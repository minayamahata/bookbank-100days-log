//
//  MemoTextBlocks.swift
//  BookBank
//
//  メモ本文の表示用のブロック分割とページ番号の検出（docs/memo-tagging-design.md 4.6節）。
//  引用は「> 」の記号ではなくUI（薄いグレーの囲み）で表現するため、行単位で
//  引用ブロックと通常ブロックに分ける。どちらも Foundation のみの純関数で、
//  View に依存しないためユニットテスト対象にできる（実装ガイド 5章）。
//

import Foundation

/// メモ本文を表示用に分割したブロック。連続する引用行はひとつの囲みにまとめる
enum MemoTextBlock: Equatable, Sendable {
    case paragraph(String)
    /// `> ` を取り除いた中身。複数行の引用は改行で連結される
    case quote(String)
    /// 引用の出典ページ（引用ブロックの直後の行に `p.42` だけを置く形）。数字部分のみ。
    /// 引用には必ず出典ページがあるという前提で、囲みの枠外・右下に表示する（設計メモ 4.6節）
    case quotePage(String)
}

enum MemoTextBlocks {
    /// 行頭が `> `（半角・空白必須）の行を引用として分割する。
    /// `>` 単独や `>text` は解釈しない（「ボタンで入れたものだけが装飾になる」約束＝設計メモ 0.4節）
    static func parse(_ memo: String) -> [MemoTextBlock] {
        var blocks: [MemoTextBlock] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines = []
        }
        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(quoteLines.joined(separator: "\n")))
            quoteLines = []
        }

        for line in memo.components(separatedBy: "\n") {
            if line.hasPrefix("> ") {
                flushParagraph()
                quoteLines.append(String(line.dropFirst(2)))
                continue
            }
            // 引用の直後の「p.数字」だけの行は、その引用の出典ページとして扱う
            if !quoteLines.isEmpty, let digits = MemoQuotePage.digits(inPageOnlyLine: line) {
                flushQuote()
                blocks.append(.quotePage(digits))
                continue
            }
            flushQuote()
            paragraphLines.append(line)
        }
        flushParagraph()
        flushQuote()
        return blocks
    }

    /// 連続する引用行をひとつのまとまりとして、その文字範囲を返す（改行は含まない）。
    /// 編集画面が囲みを自前で描くために使う（設計メモ 4.6節）
    static func quoteBlockRanges(in memo: String) -> [NSRange] {
        var blocks: [NSRange] = []
        var current: NSRange?

        (memo as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (memo as NSString).length),
            options: [.byLines]
        ) { line, lineRange, _, _ in
            guard line?.hasPrefix("> ") == true else {
                if let open = current { blocks.append(open) }
                current = nil
                return
            }
            current = current.map { NSUnionRange($0, lineRange) } ?? lineRange
        }

        if let open = current { blocks.append(open) }
        return blocks
    }

    /// 引用ブロックの直後にあるページ行の範囲（改行は含まない）。編集画面の右下寄せに使う
    static func quotePageLineRanges(in memo: String) -> [NSRange] {
        let nsText = memo as NSString
        return quoteBlockRanges(in: memo).compactMap { block in
            let lineStart = NSMaxRange(block) + 1  // ブロック末尾の改行の次
            guard lineStart < nsText.length else { return nil }
            var line = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            if nsText.substring(with: line).hasSuffix("\n") { line.length -= 1 }
            guard MemoQuotePage.digits(inPageOnlyLine: nsText.substring(with: line)) != nil
            else { return nil }
            return line
        }
    }
}

/// 引用の出典ページ（引用ブロックの直後の行の `p.42`）。
/// 入力は任意なので、数字が入らなかった行は保存時に取り除く（設計メモ 4.6節）
enum MemoQuotePage {
    /// 「p.」または「p.数字」だけの行なら数字部分（未入力なら空文字）を返す。それ以外は nil
    static func digits(inPageOnlyLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        var characters = Array(trimmed)
        guard characters[0] == "p" || characters[0] == "P", characters[1] == "." else { return nil }
        characters.removeFirst(2)
        guard characters.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(characters)
    }

