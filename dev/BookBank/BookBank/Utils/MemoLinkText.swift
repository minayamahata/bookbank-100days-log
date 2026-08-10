//
//  MemoLinkText.swift
//  BookBank
//
//  メモ本文の表示用テキストを組み立てる（docs/memo-tagging-design.md 4.6節）。
//  つながりの検出そのものは `MemoLinkParser`（Foundationのみの純関数）が担い、
//  ここは記号を隠して装飾を当てる表示側の薄い層に留める。
//
//  解釈するのは**ツールバーが出せるものだけ**（同 0.4節）:
//  `[[ ]]`（記号を隠して着色）・`**` のペア（太字）・行頭の `> `（引用）。
//  見出し・箇条書き・斜体・リンク等の他のMarkdown記法は解釈しない。
//

import SwiftUI

enum MemoLinkText {
    /// 引用行の行頭で `> ` の代わりに出す縦線。1つの `Text` の中で塗れる最小の引用装飾
    private static let quoteBar = "│ "

    /// メモ本文を表示用の `AttributedString` に組み立てる。
    ///
    /// - `[[中身]]`: 記号を隠し、中身だけ `color`＋セミボールドで着色
    /// - `**中身**`: 記号を隠して太字。ペアが同じ行で閉じている場合のみ（`*` 1つの斜体は解釈しない）
    /// - 行頭の `> `: 記号を縦線に置き換え、行全体を二次色に
    ///
    /// 記号を隠すため表示文字列は原文と一致しない。不変条件は「**解釈対象の記号以外の
    /// 文字は一切加工しない**」（設計メモ 4.6節・テストで固定）。編集画面は記号を出したまま
    static func highlighted(_ memo: String, color: Color) -> AttributedString {
        let links = MemoLinkParser.parse(memo)
        let linksByStart = Dictionary(uniqueKeysWithValues: links.map { ($0.range.lowerBound, $0) })
        let boldMarkers = pairedBoldMarkers(in: memo, excluding: links.map(\.range))

        var result = AttributedString()
        var buffer = ""
        var isBold = false
        var isQuote = false
        var atLineStart = true
        var index = memo.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            var part = AttributedString(buffer)
            if isBold { part.inlinePresentationIntent = .stronglyEmphasized }
            if isQuote { part.foregroundColor = .secondary }
            result += part
            buffer = ""
        }

        while index < memo.endIndex {
            if atLineStart {
                atLineStart = false
                isQuote = false
                if isQuoteMarker(in: memo, at: index) {
                    flush()
                    isQuote = true
                    var bar = AttributedString(quoteBar)
                    bar.foregroundColor = .secondary
                    result += bar
                    index = memo.index(index, offsetBy: 2)
                    continue
                }
            }

            if let link = linksByStart[index] {
                flush()
                var highlighted = AttributedString(link.display)
                highlighted.foregroundColor = color
                highlighted.font = .subheadline.weight(.semibold)
                result += highlighted
                index = link.range.upperBound
                continue
            }

            if boldMarkers.contains(index) {
                flush()
                isBold.toggle()
                index = memo.index(index, offsetBy: 2)
                continue
            }

            let character = memo[index]
            buffer.append(character)
            if character.isNewline {
                atLineStart = true
                flush()
                isBold = false
            }
            index = memo.index(after: index)
        }

        flush()
        return result
    }

    /// 行頭の `> `（半角・空白必須）だけを引用と見なす。ツールバーが挿入する形そのもので、
    /// `>` 単独や `>text` は解釈しない（「ボタンで入れたものだけが装飾になる」約束）
    private static func isQuoteMarker(in text: String, at index: String.Index) -> Bool {
        guard text[index] == ">" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == " "
    }

    /// 同じ行の中でペアが閉じている `**` の開始位置の集合。
    /// 奇数個目が余った場合や行をまたぐ場合、その `**` はただの文字として表示される。
    /// `[[ ]]` の中の `**` は数えない（中身は任意の文字列であり装飾記号ではない）
    private static func pairedBoldMarkers(
        in text: String,
        excluding excludedRanges: [Range<String.Index>]
    ) -> Set<String.Index> {
        var paired = Set<String.Index>()
        var pending: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if let excluded = excludedRanges.first(where: { $0.lowerBound == index }) {
                index = excluded.upperBound
                continue
            }
            if text[index].isNewline {
                pending = nil
                index = text.index(after: index)
                continue
            }
            let next = text.index(after: index)
            if text[index] == "*", next < text.endIndex, text[next] == "*" {
                if let opening = pending {
                    paired.insert(opening)
                    paired.insert(index)
                    pending = nil
                } else {
                    pending = index
                }
                index = text.index(after: next)
                continue
            }
            index = next
        }

        return paired
    }
}
