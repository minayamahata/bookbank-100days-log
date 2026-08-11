//
//  MemoEditorTextView.swift
//  BookBank
//
//  メモ編集欄のエディタ本体（docs/memo-tagging-design.md 4.6節）。
//  編集中も表示と同じ装飾をその場で反映する——Markdownを初めて見る人は、ボタンを押して
//  記号だけが出ても何が起きたのか分からないため（2026-08-11 オーナー指示）。
//  記号そのものは残して薄く表示する（隠すとカーソル位置と文字の対応が壊れて編集できない）。
//  SwiftUIの `TextEditor` は属性付き表示ができないため `UITextView` を包む。
//  装飾は textStorage の属性だけを差し替える（文字列は触らない）のでカーソル位置は保たれる。
//

import SwiftUI
import UIKit

struct MemoEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let accentColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 4
        textView.text = text
        context.coordinator.applyStyling(to: textView, accent: UIColor(accentColor))
        // 旧 TextEditor と同じく、画面表示から一拍おいて自動フォーカス
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak textView] in
            textView?.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        let length = (textView.text as NSString).length
        if textView.selectedRange != selectedRange,
           selectedRange.location + selectedRange.length <= length {
            textView.selectedRange = selectedRange
        }
        context.coordinator.applyStyling(to: textView, accent: UIColor(accentColor))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MemoEditorTextView

        init(_ parent: MemoEditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }

        /// 表示（4.6節）と同じ規則で属性を当てる。文字列は変更しない。
        /// 日本語IMEの変換中（markedText あり）は触らない——変換の下線や候補が壊れるため
        func applyStyling(to textView: UITextView, accent: UIColor) {
            guard textView.markedTextRange == nil else { return }
            let text = textView.text ?? ""
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)

            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label
            ]

            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)

            let links = MemoLinkParser.parse(text)
            let linkRanges = links.map(\.range)

            // 引用行: 行全体に薄いグレー、行頭の「> 」は薄く
            (text as NSString).enumerateSubstrings(
                in: fullRange, options: [.byLines, .substringNotRequired]
            ) { _, lineRange, _, _ in
                guard lineRange.length >= 2,
                      (text as NSString).substring(
                        with: NSRange(location: lineRange.location, length: 2)
                      ) == "> " else { return }
                storage.addAttribute(
                    .backgroundColor, value: UIColor.secondarySystemFill, range: lineRange
                )
                storage.addAttribute(
                    .foregroundColor, value: UIColor.tertiaryLabel,
                    range: NSRange(location: lineRange.location, length: 2)
                )
            }

            // 太字: 中身を太く、記号 ** は薄く
            let boldMarkers = MemoLinkText
                .pairedBoldMarkers(in: text, excluding: linkRanges)
                .sorted()
            let boldFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
            for pairStart in stride(from: 0, to: boldMarkers.count - 1, by: 2) {
                let opening = boldMarkers[pairStart]
                let closing = boldMarkers[pairStart + 1]
                let contentStart = text.index(opening, offsetBy: 2)
                storage.addAttribute(.font, value: boldFont, range: NSRange(contentStart..<closing, in: text))
                for marker in [opening..<contentStart, closing..<text.index(closing, offsetBy: 2)] {
                    storage.addAttribute(
                        .foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(marker, in: text)
                    )
                }
            }

            // ページ番号: 表示と同じバッジ風（つながりのラベル内は除外）
            let pageFont = UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .medium
            )
            for page in MemoPageMarker.ranges(in: text)
            where !linkRanges.contains(where: { $0.contains(page.lowerBound) }) {
                let range = NSRange(page, in: text)
                storage.addAttribute(.font, value: pageFont, range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                storage.addAttribute(
                    .backgroundColor, value: accent.withAlphaComponent(0.14), range: range
                )
            }

            // つながり: 中身をテーマ色＋セミボールド、括弧は薄いテーマ色
            let linkFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
            for link in links {
                let range = NSRange(link.range, in: text)
                storage.addAttribute(.font, value: linkFont, range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                let opening = link.range.lowerBound..<text.index(link.range.lowerBound, offsetBy: 2)
                let closing = text.index(link.range.upperBound, offsetBy: -2)..<link.range.upperBound
                for brackets in [opening, closing] {
                    storage.addAttribute(
                        .foregroundColor, value: accent.withAlphaComponent(0.45),
                        range: NSRange(brackets, in: text)
                    )
                }
            }

            storage.endEditing()
            textView.typingAttributes = baseAttributes
        }
    }
}
