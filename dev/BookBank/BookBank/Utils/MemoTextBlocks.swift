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
            } else {
                flushQuote()
                paragraphLines.append(line)
            }
        }
        flushParagraph()
        flushQuote()
        return blocks
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
