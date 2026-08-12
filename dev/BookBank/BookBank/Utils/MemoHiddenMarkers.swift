//
//  MemoHiddenMarkers.swift
//  BookBank
//
//  画面に出していない記号（`> `・`**`・`[[ ]]`）の位置（docs/memo-tagging-design.md 4.6節）。
//  記号は消さずに極小フォント＋透明で隠しているだけなので、行頭から範囲選択すると
//  見えていない記号まで選択に入る。ツールバーはこの範囲を外してから囲む
//  （2026-08-12 オーナー報告——引用の行頭を選んで「つなぐ」を押すと引用が解除された）。
//

import Foundation

enum MemoHiddenMarkers {
    /// 隠している記号の位置。中身を書いていない `[[]]` は4文字まとめて1つとして返す
    static func ranges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        for link in MemoLinkParser.parse(text) {
            ranges.append(link.range.lowerBound..<text.index(link.range.lowerBound, offsetBy: 2))
            ranges.append(text.index(link.range.upperBound, offsetBy: -2)..<link.range.upperBound)
        }
        ranges.append(contentsOf: MemoLinkParser.emptyPairs(in: text))
        for pair in MemoLinkText.boldPairs(in: text) {
            ranges.append(pair.range.lowerBound..<pair.body.lowerBound)
            ranges.append(pair.body.upperBound..<pair.range.upperBound)
        }

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            if text[lineStart...].hasPrefix("> ") {
                ranges.append(lineStart..<text.index(lineStart, offsetBy: 2))
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }

        return ranges
    }

    /// 選択範囲から隠れた記号を外す。両端がそれぞれ内側へ寄るだけで、範囲の中に挟まった
    /// 記号は触らない（`[[京都]]` をまたぐ選択は、そのまとまりごと囲みたいはずなので）
    static func trimming(
        _ range: Range<String.Index>,
        in text: String
    ) -> Range<String.Index> {
        let markers = ranges(in: text)
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower < upper, let marker = markers.first(where: { $0.contains(lower) }) {
            lower = min(marker.upperBound, upper)
        }
        while lower < upper,
              let marker = markers.first(where: { $0.contains(text.index(before: upper)) }) {
            upper = max(marker.lowerBound, lower)
        }
        return lower..<upper
    }
}