    /// 引用の中で改行したときに飛ばす先（その引用の出典ページの行末）。引用の中でなければ nil。
    /// 引用の中で改行できると囲みが途中で割れ、出典ページの行も宛先を失う——
    /// 引用のあとに書くことは出典ページなので、改行はそこへの移動として扱う（2026-08-12 オーナー指示）
    static func pageCaretLocation(forReturnAt location: Int, in memo: String) -> Int? {
        guard let block = MemoTextBlocks.quoteBlockRanges(in: memo).first(where: {
            NSLocationInRange(location, $0) || location == NSMaxRange($0)
        }) else { return nil }
        guard let page = MemoTextBlocks.quotePageLineRanges(in: memo).first(where: {
            $0.location == NSMaxRange(block) + 1
        }) else { return nil }
        return NSMaxRange(page)
    }

    /// 出典ページの行では、キャレットを `p.` の直後より前に置かない。
    /// 数字を打つ場所は `p.` の後ろだけで、案内を出している行は文字が幅ゼロなので
    /// どこを触っても行頭に入りうる——そのまま打つと「21p.」の順になり、ページの行としても
    /// 成立しなくなる（右下寄せもバッジも外れる）
    static func caretLocation(snapping location: Int, in text: String) -> Int {
        guard let line = MemoTextBlocks.quotePageLineRanges(in: text).first(where: {
            NSLocationInRange(location, $0) || location == NSMaxRange($0)
        }) else { return location }
        return max(location, line.location + 2)
    }

    /// 出典ページの行が無い引用の、行末の位置（そこへ `"\np."` を挿す）。
    /// 編集画面は入力のたびにこれを埋め直し、**案内を常に出しておく**（2026-08-11 オーナー指示）——
    /// 一度消すと二度と入力できなくなるため。数字が入らなければ保存時に落ちるのでメモには残らない
    static func pageLineInsertions(in memo: String) -> [Int] {
        let lines = memo.components(separatedBy: "\n")
        var offsets: [Int] = []
        var location = 0

        for (index, line) in lines.enumerated() {
            defer { location += (line as NSString).length + 1 }  // 改行の1文字を含めて進む
            guard line.hasPrefix("> ") else { continue }
            // 引用が続くならこの行はブロックの途中。ページ行が既にあるなら足さない
            let following = index + 1 < lines.count ? lines[index + 1] : nil
            if let following,
               following.hasPrefix("> ") || digits(inPageOnlyLine: following) != nil { continue }
            offsets.append(location + (line as NSString).length)
        }
        return offsets
    }

    /// `pageLineInsertions` を当てた文字列
    static func ensuringPageLines(in memo: String) -> String {
        let text = NSMutableString(string: memo)
        for offset in pageLineInsertions(in: memo).sorted(by: >) {
            text.insert("\np.", at: offset)
        }
        return text as String
    }

    /// 出典ページの行が本文の末尾にあるとき、その下に足す空行の位置（無ければ `nil`）。
    /// ページ行はキャレットを `p.` の後ろへ押し戻すので、末尾にあると**そこから先へ出られない**——
    /// テンキーには改行キーも文字へ戻る鍵も無いため、行き先の行そのものを用意しておく
    static func trailingBlankLineInsertion(in memo: String) -> Int? {
        let length = (memo as NSString).length
        let hasTrailingPageLine = MemoTextBlocks.quotePageLineRanges(in: memo)
            .contains { NSMaxRange($0) == length }
        return hasTrailingPageLine ? length : nil
    }

    /// 編集画面に載せる形。出典ページの案内と、その下の行き先の行を用意する
    static func preparedForEditing(_ memo: String) -> String {
        let ensured = ensuringPageLines(in: memo)
        return trailingBlankLineInsertion(in: ensured) == nil ? ensured : ensured + "\n"
    }

