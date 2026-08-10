//
//  MemoLinkText.swift
//  BookBank
//
//  メモ本文の表示用テキストを組み立てる（docs/memo-tagging-design.md 4.6節）。
//  つながりの検出そのものは `MemoLinkParser`（Foundationのみの純関数）が担い、
//  ここは記号を隠して色を当てる表示側の薄い層に留める。
//

import SwiftUI

enum MemoLinkText {
    /// メモ本文のうち `[[ ]]` を記号ごと**中身だけの色付き表示**に置き換えた
    /// `AttributedString` を作る。
    ///
    /// 記号を隠すため表示文字列は原文と一致しない（`#` 時代の「着色以外は素の `Text(memo)`
    /// と同じ」は成立しなくなった）。代わりの不変条件は「**解釈対象の記号以外の文字は
    /// 一切加工しない**」（設計メモ 4.6節・テストで固定）。編集画面は記号を出したままにする
    static func highlighted(_ memo: String, color: Color) -> AttributedString {
        var result = AttributedString()
        var cursor = memo.startIndex

        for link in MemoLinkParser.parse(memo) {
            result += AttributedString(memo[cursor..<link.range.lowerBound])

            var highlighted = AttributedString(link.display)
            highlighted.foregroundColor = color
            highlighted.font = .subheadline.weight(.semibold)
            result += highlighted

            cursor = link.range.upperBound
        }

        result += AttributedString(memo[cursor...])
        return result
    }
}
