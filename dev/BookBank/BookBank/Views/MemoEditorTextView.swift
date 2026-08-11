//
//  MemoEditorTextView.swift
//  BookBank
//
//  メモ編集欄のエディタ本体（docs/memo-tagging-design.md 4.6節）。
//  編集中も表示と同じ装飾をその場で反映する——Markdownを初めて見る人は、ボタンを押して
//  記号だけが出ても何が起きたのか分からないため（2026-08-11 オーナー指示）。
//  記号（`[[ ]]` / `**` / 行頭の `> `）は**一切表示しない**。装飾UIだけで表す（同日 指示）。
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
        textView.adjustsFontForContentSizeCategory = true
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
        // ツールバーからの差し替えで届いた値。反映途中に UITextView 側から書き戻されると
        // 消えてしまうので、先に控えてから当てる
        let requestedText = text
        let requestedSelection = selectedRange

        context.coordinator.isApplyingRequestedState = true
        if textView.text != requestedText {
            // 文字列の代入だけでキャレットが末尾へ飛ぶため、選択位置はこの後で必ず当て直す
            textView.text = requestedText
        }
        let length = (textView.text as NSString).length
        if textView.selectedRange != requestedSelection,
           requestedSelection.location + requestedSelection.length <= length {
            textView.selectedRange = requestedSelection
        }
        context.coordinator.isApplyingRequestedState = false

        context.coordinator.applyStyling(to: textView, accent: UIColor(accentColor))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MemoEditorTextView
        /// ツールバーが指定した状態を当てている最中。この間の位置変更は UITextView 側の副作用なので
        /// 記録し返さない——ツールバーが置いたキャレットが末尾へ上書きされてしまう
        var isApplyingRequestedState = false

        init(_ parent: MemoEditorTextView) {
            self.parent = parent
        }

        // MARK: - 入力の反映

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingRequestedState else { return }
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }

        /// 見えない記号を1文字ずつ消させない。記号の上で削除したら、その装飾のまとまりごと消す。
        /// つながりは全体（チップを消す感覚）、太字は開き・閉じの両方、引用は行頭の `> ` を消す
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement.isEmpty, range.length == 1,
                  let targets = markerDeletion(at: range.location, in: textView.text ?? "")
            else { return true }

            let storage = textView.textStorage
            storage.beginEditing()
            for target in targets.sorted(by: { $0.location > $1.location }) {
                storage.replaceCharacters(in: target, with: "")
            }
            storage.endEditing()

            // 消えた文字のうち、削除位置より前にあった分だけキャレットを戻す
            let removedBefore = targets.reduce(0) { total, target in
                total + max(0, min(target.location + target.length, range.location) - target.location)
            }
            textView.selectedRange = NSRange(location: range.location - removedBefore, length: 0)

            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
            return false
        }

        /// `index` の文字が隠した記号なら、まとめて消すべき範囲を返す。記号でなければ `nil`（通常削除）
        private func markerDeletion(at index: Int, in text: String) -> [NSRange]? {
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
                return [prefix]
            }

            return nil
        }

        // MARK: - 装飾

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
            // 記号の消し方: 文字は残したまま、極小フォント＋透明で幅も見た目も無くす
            let hiddenAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 0.01),
                .foregroundColor: UIColor.clear
            ]

            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)

            let links = MemoLinkParser.parse(text)
            let linkRanges = links.map(\.range)

            // 引用行: 行全体に薄いグレーの背景、行頭の「> 」は隠す
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
                storage.addAttributes(
                    hiddenAttributes, range: NSRange(location: lineRange.location, length: 2)
                )
            }

            // 太字: 中身を太く、記号 ** は隠す
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
                    storage.addAttributes(hiddenAttributes, range: NSRange(marker, in: text))
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

            // つながり: 中身をテーマ色＋セミボールド、括弧は隠す
            let linkFont = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
            for link in links {
                let range = NSRange(link.range, in: text)
                storage.addAttribute(.font, value: linkFont, range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                let opening = link.range.lowerBound..<text.index(link.range.lowerBound, offsetBy: 2)
                let closing = text.index(link.range.upperBound, offsetBy: -2)..<link.range.upperBound
                for brackets in [opening, closing] {
                    storage.addAttributes(hiddenAttributes, range: NSRange(brackets, in: text))
                }
            }

            storage.endEditing()
            textView.typingAttributes = baseAttributes
        }
    }
}
