//
//  MemoHiddenMarkers.swift
//  BookBank
//
//  画面に出していない記号（`> `・`**`・`[[ ]]`）の位置と、**その上でのキャレットと選択の扱い**
//  （docs/memo-tagging-design.md 4.6節）。記号は消さずに極小フォント＋透明で隠しているだけなので、
//  見た目の位置と本文の位置がずれる。ずれの手当てを1か所にまとめる
//  （**2026-08-12 オーナー指示**——「引用の行頭を選んで囲むと引用が解除される」「引用の上に
//  行を足せない」と同じ構造の不具合が場面ごとに出るため、場面ごとの個別対応にしない）。
//
//  決めごとは2つだけ:
//  1. **選択範囲は見えている文字に揃える**（両端から隠れた記号を外す＝`trimming`）
//  2. **キャレットは隠れた記号の中に置かない**（記号の先へ送る＝`caretIndex`）。行頭の `> ` は
//     「記号の前」も見た目が同じ位置なので、そこも記号の中とみなして文字の側へ送る——
//     そうしないと打った文字が `> ` の前に入り、引用そのものが壊れる
//

import Foundation

enum MemoHiddenMarkers {
    struct Marker {
        let range: Range<String.Index>
        /// 行頭の記号（`> `）か。見た目に「記号の前」が無いので、キャレットの扱いが変わる
        let isLineLeading: Bool
    }

    /// 隠している記号。`[[` と `]]` は別々の2文字として返す——中身が空の `[[]]` でも
    /// **括弧のあいだ**（つなぐを押した直後にキャレットが立つ場所）は正しい位置なので、
    /// 4文字をひとまとまりにするとそこが「記号の中」になってしまう
    static func markers(in text: String) -> [Marker] {
        var markers: [Marker] = []

        // 隠しているのは「つながりとして成立している括弧」と「中身が空の括弧」だけ
        // （長すぎるラベルなどは装飾にならず、記号のまま見えている＝隠れていない）
        let pairs = MemoLinkParser.parse(text).map(\.range) + MemoLinkParser.emptyPairs(in: text)
        for pair in pairs {
            markers.append(
                Marker(
                    range: pair.lowerBound..<text.index(pair.lowerBound, offsetBy: 2),
                    isLineLeading: false
                )
            )
            markers.append(
                Marker(
                    range: text.index(pair.upperBound, offsetBy: -2)..<pair.upperBound,
                    isLineLeading: false
                )
            )
        }
        for pair in MemoLinkText.boldPairs(in: text) {
            markers.append(
                Marker(range: pair.range.lowerBound..<pair.body.lowerBound, isLineLeading: false)
            )
            markers.append(
                Marker(range: pair.body.upperBound..<pair.range.upperBound, isLineLeading: false)
            )
        }

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            if text[lineStart...].hasPrefix("> ") {
                markers.append(
                    Marker(
                        range: lineStart..<text.index(lineStart, offsetBy: 2),
                        isLineLeading: true
                    )
                )
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }

        return markers
    }

    static func ranges(in text: String) -> [Range<String.Index>] {
        markers(in: text).map(\.range)
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

    /// キャレットを置いてよい位置。隠れた記号の中にいれば**記号の先**（本文の側）へ送る。
    ///
    /// 行頭の `> ` だけは**記号の前も同じ扱い**にする——見た目には「記号の前」という位置が
    /// 存在せず、そこに文字を打つと `あ> 引用` となって引用そのものが壊れるため。
    /// 逆に `[[` や `**` は「記号の前」が見た目にも別の位置（前の文字との境目）なので、
    /// 記号の中にいるときだけ送る
    static func caretIndex(snapping caret: String.Index, in text: String) -> String.Index {
        var index = caret
        var moved = true
        while moved {
            moved = false
            for marker in markers(in: text) {
                let inside = marker.isLineLeading
                    ? (marker.range.lowerBound <= index && index < marker.range.upperBound)
                    : (marker.range.lowerBound < index && index < marker.range.upperBound)
                if inside {
                    index = marker.range.upperBound
                    moved = true
                }
            }
        }
        return index
    }

    /// `UITextView` から渡ってくる位置（UTF-16）で受ける `caretIndex`
    static func caretLocation(snapping location: Int, in text: String) -> Int {
        guard let caret = Range(NSRange(location: location, length: 0), in: text)?.lowerBound
        else { return location }
        let snapped = caretIndex(snapping: caret, in: text)
        return snapped == caret ? location : NSRange(snapped..<snapped, in: text).location
    }

    /// 引用のまとまりの**先頭行の行頭**でEnterを押したときに、改行を入れる位置（`> ` の前）。
    /// それ以外は `nil`（引用の中の改行は出典ページへの移動＝`MemoQuotePage.pageCaretLocation`）。
    ///
    /// キャレットは行頭の `> ` の先に送られている（`caretIndex`）ので、そのままでは改行が
    /// 引用の内側に入り、**引用の上に行を足せない**（2026-08-12 オーナー報告）。
    /// まとまりの途中の行では開けない——上に行きたければ1つ上の引用行を触ればよく、
    /// ここで開けると囲みが割れる（引用の中の改行を塞いだ理由と同じ）
    static func quoteOpening(forReturnAt location: Int, in text: String) -> Int? {
        let nsText = text as NSString
        guard location <= nsText.length else { return nil }
        let line = nsText.lineRange(for: NSRange(location: location, length: 0))
        guard nsText.substring(with: line).hasPrefix("> "),
              location <= line.location + 2
        else { return nil }

        // まとまりの先頭行か（1つ上の行が引用ならまとまりの途中）
        if line.location > 0 {
            let previous = nsText.lineRange(
                for: NSRange(location: line.location - 1, length: 0)
            )
            if nsText.substring(with: previous).hasPrefix("> ") { return nil }
        }
        return line.location
    }
}