    /// 数字が未入力の出典ページ行では `p.` を消せない（消すと案内が消え、入力する場所を失う）。
    /// 直前の改行も守る——消すと `p.` が引用の行に流れ込んでしまう。
    /// 数字はふつうに消せて、最後の1文字を消すと案内に戻る
    static func protectsDeletion(of range: NSRange, in text: String) -> Bool {
        let nsText = text as NSString
        for line in MemoTextBlocks.quotePageLineRanges(in: text)
        where digits(inPageOnlyLine: nsText.substring(with: line))?.isEmpty == true {
            // 行の直前の改行と `p.` の2文字
            let marker = NSRange(location: line.location - 1, length: min(3, line.length + 1))
            if NSIntersectionRange(marker, range).length > 0 { return true }
        }
        return false
    }

    /// 出典ページの行を足すか。既にページ行がある／続きが引用行のときは足さない
    static func lineToAppend(in text: String, after index: String.Index) -> String {
        let following = followingLine(in: text, after: index)
        guard !following.hasPrefix("> "), digits(inPageOnlyLine: following) == nil else { return "" }
        return "\np."
    }

    /// `index` の直後の行（`index` が改行の上に無ければ「次の行は無い」とみなす）
    private static func followingLine(in text: String, after index: String.Index) -> String {
        guard index < text.endIndex, text[index].isNewline else { return "" }
        let start = text.index(after: index)
        let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
        return String(text[start..<end])
    }

    /// 数字が入らなかったページ行を取り除く（保存時）
    static func removingEmptyPageLines(from memo: String) -> String {
        var kept: [String] = []
        for line in memo.components(separatedBy: "\n") {
            if let digits = digits(inPageOnlyLine: line), digits.isEmpty,
               kept.last?.hasPrefix("> ") == true {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }
}

/// ツールバーの「書式クリア」。メモ全体から装飾を外す（2026-08-11 オーナー確定）。
/// `**`・`[[ ]]`・行頭の `> ` に加え、**ページ番号は数字ごと落とす**（同日指示——数字を残すと
/// 装飾が消えないため）。取り消せる操作なので、意図せず消えても「ひとつ戻す」で戻せる。
/// ペアになっていない `**` や閉じていない `[[` は本文の文字なので触らない
enum MemoPlainText {
    static func stripped(from memo: String) -> String {
        var text = MemoQuotePage.removingEmptyPageLines(from: memo)
        // 中身を書かなかった `[[ ]]` は画面に見えていないので、装飾ではなく残りかすとして落とす
        text = MemoLinkParser.removingEmptyPairs(from: text)

        // 外す範囲を集めてから後ろから消す（前から消すと位置がずれる）
        var removals: [Range<String.Index>] = []
        let links = MemoLinkParser.parse(text)
        let linkRanges = links.map(\.range)
        for link in links {
            removals.append(link.range.lowerBound..<text.index(link.range.lowerBound, offsetBy: 2))
            removals.append(text.index(link.range.upperBound, offsetBy: -2)..<link.range.upperBound)
        }
        for marker in MemoLinkText.pairedBoldMarkers(in: text, excluding: linkRanges) {
            removals.append(marker..<text.index(marker, offsetBy: 2))
        }
        // ページ番号だけの行は行ごと落とす（空行を残さない）
        removals.append(contentsOf: pageOnlyLines(in: text))
        // 文中のページ番号はその部分だけ（つながりのラベルの中は触らない）
        for page in MemoPageMarker.ranges(in: text)
        where !linkRanges.contains(where: { $0.contains(page.lowerBound) })
            && !removals.contains(where: { $0.contains(page.lowerBound) }) {
            removals.append(page)
        }

        for removal in removals.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            text.removeSubrange(removal)
        }

        // 引用は行単位なので最後にまとめて外す
        return text.components(separatedBy: "\n")
            .map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }
            .joined(separator: "\n")
    }

