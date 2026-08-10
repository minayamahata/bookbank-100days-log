//
//  MemoLinkParser.swift
//  BookBank
//
//  メモ本文から `[[ ]]`（つながり）を抽出する純関数（docs/memo-tagging-design.md 3.2節）。
//  つながりはスキーマを持たず「メモの中に既にある文字列」なので、表示・サジェスト・
//  絞り込みのすべてがこのパーサの結果から導出される（同 3.3節）。
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

/// キャレット位置で入力途中になっているつながり。入力サジェストの対象を決めるのに使う。
struct MemoDraftLink: Equatable, Sendable {
    /// 候補で置き換える範囲。`[[` から、キャレット直後に閉じ括弧が続く場合はそこまで含む
    let range: Range<String.Index>
    /// `[[` からキャレットまでに書かれたラベルの正規化キー。`[[` だけなら空文字
    let partialKey: String
}

enum MemoLinkParser {
    /// 正規化後の上限。超えたものは切り捨てずつながりとして認識しない（設計メモ 前提3）
    static let maxKeyLength = 30

    /// メモ本文からつながりを出現順に抽出する。
    ///
    /// `[[ ]]` は区切りが明示的なので、`#` 記法時代の直前境界規則は不要（設計メモ 3.2節）。
    /// 中身は任意の文字列（空白・句読点・記号・絵文字可）だが、**改行を含む場合は不成立**
    /// ——行をまたぐと表示も崩れるうえ、閉じ忘れの `[[` が後続行の `]]` と誤って結合する
    /// 事故もこれで防げる。入れ子はなく、最初の `]]` で閉じる
    nonisolated static func parse(_ text: String) -> [MemoLink] {
        var links: [MemoLink] = []
        var index = text.startIndex

        while let opener = pair(of: isOpenBracket, in: text, from: index) {
            // 閉じ括弧は同じ行の中でだけ探す。見つからなければこの `[[` は不成立で、
            // 1文字だけ進めて探し直す（`[[a\n[[b]]` の2つ目を取りこぼさないため）
            guard let closer = closerPair(in: text, from: opener.upperBound) else {
                index = text.index(after: opener.lowerBound)
                continue
            }

            let body = String(text[opener.upperBound..<closer.lowerBound])
            let key = normalize(body)
            if isValidKey(key) {
                links.append(
                    MemoLink(
                        key: key,
                        display: body.trimmingCharacters(in: .whitespaces),
                        range: opener.lowerBound..<closer.upperBound
                    )
                )
            }
            index = closer.upperBound
        }

        return links
    }

    /// キャレットの位置で入力途中になっているつながりを返す（無ければ nil）。
    ///
    /// キャレットと同じ行を後方に走査し、まだ `]]` で閉じられていない `[[` を探す。
    /// キャレットの直後（同じ行）に `]]` が続く場合は範囲をそこまで広げる——ツールバーの
    /// 「つなぐ」が `[[]]` を挿入してキャレットを括弧の中に置く形（設計メモ 4.5節）と、
    /// 既存のつながりの中身を編集し直す形の両方が、候補タップで丸ごと置き換わる
    nonisolated static func draftLink(in text: String, before caret: String.Index) -> MemoDraftLink? {
        guard let openerStart = unclosedOpenerStart(in: text, before: caret) else { return nil }

        let bodyStart = text.index(openerStart, offsetBy: 2)
        let partialKey = normalize(String(text[bodyStart..<caret]))
        guard partialKey.count <= maxKeyLength else { return nil }

        let end = trailingCloserEnd(in: text, from: caret) ?? caret
        return MemoDraftLink(range: openerStart..<end, partialKey: partialKey)
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

    /// キャレットと同じ行を後方に走査し、まだ閉じられていない `[[` の開始位置を返す。
    /// 途中で `]]` か改行に当たったら、キャレットの手前につながりは開いていない
    private nonisolated static func unclosedOpenerStart(
        in text: String,
        before caret: String.Index
    ) -> String.Index? {
        var index = caret
        while index > text.startIndex {
            let current = text.index(before: index)
            let character = text[current]
            if character.isNewline { return nil }
            if current > text.startIndex {
                let previous = text.index(before: current)
                if isCloseBracket(character), isCloseBracket(text[previous]) { return nil }
                if isOpenBracket(character), isOpenBracket(text[previous]) { return previous }
            }
            index = current
        }
        return nil
    }

    /// キャレット以降、同じ行の中で `]]` が（新しい `[[` より先に）現れるならその終端。
    /// 現れなければ nil（範囲はキャレットまでで、候補は挿入になる）
    private nonisolated static func trailingCloserEnd(
        in text: String,
        from caret: String.Index
    ) -> String.Index? {
        var index = caret
        while index < text.endIndex {
            let character = text[index]
            if character.isNewline { return nil }
            let next = text.index(after: index)
            if next < text.endIndex {
                if isCloseBracket(character), isCloseBracket(text[next]) {
                    return text.index(after: next)
                }
                if isOpenBracket(character), isOpenBracket(text[next]) { return nil }
            }
            index = next
        }
        return nil
    }
}
