//
//  MemoTagParser.swift
//  BookBank
//
//  メモ本文から `#タグ` を抽出する純関数（docs/memo-tagging-design.md 3.2節）。
//  タグはスキーマを持たず「メモの中に既にある文字列」なので、表示・サジェスト・
//  絞り込みのすべてがこのパーサの結果から導出される（同 3.3節）。
//  View に依存しないためユニットテスト対象にできる（実装ガイド 5章）。
//

import Foundation

/// メモ本文から抽出したタグ1件。
struct MemoTag: Equatable, Hashable, Sendable {
    /// 同一視・インデックスのキーに使う正規化済みの綴り（NFKC＋小文字化・`#` を含まない）
    let key: String
    /// メモに書かれたままの綴り（`#` を含まない）。チップのラベル等、人に見せる用
    let display: String
    /// メモ本文中の範囲。**`#` を含む**（ハイライトを当てる範囲そのもの）
    let range: Range<String.Index>
}

enum MemoTagParser {
    /// 正規化後の上限。超えたものは切り捨てずタグとして認識しない（設計メモ 前提3）
    static let maxKeyLength = 30

    /// メモ本文からタグを出現順に抽出する。
    ///
    /// `#` の直前が行頭・空白・改行のいずれかである場合だけタグの開始と見なす（設計メモ 3.2節）。
    /// この条件が無いと URL の `https://example.com/#section` や `C#の本` を拾ってしまう。
    /// 誤検出は既存のメモに黙ってゴミタグを生やすが、取りこぼしはユーザーが空白を
    /// 1つ入れれば直せるため、静かに壊れるほうを潰す判断を採っている。
    nonisolated static func parse(_ text: String) -> [MemoTag] {
        var tags: [MemoTag] = []
        var index = text.startIndex
        var previous: Character?

        while index < text.endIndex {
            let character = text[index]
            let isAtBoundary = previous.map(\.isWhitespace) ?? true
            guard isOpener(character), isAtBoundary else {
                previous = character
                index = text.index(after: index)
                continue
            }

            let bodyStart = text.index(after: index)
            var bodyEnd = bodyStart
            while bodyEnd < text.endIndex, isBodyCharacter(text[bodyEnd]) {
                bodyEnd = text.index(after: bodyEnd)
            }

            let body = text[bodyStart..<bodyEnd]
            let key = normalize(String(body))
            if isValidKey(key) {
                tags.append(MemoTag(key: key, display: String(body), range: index..<bodyEnd))
            }

            // 本体を読み切った位置から再開する。直前文字を本体の末尾に進めることで、
            // `#京都#奈良` の2つ目のように境界を満たさない `#` が開始記号にならない
            previous = bodyEnd > bodyStart ? text[text.index(before: bodyEnd)] : character
            index = bodyEnd
        }

        return tags
    }

    /// タグの同一視キーを作る（NFKC＋小文字化）。
    ///
    /// ノードのキーワード抽出と同じ正規化であり（設計メモ 前提4）、**本棚内検索の
    /// `ShelfSearchMatcher.normalize` とは意図的に別物**。あちらはひらがなをカタカナへ寄せて
    /// 表記ゆれを吸収するが、タグはユーザーが書き分けたものを区別するのが目的なので寄せない。
    /// 加えてタグはT2で `bookIndex.keywords` に載りノード側の抽出語と突き合わされるため、
    /// ノードの正規化と揃っている必要がある（設計メモ 3.2節）
    nonisolated static func normalize(_ rawTag: String) -> String {
        rawTag.precomposedStringWithCompatibilityMapping.lowercased()
    }

    /// 半角 `#` と全角 `＃` の両方を開始記号として受ける。
    /// 日本語IMEのかな入力では全角が出るため、ここを受けないと日本語ユーザーがタグを打てない
    private nonisolated static func isOpener(_ character: Character) -> Bool {
        character == "#" || character == "＃"
    }

    /// タグ本体に使える文字か（Unicode一般カテゴリ `L*` / `M*` / `N*` と `_`・設計メモ 前提2）。
    /// ハイフンは含めない——許すと全角ダーシや文末のダッシュまで拾い始めるため
    private nonisolated static func isBodyCharacter(_ character: Character) -> Bool {
        if character == "_" { return true }

        // キーキャップ絵文字（`1️⃣`）は基底が数字なのでカテゴリだけでは弾けない
        let isEmoji = character.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F
        }
        if isEmoji { return false }

        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// 空・数字のみ・上限超過を弾く（設計メモ 前提3）
    private nonisolated static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= maxKeyLength else { return false }
        return !key.allSatisfy(\.isNumber)
    }
}
