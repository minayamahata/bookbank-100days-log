import Testing
import SwiftUI
import UIKit
@testable import BookBank

/// 引用の囲みとカーソルの幾何。囲みは行に割り当てられた領域いっぱいに描くため、
/// 余白（段落の前後空き）を入れるとカーソルが標準では領域いっぱいに伸びる。
/// 実測でこれを確かめたうえでカーソルを文字の高さに合わせているので、そこを固定する
@MainActor
struct MemoQuoteGeometryTests {
    private func makeTextView(text: String) -> (MemoCaretAlignedTextView, MemoQuoteBackgroundLayoutManager, NSTextStorage) {
        let layoutManager = MemoQuoteBackgroundLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        let textView = MemoCaretAlignedTextView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 400), textContainer: container
        )
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 4
        textView.font = .preferredFont(forTextStyle: .body)
        textView.text = text
        return (textView, layoutManager, storage)
    }

    @Test func caretStaysInsideTheQuoteBox() {
        let text = "まえの行\n> 引用の行\nあとの行"
        let (textView, layoutManager, _) = makeTextView(text: text)

        let quoteLine = (text as NSString).range(of: "> 引用の行")
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = MemoQuoteBackgroundLayoutManager.padding
        style.paragraphSpacing = MemoQuoteBackgroundLayoutManager.padding
        textView.textStorage.addAttribute(.paragraphStyle, value: style, range: quoteLine)
        layoutManager.ensureLayout(for: textView.textContainer)

        let glyphRange = layoutManager.glyphRange(forCharacterRange: quoteLine, actualCharacterRange: nil)
        var box = CGRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            box = box.union(lineRect)
        }
        let position = try! #require(
            textView.position(from: textView.beginningOfDocument, offset: quoteLine.location + 4)
        )
        // 囲みはビュー座標では上の余白ぶん下がる
        let boxInView = box.offsetBy(dx: 0, dy: textView.textContainerInset.top)
        let caret = textView.caretRect(for: position)

        #expect(caret.minY >= boxInView.minY, "カーソルが囲みの上へ飛び出さない")
        #expect(caret.maxY <= boxInView.maxY, "カーソルが囲みの下へ飛び出さない")
        #expect(
            caret.height < boxInView.height,
            "カーソルは囲みより低い（文字の高さに合わせている）"
        )
    }

    /// 本文の先頭・末尾では段落の前後空きが効かない（実測で確認）。囲みを外へ広げて補っているので、
    /// 上下どちらの端でも文字と囲みのあいだに余白が残ることを固定する
    @Test func quoteBoxKeepsPaddingAtBothEndsOfTheMemo() {
        let padding = MemoQuoteBackgroundLayoutManager.padding

        for text in ["> 先頭が引用\nあとの行", "まえの行\n> 末尾が引用"] {
            let quoteLine = (text as NSString).range(of: "引用")
            let block = (text as NSString).lineRange(for: quoteLine)
            let trimmed = NSRange(
                location: block.location,
                length: block.length - ((text as NSString).substring(with: block).hasSuffix("\n") ? 1 : 0)
            )

            let (textView, layoutManager, _) = makeTextView(text: text)
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = padding
            style.paragraphSpacing = padding
            textView.textStorage.addAttribute(.paragraphStyle, value: style, range: trimmed)
            layoutManager.quoteRanges = [trimmed]
            layoutManager.ensureLayout(for: textView.textContainer)

            let box = try! #require(layoutManager.quoteBoxes().first)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            var textArea = CGRect.null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, used, _, _, _ in
                textArea = textArea.union(used)
            }

            #expect(textArea.minY - box.minY >= padding - 0.5, "上の余白が残る: \(text)")
            #expect(box.maxY - textArea.maxY >= padding - 0.5, "下の余白が残る: \(text)")
        }
    }

    /// 出典ページが未入力の行は `p.` を隠すので、素のままだと行が潰れてカーソルも案内も
    /// 置き場を失う。行の高さを底上げしていることを固定する
    @Test func emptyPageLineKeepsRoomForTheCaretAndHint() {
        let text = "> 引用の行\np."
        let (textView, layoutManager, _) = makeTextView(text: text)
        let pageLine = (text as NSString).range(of: "p.")
        let pageFont = UIFont.preferredFont(forTextStyle: .footnote)

        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.minimumLineHeight = pageFont.lineHeight
        textView.textStorage.addAttribute(.paragraphStyle, value: style, range: pageLine)
        textView.textStorage.addAttributes(
            [.font: UIFont.systemFont(ofSize: 0.01), .foregroundColor: UIColor.clear],
            range: pageLine
        )
        layoutManager.ensureLayout(for: textView.textContainer)

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: pageLine.location)
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        #expect(line.height >= pageFont.lineHeight - 0.5, "案内を描ける高さが残る")

        let position = try! #require(
            textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(pageLine))
        )
        #expect(textView.caretRect(for: position).height >= pageFont.lineHeight - 0.5)
    }

    /// 案内は本文の文字ではなく描画なので、出ているかどうかを実機以外で見る手段がここしかない。
    /// 案内あり／なしで描き出しが変わることを固定する
    @Test func pageHintIsDrawnOnTheEmptyPageLine() {
        let text = "> 引用の行\np."
        let (textView, layoutManager, _) = makeTextView(text: text)
        let pageLine = (text as NSString).range(of: "p.")
        let pageFont = UIFont.preferredFont(forTextStyle: .footnote)

        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.minimumLineHeight = pageFont.lineHeight
        textView.textStorage.addAttribute(.paragraphStyle, value: style, range: pageLine)
        textView.textStorage.addAttributes(
            [.font: UIFont.systemFont(ofSize: 0.01), .foregroundColor: UIColor.clear],
            range: pageLine
        )
        layoutManager.pageHintRanges = [pageLine]
        layoutManager.ensureLayout(for: textView.textContainer)

        let everything = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: (text as NSString).length),
            actualCharacterRange: nil
        )
        func render(hint: NSAttributedString?) -> Data? {
            layoutManager.pageHint = hint
            return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
                .image { _ in layoutManager.drawBackground(forGlyphRange: everything, at: .zero) }
                .pngData()
        }

        let hint = NSAttributedString(
            string: "ページを入力",
            attributes: [.font: pageFont, .foregroundColor: UIColor.tertiaryLabel]
        )
        #expect(render(hint: hint) != render(hint: nil), "案内が描かれている")
    }

    /// 「ひとつ戻す」はiOS標準の取り消し機構に相乗りする。取り消すと復元された範囲が選択される
    /// （書式クリアを戻すと全選択に見えた）ので、キャレットに畳んでいることを固定する
    @Test func undoCollapsesTheRestoredSelection() throws {
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        textView.text = "もとの本文"
        let bridge = MemoEditorBridge()
        bridge.textView = textView

        #expect(bridge.replace(NSRange(location: 0, length: 5), with: "書き換えた", caretLocation: 5))
        try #require(bridge.canUndo, "テキストビュー経由の書き換えは取り消しの履歴に載る")

        bridge.undo()
        #expect(textView.text == "もとの本文")
        #expect(textView.selectedRange.length == 0, "全選択のまま戻さない")
    }

    /// 出典ページの行は編集画面では消えたままにしない（2026-08-11 オーナー指示）——
    /// 消したあとに案内が出ないと、そのメモにはもうページを入力できない。
    /// 純関数は `BookBankTests` で固定しているので、ここでは画面との結線を見る
    @Test func editorPutsThePageLineBackAfterItIsDeleted() throws {
        let memo = Box("> 引用の行")
        let editor = MemoEditorView(
            memo: Binding(get: { memo.value }, set: { memo.value = $0 }),
            accentColor: .blue
        ) { _ in }

        let host = UIHostingController(rootView: editor)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        let textView = try #require(Self.textView(in: host.view))
        #expect(
            textView.text == "> 引用の行\np.\n",
            "引用だけのメモを開いても案内が出る。その下には抜ける先の行も用意する"
        )

        // 案内の行ごと消された状態を作り、入力の反映を通す
        textView.text = "> 引用の行"
        textView.delegate?.textViewDidChange?(textView)
        #expect(textView.text == "> 引用の行\np.\n", "消えたら足し直す")
        #expect(memo.value == "> 引用の行", "足した案内は保存前のメモには出さない")
    }

    /// 単体のページ番号のバッジは、隣の文字に重ならず本文の左端からも出ない。
    /// 余白は字送りで作るので、行頭のバッジだけは字下げに切り替えている（設計メモ 4.6節）——
    /// 字送りだと直前の改行が広がり、前の行が伸びてしまう（実機で発覚）
    @Test func pageBadgeKeepsClearOfNeighboringText() throws {
        let inset = MemoQuoteBackgroundLayoutManager.pageBadgeInset.width
        let margin = MemoQuoteBackgroundLayoutManager.pageBadgeMargin
        let spacing = MemoQuoteBackgroundLayoutManager.pageBadgeSpacing

        // 行頭のバッジ: 本文の左端（行の余白）より内側に収まる
        let (leading, leadingManager) = try Self.makeEditor(memo: "あああああ\np.125")
        let leadingBox = try #require(leadingManager.pageBadgeBoxes().first)
        #expect(
            leadingBox.minX >= leading.textContainer.lineFragmentPadding - 0.5,
            "バッジが本文の左端から出ない"
        )
        #expect(
            leading.textStorage.attribute(.kern, at: 5, effectiveRange: nil) == nil,
            "前の行の改行は広げない（未確定文字の囲みが伸びて見える）"
        )

        // 行の途中のバッジ: 直前の文字とのあいだに間隔が残る
        let memo = "ああああp.125あああ"
        let (inline, inlineManager) = try Self.makeEditor(memo: memo)
        let badge = (memo as NSString).range(of: "p.125")
        let inlineBox = try #require(inlineManager.pageBadgeBoxes().first)
        let previous = NSRange(location: badge.location - 1, length: 1)
        var previousRect = CGRect.null
        inlineManager.enumerateEnclosingRects(
            forGlyphRange: inlineManager.glyphRange(
                forCharacterRange: previous, actualCharacterRange: nil
            ),
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: inline.textContainer
        ) { rect, _ in previousRect = previousRect.union(rect) }

        // 直前の文字の字送りを広げてあるので、字幅はその分を戻して見る
        let previousEnd = previousRect.maxX - spacing
        #expect(inlineBox.minX - previousEnd >= margin - 0.5, "直前の文字に重ならない")
        #expect(inlineBox.minX - previousEnd <= inset + margin, "離れすぎない")
    }

    private static func makeEditor(
        memo: String
    ) throws -> (UITextView, MemoQuoteBackgroundLayoutManager) {
        let box = Box(memo)
        let editor = MemoEditorView(
            memo: Binding(get: { box.value }, set: { box.value = $0 }),
            accentColor: .orange
        ) { _ in }
        let host = UIHostingController(rootView: editor)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        let textView = try #require(Self.textView(in: host.view))
        let manager = try #require(textView.layoutManager as? MemoQuoteBackgroundLayoutManager)
        manager.ensureLayout(for: textView.textContainer)
        return (textView, manager)
    }

    private final class Box {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let found = view as? UITextView { return found }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    @Test func caretMatchesTextHeightOnPlainLines() {
        let text = "ふつうの行"
        let (textView, layoutManager, _) = makeTextView(text: text)
        layoutManager.ensureLayout(for: textView.textContainer)

        let position = try! #require(
            textView.position(from: textView.beginningOfDocument, offset: 1)
        )
        let textArea = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        let caret = textView.caretRect(for: position)

        // 余白のない行では、書き換えても標準とほぼ同じ高さのままであること
        #expect(abs(caret.height - (textArea.height + 2)) < 0.5)
    }
}
