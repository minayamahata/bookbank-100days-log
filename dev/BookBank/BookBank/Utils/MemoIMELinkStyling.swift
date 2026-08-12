//
//  MemoIMELinkStyling.swift
//  BookBank
//
//  つながりの括弧の中での日本語IMEまわりの約束（docs/memo-tagging-design.md 4.6節）。
//  View に閉じると測定できないので、判定だけここに出す。
//

import Foundation

enum MemoIMELinkStyling {
    /// 測定1: つながりの中では**打つ前に**テーマ色を決める（`typingAttributes`）。
    /// 入力後に当て直すと、変換確定まで色が付かず一拍遅れる
    static func prefersLinkTypingAttributes(isInsideLink: Bool) -> Bool {
        isInsideLink
    }

    /// 測定2: 変換中（markedText あり）は全体の装飾当て直しをしない。
    /// `setAttributes` で置き換えると IME の下線まで消える
    static func shouldRefreshFullDecoration(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }

    /// 測定3: 再変換中の色付けは属性を**足すだけ**（全体置換ではない）。
    /// つながりの中に変換範囲があるときだけ足す
    static func shouldAugmentMarkedText(isInsideLink: Bool) -> Bool {
        isInsideLink
    }
}
