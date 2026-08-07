//
//  MemoTagText.swift
//  BookBank
//
//  メモ本文の表示用テキストを組み立てる（docs/memo-tagging-design.md 4.1節）。
//  タグの検出そのものは `MemoTagParser`（Foundationのみの純関数）が担い、
//  ここは色を当てる表示側の薄い層に留める。
//

import SwiftUI

enum MemoTagText {
    /// メモ本文のうちタグ部分だけを色付きにした `AttributedString` を作る。
    ///
    /// タグ以外の文字は一切加工しないため、`Text` に渡したときの改行・折り返しは
    /// 素の `Text(memo)` と同じになる（前提13の見た目不変の範囲を、タグの着色だけに限る）。
    static func highlighted(_ memo: String, color: Color) -> AttributedString {
        var result = AttributedString()
        var cursor = memo.startIndex

        for tag in MemoTagParser.parse(memo) {
            result += AttributedString(memo[cursor..<tag.range.lowerBound])

            var highlighted = AttributedString(memo[tag.range])
            highlighted.foregroundColor = color
            highlighted.font = .subheadline.weight(.semibold)
            result += highlighted

            cursor = tag.range.upperBound
        }

        result += AttributedString(memo[cursor...])
        return result
    }
}
