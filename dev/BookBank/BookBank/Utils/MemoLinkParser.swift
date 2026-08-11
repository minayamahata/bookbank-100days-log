//
//  MemoLinkParser.swift
//  BookBank
//
//  メモ本文から `[[ ]]`（つながり）を抽出する純関数（docs/memo-tagging-design.md 3.2節）。
//  つながりはスキーマを持たず「メモの中に既にある文字列」なので、表示・絞り込みの
//  すべてがこのパーサの結果から導出される（同 3.3節）。
//  View に依存しないためユニットテスト対象にできる（実装ガイド 5章）。
//

import Foundation

/// メモ本文から抽出したつながり1件。
struct MemoLink: Equatable, Hashable, Sendable {
    /// 同一視・インデックスのキーに使う正規化済みのラベル（トリム＋NFKC＋小文字化・括弧を含まない）
    let key: String
    /// メモに書かれたままのラベル（前後の空白のみトリム・括弧を含まない）。チップや表示用
    let display: String
    /// メモ本文中の範囲。**`[[ ]]` を含む**（表示で記号を隠すときに置き換える範囲そのもの）
    let range: Range<String.Index>
}

enum MemoLinkParser {
    /// 正規化後の上限。超えたものは切り捨てずつながりとして認識しない（設計メモ 前提3）。
    /// パーサ本体が `nonisolated` なので、この定数も画面から切り離しておく
    nonisolated static let maxKeyLength = 30

    /// メモ本文からつながりを出現順に抽出する。
    ///
    /// `[[ ]]` は区切りが明示的なので、`#` 記法時代の直前境界規則は不要（設計メモ 3.2節）。
    /// 中身は任意の文字列（空白・句読点・記号・絵文字可）だが、**改行を含む場合は不成立**
    /// ——行をまたぐと表示も崩れるうえ、閉じ忘れの `[[` が後続行の `]]` と誤って結合する
    /// 事故もこれで防げる。入れ子はなく、最初の `]]` で閉じる
    nonisolated static func parse(_ text: String) -> [MemoLink] {
        closedPairs(in: text).compactMap { pair in
            let body = String(text[pair.body])
            let key = normalize(body)
            guard isValidKey(key) else { return nil }
            return MemoLink(
                key: key,
                display: body.trimmingCharacters(in: .whitespaces),
                range: pair.range
            )
        }
    }

    /// 中身がまだ空（空白のみ）の `[[ ]]` を出現順に返す。
    ///
    /// ツールバーの「つなぐ」を押した直後の形で、つながりとしては**不成立**（3.2節）。
    /// それでも編集画面には `[[ ]]` という記号を出さない（設計メモ 4.6節・2026-08-12 オーナー指示
    /// ——Markdownを知らない人には意味が分からない）ため、隠す範囲としてここで拾う。
    /// 書かずに閉じたものは保存時に落ちる（`removingEmptyPairs`）
    nonisolated static func emptyPairs(in text: String) -> [Range<String.Index>] {
        closedPairs(in: text)
            .filter { normalize(String(text[$0.body])).isEmpty }
            .map { $0.range }
    }

    /// 中身が空のまま残った `[[ ]]` を落とす。数字が入らなかった出典ページの行と同じ扱いで、
    /// メモ本文にもエクスポートにも記号を残さない（設計メモ 4.6節）
    nonisolated static func removingEmptyPairs(from text: String) -> String {
        var result = text
        for pair in emptyPairs(in: text).reversed() {
            result.removeSubrange(pair)
        }
        return result
    }

    /// キャレットを囲んでいる `[[ ]]`（成立しているものも中身が空のものも含む）。
    /// 括弧の中でEnterを押したときの行き先を決めるのに使う（設計メモ 4.5節）
    nonisolated static func enclosingPair(
        in text: String,
        at caret: String.Index
    ) -> Range<String.Index>? {
        closedPairs(in: text)
            .first { $0.range.lowerBound < caret && caret < $0.range.upperBound }?
            .range
    }

    /// 閉じている `[[ ]]` を出現順に返す（中身の妥当性は見ない）。
    /// つながりの抽出（`parse`）と、記号を隠すための空の括弧の検出が同じ走査を共有する
    private nonisolated static func closedPairs(
        in text: String
    ) -> [(range: Range<String.Index>, body: Range<String.Index>)] {
        var pairs: [(range: Range<String.Index>, body: Range<String.Index>)] = []
        var index = text.startIndex

        while let opener = pair(of: isOpenBracket, in: text, from: index) {
            // 閉じ括弧は同じ行の中でだけ探す。見つからなければこの `[[` は不成立で、
            // 1文字だけ進めて探し直す（`[[a\n[[b]]` の2つ目を取りこぼさないため）
            guard let closer = closerPair(in: text, from: opener.upperBound) else {
                index = text.index(after: opener.lowerBound)
                continue
            }

            pairs.append(
                (
                    range: opener.lowerBound..<closer.upperBound,
                    body: opener.upperBound..<closer.lowerBound
                )
            )
            index = closer.upperBound
        }

        return pairs
    }

    /// ラベルの同一視キーを作る（前後の空白をトリム → NFKC＋小文字化）。
    ///
    /// ノードのキーワード抽出と同じ正規化であり（設計メモ 前提4）、**本棚内検索の
    /// `ShelfSearchMatcher.normalize` とは意図的に別物**。あちらはひらがなをカタカナへ寄せて
    /// 表記ゆれを吸収するが、つながりはユーザーが書き分けたものを区別するのが目的なので
    /// 寄せない。加えてT2で `bookIndex.keywords` に載りノード側の抽出語と突き合わされるため、
    /// ノードの正規化と揃っている必要がある（設計メモ 3.2節）
    nonisolated static func normalize(_ rawLabel: String) -> String {
        rawLabel.trimmingCharacters(in: .whitespaces)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }

    /// 空（空白のみ含む）・上限超過を弾く。数字のみは**有効**——旧 `#` 記法の「数字のみ無効」は
    /// 誤検出対策であり、明示的に括る `[[ ]]` には当たらない（設計メモ 前提2）
    private nonisolated static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= maxKeyLength
    }

    // MARK: - 括弧の走査

    /// 半角と全角の両方を受け、開始と終了で混ざっていてもよい（設計メモ 前提9）。
    /// 日本語IMEでは全角が出るため、手打ちを弾かない
    private nonisolated static func isOpenBracket(_ character: Character) -> Bool {
        character == "[" || character == "［"
    }

    private nonisolated static func isCloseBracket(_ character: Character) -> Bool {
        character == "]" || character == "］"
    }

    /// `from` 以降で最初に現れる、`matches` を満たす文字2連の範囲
    private nonisolated static func pair(
        of matches: (Character) -> Bool,
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var index = start
        while index < text.endIndex {
            let next = text.index(after: index)
            if matches(text[index]), next < text.endIndex, matches(text[next]) {
                return index..<text.index(after: next)
            }
            index = next
        }
        return nil
    }

    /// `from` 以降、**同じ行の中で**最初に現れる `]]` の範囲。改行に先に当たれば nil
    private nonisolated static func closerPair(
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var index = start
        while index < text.endIndex {
            if text[index].isNewline { return nil }
            let next = text.index(after: index)
            if isCloseBracket(text[index]), next < text.endIndex, isCloseBracket(text[next]) {
                return index..<text.index(after: next)
            }
            index = next
        }
        return nil
    }

}
