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

/// キャレット位置で入力途中になっているタグ。入力サジェストの対象を決めるのに使う。
struct MemoDraftTag: Equatable, Sendable {
    /// 置き換え対象の範囲（`#` を含む）
    let range: Range<String.Index>
    /// キャレットまでに書かれた本体の正規化キー。`#` を打っただけなら空文字
    let partialKey: String
}

enum MemoTagParser {
    /// 正規化後の上限。超えたものは切り捨てずタグとして認識しない（設計メモ 前提3）
    static let maxKeyLength = 30

    /// メモ本文からタグを出現順に抽出する。
    ///
    /// `#` は **行頭・空白・改行の直後**、または **直前のタグが終わった位置** にある場合だけ
    /// タグの開始と見なす（設計メモ 3.2節）。この条件が無いと URL の
    /// `https://example.com/#section` や `C#の本` を拾ってしまう。誤検出は既存のメモに黙って
    /// ゴミタグを生やすが、取りこぼしはユーザーが空白を1つ入れれば直せるため、静かに壊れる
    /// ほうを潰す判断を採っている。連続タグ（`#京都#奈良`）だけは日本語圏で標準的な
    /// 書き方なので例外的に許す
    nonisolated static func parse(_ text: String) -> [MemoTag] {
        var tags: [MemoTag] = []
        var index = text.startIndex
        var previous: Character?
        var followsTag = false

        while index < text.endIndex {
            let character = text[index]
            let isAtBoundary = followsTag || (previous.map(\.isWhitespace) ?? true)
            guard isOpener(character), isAtBoundary else {
                previous = character
                followsTag = false
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
            let isTag = isValidKey(key)
            if isTag {
                tags.append(MemoTag(key: key, display: String(body), range: index..<bodyEnd))
            }

            // 連続タグを許すのは**タグとして成立した直後**だけ。`##京都` のように
            // 本体が空だった場合は境界が復活しないので、2つ目の `#` も開始記号にならない
            previous = bodyEnd > bodyStart ? text[text.index(before: bodyEnd)] : character
            followsTag = isTag
            index = bodyEnd
        }

        return tags
    }

    /// キャレットの直前で入力途中になっているタグを返す（無ければ nil）。
    ///
    /// 境界や文字種の規則は `parse(_:)` の結果をそのまま使って判定する。入力途中のタグも
    /// それ自体が成立したタグなので、**キャレットで終わるタグ**がそれである。唯一の例外は
    /// `#` を打っただけの状態で、本体が空でタグとして成立しないため個別に拾う
    /// （既存タグを全部出せる、サジェストとしては最も役に立つ瞬間なので落とせない）
    nonisolated static func draftTag(in text: String, before caret: String.Index) -> MemoDraftTag? {
        let tags = parse(text)

        if let typing = tags.first(where: { $0.range.upperBound == caret }) {
            return MemoDraftTag(range: typing.range, partialKey: typing.key)
        }

        guard caret > text.startIndex else { return nil }
        let opener = text.index(before: caret)
        guard isOpener(text[opener]) else { return nil }

        let isAtBoundary = opener == text.startIndex
            || text[text.index(before: opener)].isWhitespace
            || tags.contains { $0.range.upperBound == opener }
        guard isAtBoundary else { return nil }

        return MemoDraftTag(range: opener..<caret, partialKey: "")
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
        return !key.allSatisfy(isDecimalDigit)
    }

    /// 「数字のみ無効」の判定は**十進数字（`Nd`）に限る**。`Character.isNumber` は `京` や `十`
    /// のように数値を持つ漢字も数字と見なすため、それだと `#京` のような正当なタグまで弾かれる
    private nonisolated static func isDecimalDigit(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return character.unicodeScalars.count == 1
            && scalar.properties.generalCategory == .decimalNumber
    }
}