    /// ページ番号しか書かれていない行（前後の改行を1つ含める）
    private static func pageOnlyLines(in text: String) -> [Range<String.Index>] {
        var lines: [Range<String.Index>] = []
        var lineStart = text.startIndex
        while true {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            if MemoQuotePage.digits(inPageOnlyLine: String(text[lineStart..<lineEnd])) != nil {
                if lineEnd < text.endIndex {
                    lines.append(lineStart..<text.index(after: lineEnd))
                } else {
                    // 最後の行なら手前の改行ごと落とす
                    let start = lineStart > text.startIndex
                        ? text.index(before: lineStart) : lineStart
                    lines.append(start..<lineEnd)
                }
            }
            guard lineEnd < text.endIndex else { return lines }
            lineStart = text.index(after: lineEnd)
        }
    }
}

/// ツールバーの「引用」が本文に加える差分。引用は行単位の仕組みなので、行の一部を選んだときは
/// その部分だけを独立した行に切り出す（2026-08-11 オーナー指示）。
/// 出典ページの行までここで組み立てる——経路ごとに足していた実装で無選択の経路が漏れたため
enum MemoQuoteInsertion {
    struct Result: Equatable {
        let replaced: Range<String.Index>
        let text: String
        /// 置き換え開始から数えたキャレット位置（引用した文字の末尾＝ページ行の手前）
        let caretOffset: Int
    }

    static func make(in text: String, selecting range: Range<String.Index>) -> Result {
        let selected = String(text[range])

        // 無選択ならキャレットのある行をまるごと引用にする
        guard !selected.isEmpty else {
            let lineStart = text[..<range.lowerBound].lastIndex(where: \.isNewline)
                .map { text.index(after: $0) } ?? text.startIndex
            let lineEnd = text[range.lowerBound...].firstIndex(where: \.isNewline) ?? text.endIndex
            return Result(
                replaced: lineStart..<lineEnd,
                text: "> " + text[lineStart..<lineEnd]
                    + MemoQuotePage.lineToAppend(in: text, after: lineEnd),
                caretOffset: text.distance(from: lineStart, to: range.lowerBound) + 2
            )
        }

        // 複数行を選んだ場合は各行に付ける（連続する引用行はひとつの囲みにまとまる）
        let quoted = selected.components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
        // 選択が行の途中から始まる／途中で終わるときだけ改行で行を切る（空行を増やさない）
        let opensLine = range.lowerBound == text.startIndex
            || text[text.index(before: range.lowerBound)].isNewline
        let closesLine = range.upperBound == text.endIndex || text[range.upperBound].isNewline
        return Result(
            replaced: range,
            text: (opensLine ? "" : "\n") + quoted
                + MemoQuotePage.lineToAppend(in: text, after: range.upperBound)
                + (closesLine ? "" : "\n"),
            caretOffset: (opensLine ? 0 : 1) + quoted.count
        )
    }
}

enum MemoPageMarker {
    /// `p.`（または `P.`）＋半角数字1つ以上をページ番号として検出する。
    /// ツールバーのページ番号ボタンが挿す形（設計メモ 4.5節）で、表示側はこれをバッジにする。
    /// 直前が英数字の場合は不成立（`stop.123` の中の `p.123` を拾わない）。
    /// 日本語文は語間に空白が無いので、境界は「英数字でないこと」に留める（`本文p.42` は拾う）
    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "p" || character == "P",
                  previous.map({ !isASCIIAlphanumeric($0) }) ?? true else {
                previous = character
                index = text.index(after: index)
                continue
            }

            let dot = text.index(after: index)
            guard dot < text.endIndex, text[dot] == "." else {
                previous = character
                index = dot
                continue
            }

            var digitsEnd = text.index(after: dot)
            while digitsEnd < text.endIndex, isASCIIDigit(text[digitsEnd]) {
                digitsEnd = text.index(after: digitsEnd)
            }
            guard text.distance(from: dot, to: digitsEnd) > 1 else {
                // `p.` だけで数字が続かない。`.` の次から読み直す
                previous = text[dot]
                index = digitsEnd
                continue
            }

            result.append(index..<digitsEnd)
            previous = text[text.index(before: digitsEnd)]
            index = digitsEnd
        }

        return result
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
