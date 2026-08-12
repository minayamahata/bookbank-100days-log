//
//  MemoFormatToggle.swift
//  BookBank
//
//  ツールバーの「つなぐ・太字・引用」が本文に加える差分（docs/memo-tagging-design.md 4.5節）。
//  **押すたびに付いたり外れたりするトグル**（2026-08-12 オーナー指示——連打で `[[]]` が
//  入れ子になり記号が露出していた。いま中にいるなら外すのが自然）。
//  画面の中に書くとテストで固定できないので、差分の組み立てはここに集約する。
//

import Foundation

enum MemoFormatToggle {
    struct Edit: Equatable {
        let replaced: Range<String.Index>
        let text: String
        /// 置き換え開始から数えたキャレット位置
        let caretOffset: Int
    }

    /// つながり。中にいれば括弧を外し、いなければ選択を `[[ ]]` で囲む（無選択なら空の括弧）。
    /// 囲んだあとのキャレットは `]]` の手前——続けてラベルを書ける位置に置く
    static func link(in text: String, selecting range: Range<String.Index>) -> Edit {
        if let pair = MemoLinkParser.enclosingPair(in: text, at: range.lowerBound) {
            let label = String(text[pair].dropFirst(2).dropLast(2))
            return Edit(replaced: pair, text: label, caretOffset: label.count)
        }
        let target = MemoHiddenMarkers.trimming(range, in: text)
        let selected = String(text[target])
        return Edit(
            replaced: target, text: "[[\(selected)]]", caretOffset: 2 + selected.count
        )
    }

    /// 太字。中にいれば `**` を外し、いなければ選択を囲む（無選択なら `****` の中へ）
    static func bold(in text: String, selecting range: Range<String.Index>) -> Edit {
        if let pair = MemoLinkText.enclosingBoldPair(in: text, at: range.lowerBound) {
            let content = String(text[pair.body])
            return Edit(replaced: pair.range, text: content, caretOffset: content.count)
        }
        let target = MemoHiddenMarkers.trimming(range, in: text)
        let selected = String(text[target])
        return Edit(
            replaced: target,
            text: "**\(selected)**",
            caretOffset: selected.isEmpty ? 2 : selected.count + 4
        )
    }

    /// ページ番号。付ける側は `p.` を挿すだけ（数字はユーザーが打つ）。
    /// 外す側は他のトグルに揃えて**記号だけ外す**（**2026-08-12 オーナー指示**——
    /// 光っているのにもう一度押すと `p.` が重なって入っていた）。例外が2つある:
    /// - **数字がまだ入っていない `p.` は丸ごと消す**——押し間違いの取り消しになる
    /// - **出典ページの行（ページ番号だけの行）は数字だけ落とす**——行そのものが引用の一部で、
    ///   `p.` を外すと数字だけの行が残り、その下に空のページ行が足し直される
    static func page(in text: String, selecting range: Range<String.Index>) -> Edit {
        guard let marker = MemoPageMarker.enclosing(range.lowerBound, in: text) else {
            let target = MemoHiddenMarkers.trimming(range, in: text)
            return Edit(replaced: target, text: "p.", caretOffset: 2)
        }

        let digits = text.index(marker.lowerBound, offsetBy: 2)..<marker.upperBound
        // 引用の出典ページは行そのものが引用の一部なので、数字だけ落として枠は残す
        // （`p.` を外すと数字だけの行が残り、その下に空のページ行が足し直される）。
        // 数字がまだ無ければ何もしない——消しても同じ行がすぐ足し直されるだけ
        if isQuotePageLine(marker, in: text) {
            return Edit(replaced: digits, text: "", caretOffset: 0)
        }
        if digits.isEmpty {
            return Edit(replaced: marker, text: "", caretOffset: 0)
        }
        let number = String(text[digits])
        return Edit(replaced: marker, text: number, caretOffset: number.count)
    }

    /// **引用の直後の**ページ番号だけの行か。「ページ番号だけの行」で見ると、引用と関係なく
    /// 単独の行に打った `p.42` まで巻き込み、数字のほうが消えてしまう
    /// （**2026-08-12 オーナー報告**）——引用のページ行かどうかは `MemoTextBlocks` に合わせる
    private static func isQuotePageLine(
        _ marker: Range<String.Index>,
        in text: String
    ) -> Bool {
        let location = NSRange(marker, in: text).location
        return MemoTextBlocks.quotePageLineRanges(in: text)
            .contains { NSLocationInRange(location, $0) }
    }

    /// 引用。触れている行がすべて引用なら外し、そうでなければ行頭に `> ` を入れる
    /// （出典ページの行の用意・後始末も含めて `MemoQuoteInsertion` が組み立てる）
    static func quote(in text: String, selecting range: Range<String.Index>) -> Edit {
        let target = MemoHiddenMarkers.trimming(range, in: text)
        let result = MemoQuoteInsertion.removal(in: text, selecting: target)
            ?? MemoQuoteInsertion.make(in: text, selecting: target)
        return Edit(
            replaced: result.replaced, text: result.text, caretOffset: result.caretOffset
        )
    }
}
