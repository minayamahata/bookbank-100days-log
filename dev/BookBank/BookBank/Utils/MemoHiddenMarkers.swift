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
//     そうしないと打った文字が `> ` の前に入り、引用そのものが壊れる。
//     ただし**行頭に記号が続くときは装飾の外側に置く**（`> [[京都]]…` の行頭は `[[` の前）——
//     送り先が次の装飾の内側になると、行頭に見える位置がつながりの中になってしまう
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
        let markers = markers(in: text)
        var index = caret
        var moved = true
        while moved {
            moved = false
            for marker in markers {
                let inside = marker.isLineLeading
                    ? (marker.range.lowerBound <= index && index < marker.range.upperBound)
                    : (marker.range.lowerBound < index && index < marker.range.upperBound)
                if inside {
                    index = marker.range.upperBound
                    moved = true
                }
            }
        }

        // 行頭から記号しか無いところまでは、装飾の**外側**（記号の前）へ戻す
        // （**2026-08-12 オーナー報告A**——引用の冒頭がつながりだと、`> ` を飛ばした先が
        // そのまま `[[` の中になり、行頭に見える位置がつながりの内側だった。
        // そこでEnterを押すと「括弧の外へ出る」規則が先に効いて、引用の上に行を足せない）
        guard !isInsideEmptyPair(index, in: text) else { return index }
        let head = lineHead(before: index, in: text)
        guard head < index else { return index }

        var scan = head
        while scan < index {
            guard markers.contains(where: { $0.range.contains(scan) }) else { return index }
            scan = text.index(after: scan)
        }
        return head
    }

    /// その行でキャレットが取れるいちばん前の位置。引用行は `> ` の先（前は行頭ではない）
    private static func lineHead(before index: String.Index, in text: String) -> String.Index {
        let start = text[..<index].lastIndex(where: \.isNewline)
            .map { text.index(after: $0) } ?? text.startIndex
        guard text[start...].hasPrefix("> ") else { return start }
        return text.index(start, offsetBy: 2)
    }

    /// 中身が空の `[[]]`／`****` の括弧のあいだか。ボタンを押した直後にキャレットが立つ
    /// 場所なので、行頭にあっても外へ出さない（出すと押しても何も書けなくなる）
    private static func isInsideEmptyPair(_ index: String.Index, in text: String) -> Bool {
        let links = MemoLinkParser.emptyPairs(in: text)
            .map { text.index($0.lowerBound, offsetBy: 2) }
        let bolds = MemoLinkText.boldPairs(in: text)
            .filter { $0.body.isEmpty }
            .map { $0.body.lowerBound }
        return links.contains(index) || bolds.contains(index)
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

    // MARK: - まとまり削除（設計メモ 4.6節）

    /// 削除範囲が隠れた記号に触れていれば、まとまりごと消すべき範囲の一覧。
    /// 1文字削除も範囲削除も同じ規則——触れた記号の装飾を片側だけ残さない。
    /// 触れていなければ `nil`（通常の削除へ）
    static func bulkDeletionTargets(covering range: NSRange, in text: String) -> [NSRange]? {
        guard range.length >= 1, range.location >= 0 else { return nil }
        let nsLength = (text as NSString).length
        guard range.location < nsLength else { return nil }

        var targets: [NSRange] = []
        let end = min(range.location + range.length, nsLength)
        for location in range.location..<end {
            if let group = deletionGroup(at: location, in: text) {
                targets.append(contentsOf: group)
            }
        }
        guard !targets.isEmpty else { return nil }

        // 範囲削除では選んだ本文も一緒に消す（記号だけ広げて本文が残るのを防ぐ）
        if range.length > 1 {
            targets.append(range)
        }
        return mergedRanges(targets)
    }

    /// `index` の文字が隠した記号なら、まとめて消すべき範囲。記号でなければ `nil`
    static func deletionGroup(at index: Int, in text: String) -> [NSRange]? {
        let links = MemoLinkParser.parse(text)

        for link in links {
            let range = NSRange(link.range, in: text)
            let openingEnd = range.location + 2
            let closingStart = range.location + range.length - 2
            if (index >= range.location && index < openingEnd)
                || (index >= closingStart && index < range.location + range.length) {
                return [range]
            }
        }

        for pair in MemoLinkParser.emptyPairs(in: text) {
            let range = NSRange(pair, in: text)
            if NSLocationInRange(index, range) { return [range] }
        }

        let boldMarkers = MemoLinkText
            .pairedBoldMarkers(in: text, excluding: links.map(\.range))
            .sorted()
        for pairStart in stride(from: 0, to: boldMarkers.count - 1, by: 2) {
            let pair = [boldMarkers[pairStart], boldMarkers[pairStart + 1]].map { marker in
                NSRange(marker..<text.index(marker, offsetBy: 2), in: text)
            }
            if pair.contains(where: { NSLocationInRange(index, $0) }) {
                return pair
            }
        }

        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
        let prefix = NSRange(location: lineRange.location, length: 2)
        if lineRange.length >= 2, nsText.substring(with: prefix) == "> ",
           index == lineRange.location || index == lineRange.location + 1 {
            guard let page = emptyPageLine(after: lineRange, in: nsText) else { return [prefix] }
            return [prefix, page]
        }

        return nil
    }

    /// 重なる／隣接する範囲を1つにまとめる（後ろから消すときに二重に削らない）
    static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges
            .filter { $0.length > 0 && $0.location >= 0 }
            .sorted { $0.location < $1.location }
        guard var current = sorted.first else { return [] }
        var result: [NSRange] = []
        for next in sorted.dropFirst() {
            let currentEnd = NSMaxRange(current)
            if next.location <= currentEnd {
                current = NSRange(
                    location: current.location,
                    length: max(currentEnd, NSMaxRange(next)) - current.location
                )
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    /// `line` の次が数字未入力の出典ページの行なら、その行（手前の改行を含む）
    private static func emptyPageLine(after line: NSRange, in nsText: NSString) -> NSRange? {
        let next = NSMaxRange(line)
        guard next < nsText.length else { return nil }
        let pageLine = nsText.lineRange(for: NSRange(location: next, length: 0))
        let content = nsText.substring(with: pageLine)
            .trimmingCharacters(in: .newlines)
        guard MemoQuotePage.digits(inPageOnlyLine: content)?.isEmpty == true else { return nil }
        return NSRange(location: next - 1, length: content.count + 1)
    }
}
