//
//  MemoActiveFormats.swift
//  BookBank
//
//  キャレットがいまどの装飾の中にいるかを判定する純関数（docs/memo-tagging-design.md 4.5節）。
//  記号を隠した編集画面では「いま太字を書いている」「つながりの中にいる」が画面から
//  読み取れないため、ツールバーのボタンを光らせて伝える（2026-08-12 オーナー指示）。
//  View に依存しないためユニットテスト対象にできる（実装ガイド 5章）。
//

import Foundation

struct MemoActiveFormats: Equatable, Sendable {
    var link = false
    var bold = false
    var quote = false
    var page = false

    static let none = MemoActiveFormats()

    /// `caret` の位置に効いている装飾を返す。
    ///
    /// 判定はどれも「そこで文字を打ったらその装飾になるか」で揃える——記号は隠れていて
    /// 見えないので、ユーザーにとっての「中にいる」はそういう意味になる
    static func at(_ caret: String.Index, in text: String) -> MemoActiveFormats {
        MemoActiveFormats(
            link: MemoLinkParser.enclosingPair(in: text, at: caret) != nil,
            bold: isInsideBold(caret, in: text),
            quote: isOnQuoteLine(caret, in: text),
            page: isInsidePageNumber(caret, in: text)
        )
    }

    /// `**` のペアの中身にいるか（中身の両端も中と見なす）
    private static func isInsideBold(_ caret: String.Index, in text: String) -> Bool {
        MemoLinkText.enclosingBoldPair(in: text, at: caret) != nil
    }

    /// 行頭が `> ` の行にいるか（引用は行単位の仕組みなので、行のどこにいても中）
    private static func isOnQuoteLine(_ caret: String.Index, in text: String) -> Bool {
        let lineStart = text[..<caret].lastIndex(where: \.isNewline)
            .map { text.index(after: $0) } ?? text.startIndex
        return text[lineStart...].hasPrefix("> ")
    }

    /// `p.数字` の中、または数字を打ち進められる末尾にいるか
    private static func isInsidePageNumber(_ caret: String.Index, in text: String) -> Bool {
        MemoPageMarker.ranges(in: text).contains { range in
            caret > range.lowerBound && caret <= range.upperBound
        }
    }
}
