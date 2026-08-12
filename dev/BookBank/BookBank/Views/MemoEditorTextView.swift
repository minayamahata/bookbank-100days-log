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

/// 引用の囲みを自前で描くレイアウトマネージャ。文字の背景色属性では余白を作れず、
/// 書籍詳細側の囲み（内側の余白10）と見た目が揃わないため（2026-08-11 オーナー指示）。
/// この描画のため `UITextView` は旧来のレイアウト機構（TextKit 1）で組む
final class MemoQuoteBackgroundLayoutManager: NSLayoutManager {
    /// 囲みの内側の余白。上下は段落スタイルの前後空き、左右は字下げで作る
    static let padding: CGFloat = 18
    /// 囲みと隣の行のあいだ（書籍詳細のブロック間と同じ）
    static let gapToNeighbor: CGFloat = 6

    /// 単体のページ番号（`p.42`）のバッジ。角丸とグレーの背景は文字の背景色属性では作れないので、
    /// 引用の囲みと同じくここで描く（2026-08-11 オーナー指示。文字色はテーマ色のまま）
    static let pageBadgeCornerRadius: CGFloat = 4
    static let pageBadgeInset = CGSize(width: 6, height: 3)
    /// バッジと隣の文字のあいだ（**2026-08-11 オーナー指示**）
    static let pageBadgeMargin: CGFloat = 4
    /// バッジの前後に空ける文字送り（内側の余白＋外側の間隔）。文字を足さずに場所を作るため、
    /// 直前の文字とバッジ末尾の文字の字送り（`.kern`）を広げてこの空きを作る
    static var pageBadgeSpacing: CGFloat { pageBadgeInset.width + pageBadgeMargin }
    /// バッジのグレー。書籍詳細（`MemoFormattedText`）と共有する
    static let pageBadgeColorDefault = UIColor.systemFill

    var quoteRanges: [NSRange] = []
    var quoteColor: UIColor = .quaternarySystemFill
    /// 数字が未入力のページ行。文字（`p.`）は隠してあるので、案内をここに描く
    var pageHintRanges: [NSRange] = []
    var pageHint: NSAttributedString?
    /// 中身が空のつながり（「つなぐ」を押した直後）。記号は隠してあるので、案内をここに描く
    var linkHintRange: NSRange?
    var linkHint: NSAttributedString?
    var pageBadgeRanges: [NSRange] = []
    var pageBadgeColor: UIColor = MemoQuoteBackgroundLayoutManager.pageBadgeColorDefault

    /// 囲みの矩形（テキストコンテナ座標）。行に割り当てられた領域＝段落の前後空きを含むので、
    /// それがそのまま内側の余白になる。ただし**本文の先頭では前の空きが、末尾では後の空きが
    /// 効かない**（実測で確認）ため、その分をここで補う
    func quoteBoxes() -> [CGRect] {
        guard let container = textContainers.first, let storage = textStorage else { return [] }
        // 範囲は本文から求めたものなので、描画が本文の変更に先回りした場合に備えて丸める
        let available = NSRange(location: 0, length: storage.length)

        return quoteRanges.compactMap { requested in
            let range = NSIntersectionRange(requested, available)
            guard range.length > 0 else { return nil }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var box = CGRect.null
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                box = box.union(lineRect)
            }
            guard !box.isNull else { return nil }

            let missingTop = range.location == 0 ? Self.padding : 0
            let missingBottom = NSMaxRange(range) == storage.length ? Self.padding : 0
            return CGRect(
                x: 0,
                y: box.minY - missingTop,
                width: container.size.width,
                height: box.height + missingTop + missingBottom
            )
        }
    }

    /// 単体のページ番号を囲むバッジの矩形（テキストコンテナ座標）。
    /// 文字にぴったり付く矩形を上下左右へ広げて余白にする——行に割り当てられた領域を使うと
    /// 縦だけ大きくなり、書籍詳細側（文字の外形に付ける）と見た目が揃わない
    func pageBadgeBoxes() -> [CGRect] {
        guard let container = textContainers.first, let storage = textStorage else { return [] }
        let available = NSRange(location: 0, length: storage.length)

        var boxes: [CGRect] = []
        for requested in pageBadgeRanges {
            let range = NSIntersectionRange(requested, available)
            guard range.length > 0 else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            // 幅は字送りを広げる前の文字幅から測る——行の矩形には末尾に足した空きが入っている
            let width = font.map { pageFont in
                NSAttributedString(
                    string: storage.attributedSubstring(from: range).string,
                    attributes: [.font: pageFont]
                ).size().width
            }
            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                var box = rect
                if let font {
                    // 縦はベースラインから文字の高さぶんだけ取る
                    let lineRect = self.lineFragmentRect(
                        forGlyphAt: glyphRange.location, effectiveRange: nil
                    )
                    let baseline = self.location(forGlyphAt: glyphRange.location).y
                    box = CGRect(
                        x: rect.minX,
                        y: lineRect.minY + baseline - font.ascender,
                        width: min(width ?? rect.width, rect.width),
                        height: font.ascender - font.descender
                    )
                }
                boxes.append(
                    box.insetBy(dx: -Self.pageBadgeInset.width, dy: -Self.pageBadgeInset.height)
                )
            }
        }
        return boxes
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            context.setFillColor(quoteColor.cgColor)
            for box in quoteBoxes() {
                context.fill(box.offsetBy(dx: origin.x, dy: origin.y))
            }
            context.setFillColor(pageBadgeColor.cgColor)
            for box in pageBadgeBoxes() {
                let path = UIBezierPath(
                    roundedRect: box.offsetBy(dx: origin.x, dy: origin.y),
                    cornerRadius: Self.pageBadgeCornerRadius
                )
                context.addPath(path.cgPath)
                context.fillPath()
            }
            context.restoreGState()
        }
        drawPageHints(at: origin)
        drawLinkHint(at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// 中身が空のつながりに「つながりを入力」の案内を、キャレットの位置から描く。
    /// 記号（`[[ ]]`）を出さない代わりに、そこが何を書く場所なのかをこれで伝える
    private func drawLinkHint(at origin: CGPoint) {
        guard let hint = linkHint, let requested = linkHintRange,
              let container = textContainers.first, let storage = textStorage
        else { return }

        let range = NSIntersectionRange(requested, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var line = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            line = line.union(usedRect)
        }
        guard !line.isNull else { return }

        // 記号は隠してあり幅がほぼ無いので、この矩形の左端がキャレットの位置になる
        let box = boundingRect(forGlyphRange: glyphRange, in: container)
        let size = hint.size()
        hint.draw(
            in: CGRect(
                x: origin.x + box.minX,
                y: origin.y + line.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }

    /// 数字未入力のページ行に「ページを入力」の案内を右詰めで描く。
    /// 本文の文字として入れないので、入力しなければメモには何も残らない
    private func drawPageHints(at origin: CGPoint) {
        guard let hint = pageHint, let container = textContainers.first,
              let storage = textStorage, !pageHintRanges.isEmpty else { return }

        let available = NSRange(location: 0, length: storage.length)
        let size = hint.size()
        let rightEdge = container.size.width - container.lineFragmentPadding
        for requested in pageHintRanges {
            let range = NSIntersectionRange(requested, available)
            guard range.length > 0 else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var line = CGRect.null
            enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                line = line.union(usedRect)
            }
            guard !line.isNull else { continue }
            hint.draw(
                in: CGRect(
                    x: origin.x + rightEdge - size.width - 3,
                    y: origin.y + line.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            )
        }
    }
}

/// カーソルの高さを文字に合わせる編集ビュー。
/// 標準では行に割り当てられた領域いっぱいに伸びるため、引用の余白（段落の前後空き）を入れると
/// カーソルだけが極端に長くなる（実測: 22ptの文字に対して52pt）。文字の高さに合わせて描き直す
final class MemoCaretAlignedTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let location = self.offset(from: beginningOfDocument, to: position)
        // ページ番号の直後は、バッジの余白のために広げた字送りの分だけ左へ戻す——
        // 戻さないとバッジの外にカーソルが立ち、入力中の場所に見えない（2026-08-12 オーナー報告）
        if endsPageBadge(at: location) {
            rect.origin.x -= MemoQuoteBackgroundLayoutManager.pageBadgeSpacing
        }

        guard let layoutManager = textContainer.layoutManager,
              let storage = layoutManager.textStorage, storage.length > 0
        else { return rect }

        // 末尾の改行のうしろ（文字がまだ無い最後の行）は、その行のためだけの矩形に合わせる——
        // 直前の文字（改行）に合わせるとひとつ上の行にカーソルが立って見え、
        // Enterを押しても改行できていないように映る（2026-08-12 オーナー報告）
        if location >= storage.length {
            let extra = layoutManager.extraLineFragmentUsedRect
            if extra.height > 0 {
                return CGRect(
                    x: rect.minX,
                    y: extra.minY + textContainerInset.top - 1,
                    width: rect.width,
                    height: extra.height + 2
                )
            }
        }

        let offset = min(location, storage.length - 1)
        guard offset >= 0 else { return rect }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return rect }

        let textArea = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard textArea.height > 0 else { return rect }
        return CGRect(
            x: rect.minX,
            y: textArea.minY + textContainerInset.top - 1,
            width: rect.width,
            height: textArea.height + 2
        )
    }

    /// その位置がページ番号のバッジの直後か（バッジの範囲は描画側が持っている）
    private func endsPageBadge(at location: Int) -> Bool {
        guard let manager = textContainer.layoutManager as? MemoQuoteBackgroundLayoutManager
        else { return false }
        return manager.pageBadgeRanges.contains { NSMaxRange($0) == location }
    }
}

/// 編集画面からテキストビューへ命令を送る通り道。
/// 「ひとつ戻す」はiOS標準の取り消し機構に相乗りするので、ツールバーの書き換えも
/// テキストビュー経由で行う——文字列を直接差し替えると取り消しの履歴に残らない
@MainActor
@Observable
final class MemoEditorBridge {
    @ObservationIgnored weak var textView: UITextView?
    var canUndo = false

    /// 取り消しの履歴に載る形で書き換える。テキストビューがまだ無ければ `false`（呼び出し側が従来の経路へ）
    func replace(_ range: NSRange, with insertion: String, caretLocation: Int) -> Bool {
        guard let textView,
              let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let target = textView.textRange(from: start, to: end)
        else { return false }

        // 入力機構へ「こちらで書き換えた」と知らせてから触る（2026-08-12）。黙って書き換えると
        // 日本語キーボードが古い本文を握ったままになり、挿した記号（`]`）が予測変換バーに
        // 候補として並ぶ——「つなぐ」を押すとキーボードの上に見慣れない表示が出る原因
        textView.inputDelegate?.textWillChange(textView)
        textView.replace(target, withText: insertion)
        textView.inputDelegate?.textDidChange(textView)

        textView.inputDelegate?.selectionWillChange(textView)
        textView.selectedRange = NSRange(location: caretLocation, length: 0)
        textView.inputDelegate?.selectionDidChange(textView)
        // 差し替えの通知が来ない経路があっても編集画面と食い違わないよう、こちらから反映させる
        textView.delegate?.textViewDidChange?(textView)
        refresh()
        return true
    }

    func undo() {
        guard let textView, let undoManager = textView.undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        // 取り消すと復元された範囲が選択される（書式クリアを戻すと全選択に見える）ので、
        // 末尾のキャレットに畳む
        if textView.selectedRange.length > 0 {
            textView.selectedRange = NSRange(
                location: NSMaxRange(textView.selectedRange), length: 0
            )
        }
        // 取り消しの経路によっては通知が来ないので、こちらから編集画面へ反映させる
        textView.delegate?.textViewDidChange?(textView)
        refresh()
    }

    func refresh() {
        let available = textView?.undoManager?.canUndo ?? false
        if canUndo != available { canUndo = available }
    }
}

struct MemoEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    /// ページ番号の入力中だけ数字が並んだキーボードにする。キャレットが `p.数字` から離れたら自動で戻す
    @Binding var prefersNumericKeyboard: Bool
    let accentColor: Color
    /// ツールバーの書き換えと「ひとつ戻す」の通り道
    let bridge: MemoEditorBridge

    /// 本文の上下の余白（引用が端にある場合はここに囲みの余白ぶんを足す）
    fileprivate static let baseTextInset: CGFloat = 12

    /// 引用の中の文字色。本文より少し薄い黒（濃いめのグレー）で、書籍詳細と共有する
    static let quoteTextColor = UIColor.label.withAlphaComponent(0.75)

    /// 書いている最中のつながりに敷く背景の濃さ（文字と同じテーマ色を薄くする）。
    /// **2026-08-12 オーナー指示**——記号を隠したので、色だけではどこまでが中身か分からない。
    /// 編集画面だけの手当てで、書籍詳細は文字色のままにする（背景は「いま書いている」印）
    static let linkBackgroundAlpha: CGFloat = 0.1

    /// 太字の太さ。`bold` では本文との差が弱いので一段上げる（**2026-08-12 オーナー指示**）。
    /// 書籍詳細（`MemoFormattedText`）と共有する
    static let boldWeight: UIFont.Weight = .heavy

    /// Enterで分けた段落のあいだに足す空き。折り返しの行と行送りが同じだと改行できたのか
    /// 分からないため、段落の行送りが2倍になるぶんだけ空ける（**2026-08-12 オーナー指示**）。
    /// 書籍詳細（`MemoFormattedText`）と共有する
    static var paragraphSpacing: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        // 引用の囲みを自前で描くため、レイアウト機構を明示して組む（TextKit 1）
        let layoutManager = MemoQuoteBackgroundLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        // 文字置き場はレイアウト機構から弱参照されるだけなので、こちらで保持しないと
        // 解放され、編集画面を開いた瞬間に落ちる
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        let textView = MemoCaretAlignedTextView(frame: .zero, textContainer: container)
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        layoutManager.pageHint = NSAttributedString(
            string: String(localized: "memo.quote.page.hint"), attributes: hintAttributes
        )
        layoutManager.linkHint = NSAttributedString(
            string: String(localized: "memo.link.hint"), attributes: hintAttributes
        )
        context.coordinator.textStorage = storage
        context.coordinator.quoteLayoutManager = layoutManager
        textView.delegate = context.coordinator
        // ページ番号と同じ行の余白を触ったときの抜け口（2026-08-12 オーナー指示・下記
        // `escapePageMarker`）。キャレットが既に行末に在ると位置が動かず、`UITextView` の
        // タップだけでは何も起きない——触ったこと自体を受け取る必要があるので手を挙げる
        let escapeTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePageMarkerEscapeTap(_:))
        )
        escapeTap.delegate = context.coordinator
        escapeTap.cancelsTouchesInView = false
        textView.addGestureRecognizer(escapeTap)
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(
            top: Self.baseTextInset, left: 0, bottom: Self.baseTextInset, right: 0
        )
        textView.textContainer.lineFragmentPadding = 4
        textView.text = text
        bridge.textView = textView
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

        // ページ番号のあいだはテンキー（2026-08-11 オーナー指示）。テンキーには Enter が無いので、
        // 抜け口は「何もないところのタップ」に一本化する（2026-08-12 オーナー確定）
        let keyboardType: UIKeyboardType = prefersNumericKeyboard ? .numberPad : .default
        if textView.keyboardType != keyboardType {
            textView.keyboardType = keyboardType
            if textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }

        context.coordinator.applyStyling(to: textView, accent: UIColor(accentColor))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MemoEditorTextView
        /// レイアウト機構は文字置き場に強参照されるので、こちらは弱参照でよい
        weak var quoteLayoutManager: MemoQuoteBackgroundLayoutManager?
        /// 文字置き場（`UITextView` からは弱参照）。エディタが生きている間はここで保持する
        var textStorage: NSTextStorage?
        /// ツールバーが指定した状態を当てている最中。この間の位置変更は UITextView 側の副作用なので
        /// 記録し返さない——ツールバーが置いたキャレットが末尾へ上書きされてしまう
        var isApplyingRequestedState = false
        /// ひとつ前の位置変更のときの本文の長さ。位置が動いた理由が入力かタップかを見分けるために持つ
        /// （入力なら長さが変わる。テンキーからの抜け方の判定に使う）
        private var lengthAtLastSelectionChange = -1
        /// 引用の上に空行を足している最中。入れた改行が同じ規則に再入するのを防ぐ
        private var isOpeningLineAboveQuote = false

        init(_ parent: MemoEditorTextView) {
            self.parent = parent
        }

        // MARK: - 入力の反映

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            parent.bridge.refresh()
            ensureQuotePageLines(textView)
            releaseNumericKeyboardIfNeeded(textView)
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
        }

        /// 引用に出典ページの行が無ければ足し直す。案内を常に出しておくため（2026-08-11 オーナー指示）——
        /// 引用を書いたあとに消してしまうと、入力する場所そのものが無くなってしまう。
        /// 取り消しの履歴には載せない（自動で足したものを戻す操作は意味を持たない）
        private func ensureQuotePageLines(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let offsets = MemoQuotePage.pageLineInsertions(in: textView.text ?? "")
            // ページ行が本文の末尾のままだと、そこから先へ出られない（テンキーに改行キーが無い）
            let tail = MemoQuotePage.trailingBlankLineInsertion(
                in: MemoQuotePage.ensuringPageLines(in: textView.text ?? "")
            )
            guard !offsets.isEmpty || tail != nil else { return }

            let caret = textView.selectedRange
            let storage = textView.textStorage
            storage.beginEditing()
            for offset in offsets.sorted(by: >) {
                storage.replaceCharacters(in: NSRange(location: offset, length: 0), with: "\np.")
            }
            if tail != nil {
                storage.replaceCharacters(
                    in: NSRange(location: storage.length, length: 0), with: "\n"
                )
            }
            storage.endEditing()

            // キャレットより前に入った分だけ後ろへずらす（行末に入るので同位置なら動かさない）
            let insertedBefore = offsets.count(where: { $0 < caret.location }) * 3
            textView.selectedRange = NSRange(
                location: caret.location + insertedBefore, length: caret.length
            )
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingRequestedState else { return }
            let length = (textView.text as NSString).length
            let followsEdit = length != lengthAtLastSelectionChange
            lengthAtLastSelectionChange = length

            guard !releaseNumericKeyboardKeepingCaret(textView, followsEdit: followsEdit) else {
                return
            }
            snapCaretPastPageMarker(textView)
            snapCaretOutOfHiddenMarkers(textView)
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
            adoptNumericKeyboardOnQuotePageLine(textView)
            releaseNumericKeyboardIfNeeded(textView)
            // 案内は「キャレットがその行に無いとき」だけ出すので、選択が動くたびに当て直す
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
        }

        /// 出典ページの行では、キャレットを必ず `p.` の直後へ置き直す（判定は `MemoQuotePage`）
        private func snapCaretPastPageMarker(_ textView: UITextView) {
            let selection = textView.selectedRange
            guard selection.length == 0 else { return }
            let snapped = MemoQuotePage.caretLocation(
                snapping: selection.location, in: textView.text ?? ""
            )
            guard snapped != selection.location else { return }
            textView.selectedRange = NSRange(location: snapped, length: 0)
        }

        /// 隠れた記号の中にはキャレットを置かない（判定は `MemoHiddenMarkers`）。
        /// 行頭をタップしても `> ` の前ではなく文字の側に入るので、打った文字が引用の外へ
        /// こぼれない。変換中は動かさない——IMEが握っている位置を横から変えることになる
        private func snapCaretOutOfHiddenMarkers(_ textView: UITextView) {
            let selection = textView.selectedRange
            guard selection.length == 0, textView.markedTextRange == nil else { return }
            let snapped = MemoHiddenMarkers.caretLocation(
                snapping: selection.location, in: textView.text ?? ""
            )
            guard snapped != selection.location else { return }
            textView.selectedRange = NSRange(location: snapped, length: 0)
        }

        /// 出典ページの行に入ったら数字キーボードにする（案内を見て触った直後に数字が打てるように）
        private func adoptNumericKeyboardOnQuotePageLine(_ textView: UITextView) {
            guard !parent.prefersNumericKeyboard else { return }
            let text = textView.text ?? ""
            let selection = textView.selectedRange
            guard selection.length == 0,
                  caretFollowsPageMarker(in: text, at: selection.location),
                  MemoTextBlocks.quotePageLineRanges(in: text).contains(where: {
                      NSLocationInRange(selection.location, $0)
                          || selection.location == NSMaxRange($0)
                  })
            else { return }
            parent.prefersNumericKeyboard = true
        }

        /// 何もないところを触ってテンキーから抜けるときは、**キャレットを動かさずキーボードだけ戻す**
        /// （**2026-08-12 オーナー報告**——本文の途中にページ番号を入れると、抜けるたびに末尾へ飛んでいた）。
        /// 文字の無い場所を触るとキャレットは必ず本文の末尾に入るので、そこへ飛んだかどうかで見分ける。
        /// 代わりに、テンキー中に末尾を狙って触った1回は空振りになる（もう一度触れば末尾へ行ける）。
        /// 数字を打ってもキャレットは末尾へ進むので、**入力に続く位置変更は対象外**
        /// （2026-08-12 オーナー報告——1桁打つとテンキーが閉じていた）
        private func releaseNumericKeyboardKeepingCaret(
            _ textView: UITextView,
            followsEdit: Bool
        ) -> Bool {
            guard parent.prefersNumericKeyboard, !followsEdit else { return false }
            let text = textView.text ?? ""
            let end = (text as NSString).length
            let previous = parent.selectedRange
            guard textView.selectedRange == NSRange(location: end, length: 0),
                  previous.length == 0, previous.location != end,
                  caretFollowsPageMarker(in: text, at: previous.location)
            else { return false }

            parent.prefersNumericKeyboard = false
            isApplyingRequestedState = true
            textView.selectedRange = previous
            isApplyingRequestedState = false
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
            return true
        }

        // MARK: - ページ番号からの抜け口

        /// `UITextView` 自身のタップとは別に手を挙げる（触った位置を見るだけで、邪魔はしない）
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handlePageMarkerEscapeTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            escapePageMarker(in: textView, tappedAt: recognizer.location(in: textView))
        }

        /// **ページ番号と同じ行の、文字より後ろの余白**を触ったら、番号の外（行末）へ出て
        /// 通常のキーボードへ戻す（**2026-08-12 オーナー指示**——番号がメモの末尾にあると、
        /// テンキーに改行キーが無いぶん先へ進めなくなっていた）。
        /// **行より下の広い余白は対象にしない**——そちらは「キャレットを動かさずキーボードだけ戻す」
        /// ままにする（同日の手当て。抜けるたびに末尾へ飛ぶのを防いでいる）。
        /// 行末に番号が無い（`本文p.42のところ`）ときも触らない——行末へ入るのが当たり前の動きで、
        /// それは `UITextView` が自分でやる
        @discardableResult
        func escapePageMarker(in textView: UITextView, tappedAt point: CGPoint) -> Bool {
            guard parent.prefersNumericKeyboard, textView.selectedRange.length == 0 else {
                return false
            }
            let text = textView.text ?? ""
            guard let caret = Range(textView.selectedRange, in: text)?.lowerBound,
                  let escape = MemoPageMarker.lineEndEscape(from: caret, in: text)
            else { return false }

            let destination = NSRange(escape..<escape, in: text).location
            guard tapFollowsLineEnd(at: destination, in: textView, point: point) else {
                return false
            }

            parent.prefersNumericKeyboard = false
            if textView.selectedRange.location != destination {
                isApplyingRequestedState = true
                textView.selectedRange = NSRange(location: destination, length: 0)
                isApplyingRequestedState = false
            }
            parent.selectedRange = textView.selectedRange
            applyStyling(to: textView, accent: UIColor(parent.accentColor))
            return true
        }

        /// 触った点が、その位置の行の**文字の外の余白**か（行の帯から上下に外れていれば偽）。
        /// 左右どちらも見るのは、出典ページの行が右寄せで、余白が番号の**左**にあるため
        private func tapFollowsLineEnd(
            at location: Int,
            in textView: UITextView,
            point: CGPoint
        ) -> Bool {
            let nsText = textView.text as NSString
            let line = nsText.lineRange(for: NSRange(location: min(location, nsText.length), length: 0))
            let manager = textView.layoutManager
            let glyphs = manager.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
            var band = CGRect.null
            var used = CGRect.null
            manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, usedRect, _, _, _ in
                band = band.union(rect)
                used = used.union(usedRect)
            }
            guard !band.isNull, !used.isNull else { return false }

            let inset = textView.textContainerInset
            // 上下は**行に割り当てられた帯**で見る（文字の高さだけだと、狙って触っても外れる）。
            // ページ番号で終わるメモには下に空行を用意してあるので、帯を広く取っても
            // 「行より下の広い余白」とは混ざらない——そこは空行の帯になる
            band = band.offsetBy(dx: inset.left, dy: inset.top)
            used = used.offsetBy(dx: inset.left, dy: inset.top)
            guard band.minY <= point.y, point.y <= band.maxY else { return false }
            return point.x < used.minX || point.x > used.maxX
        }

        /// ページ番号から離れたら通常のキーボードへ戻す（数字キーボードのまま取り残さない）
        private func releaseNumericKeyboardIfNeeded(_ textView: UITextView) {
            guard parent.prefersNumericKeyboard else { return }
            let selection = textView.selectedRange
            guard selection.length == 0,
                  caretFollowsPageMarker(in: textView.text ?? "", at: selection.location)
            else {
                parent.prefersNumericKeyboard = false
                return
            }
        }

        /// キャレットの直前が `p.` または `p.数字` か（数字を打ち進めている間は真のまま）
        private func caretFollowsPageMarker(in text: String, at location: Int) -> Bool {
            guard let caret = Range(NSRange(location: location, length: 0), in: text)?.lowerBound
            else { return false }

            var index = caret
            while index > text.startIndex {
                let previous = text[text.index(before: index)]
                guard previous.isASCII, previous.isNumber else { break }
                index = text.index(before: index)
            }
            guard index > text.startIndex, text[text.index(before: index)] == "." else { return false }
            let dot = text.index(before: index)
            guard dot > text.startIndex else { return false }
            let letter = text[text.index(before: dot)]
            return letter == "p" || letter == "P"
        }

        /// 見えない記号を1文字ずつ消させない。記号の上で削除したら、その装飾のまとまりごと消す。
        /// つながりは全体（チップを消す感覚）、太字は開き・閉じの両方、引用は行頭の `> ` を消す
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            // つながりの中の改行は、括弧の外へ出る操作として扱う（2026-08-12 オーナー指示で
            // 記号を隠したため、`]]` の先へキャレットを送る手がかりが画面に無い）。
            // 改行をそのまま入れると括弧が行をまたいでつながりが壊れるので、通す意味もない
            if replacement == "\n", range.length == 0, textView.markedTextRange == nil,
               let text = textView.text,
               let caret = Range(NSRange(location: range.location, length: 0), in: text)?.lowerBound,
               let pair = MemoLinkParser.enclosingPair(in: text, at: caret) {
                let destination = NSRange(pair.upperBound..<pair.upperBound, in: text).location
                textView.selectedRange = NSRange(location: destination, length: 0)
                parent.selectedRange = textView.selectedRange
                return false
            }

            // 引用のまとまりの先頭でEnterを押したら、引用の上に空行を足す（引用が下がる）。
            // 行頭に見える位置は隠れた `> ` の先なので、そのまま通すと改行が引用の内側に入り、
            // 上に行を足せなかった（2026-08-12 オーナー報告）。改行は `> ` の前へ入れる
            if replacement == "\n", range.length == 0, !isOpeningLineAboveQuote,
               textView.markedTextRange == nil,
               let opening = MemoHiddenMarkers.quoteOpening(
                   forReturnAt: range.location, in: textView.text ?? ""
               ) {
                // 「ひとつ戻す」で戻せるよう、書き換えはテキストビュー経由で行う。
                // 入れた改行がこの規則に再入しないよう、印を立ててから呼ぶ
                isOpeningLineAboveQuote = true
                defer { isOpeningLineAboveQuote = false }
                // **キャレットは新しくできた空行に置く**（**2026-08-12 オーナー確定**——
                // 一般のエディタは文字の側にキャレットを残すが、iOSには矢印キーが無く、
                // 空行へ戻る手段がタップだけになる。そのタップが引用に吸われて
                // 「作った空行に入力できない」状態になったため、標準の挙動から外れる）
                _ = parent.bridge.replace(
                    NSRange(location: opening, length: 0),
                    with: "\n",
                    caretLocation: opening
                )
                return false
            }

            // 引用の中の改行は、その引用の出典ページへの移動として扱う（2026-08-12 オーナー指示）
            if replacement == "\n", textView.markedTextRange == nil,
               let destination = MemoQuotePage.pageCaretLocation(
                   forReturnAt: range.location, in: textView.text ?? ""
               ) {
                textView.selectedRange = NSRange(location: destination, length: 0)
                parent.selectedRange = textView.selectedRange
                return false
            }

            // 数字未入力の出典ページは消させない。消しても足し直すので、通せば `p` だけが残る
            if replacement.isEmpty, range.length == 1,
               MemoQuotePage.protectsDeletion(of: range, in: textView.text ?? "") {
                return false
            }
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

            // 中身が空の括弧は隠してあるので、どこを消しても4文字まとめて消す
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
                // 引用でなくなると、続く空の出典ページの行は置き場を失う（`p.` が本文に残る）。
                // ツールバーで引用を外したときと同じ後始末をする（4.5節）
                guard let page = emptyPageLine(after: lineRange, in: nsText) else { return [prefix] }
                return [prefix, page]
            }

            return nil
        }

        // MARK: - 装飾

        /// 表示（4.6節）と同じ規則で属性を当てる。文字列は変更しない。
        /// 日本語IMEの変換中（markedText あり）は触らない——変換の下線や候補が壊れるため
        func applyStyling(to textView: UITextView, accent: UIColor) {
            guard textView.markedTextRange == nil else {
                colorMarkedTextInsideLink(in: textView, accent: accent)
                return
            }
            let text = textView.text ?? ""
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)

            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            // Enterで分けた段落は折り返しの行より広く空ける（段落の行送りが2倍になる）
            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.paragraphSpacing = MemoEditorTextView.paragraphSpacing
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: bodyStyle
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

            // 引用行: 行頭の「> 」を隠し、囲みの内側に余白ができるよう文字を寄せる。
            // 文字は本文より少し小さく（書籍詳細と同じ）。囲み自体は
            // `MemoQuoteBackgroundLayoutManager` が描く
            let nsText = text as NSString
            let quoteBlocks = MemoTextBlocks.quoteBlockRanges(in: text)
            let quoteFont = UIFont.preferredFont(forTextStyle: .callout)
            for block in quoteBlocks {
                nsText.enumerateSubstrings(
                    in: block, options: [.byLines, .substringNotRequired]
                ) { _, lineRange, _, _ in
                    storage.addAttribute(.font, value: quoteFont, range: lineRange)
                    // 引用の文字は本文より少し薄い黒（濃いめのグレー）
                    storage.addAttribute(
                        .foregroundColor,
                        value: MemoEditorTextView.quoteTextColor,
                        range: lineRange
                    )
                    storage.addAttributes(
                        hiddenAttributes, range: NSRange(location: lineRange.location, length: 2)
                    )
                    storage.addAttribute(
                        .paragraphStyle,
                        value: Self.quoteParagraphStyle(
                            of: lineRange, in: block,
                            lineFragmentPadding: textView.textContainer.lineFragmentPadding
                        ),
                        range: lineRange
                    )
                }
            }
            quoteLayoutManager?.quoteRanges = quoteBlocks
            applyNeighborGaps(around: quoteBlocks, in: nsText, storage: storage)
            // 本文の端の引用は囲みを外へ広げて余白を補うので、その分の余地を作る。
            // 作らないと囲みがヘッダー側へはみ出して見切れる
            let padding = MemoQuoteBackgroundLayoutManager.padding
            let insets = UIEdgeInsets(
                top: MemoEditorTextView.baseTextInset
                    + (quoteBlocks.first?.location == 0 ? padding : 0),
                left: 0,
                bottom: MemoEditorTextView.baseTextInset
                    + (quoteBlocks.last.map { NSMaxRange($0) == nsText.length } == true ? padding : 0),
                right: 0
            )
            if textView.textContainerInset != insets {
                textView.textContainerInset = insets
            }

            // 太字: 中身を太く、記号 ** は隠す
            let boldMarkers = MemoLinkText
                .pairedBoldMarkers(in: text, excluding: linkRanges)
                .sorted()
            for pairStart in stride(from: 0, to: boldMarkers.count - 1, by: 2) {
                let opening = boldMarkers[pairStart]
                let closing = boldMarkers[pairStart + 1]
                let contentStart = text.index(opening, offsetBy: 2)
                let content = NSRange(contentStart..<closing, in: text)
                // 引用の中は文字が小さいので、太字もその行の大きさに合わせる。
                // 太さは `bold` より一段上（**2026-08-12 オーナー指示**——本文との差をはっきり出す）
                let boldFont = UIFont.systemFont(
                    ofSize: Self.fontSize(at: content.location, in: storage, fallback: bodyFont),
                    weight: MemoEditorTextView.boldWeight
                )
                storage.addAttribute(.font, value: boldFont, range: content)
                for marker in [opening..<contentStart, closing..<text.index(closing, offsetBy: 2)] {
                    storage.addAttributes(hiddenAttributes, range: NSRange(marker, in: text))
                }
            }

            // ページ番号: 表示と同じバッジ風（つながりのラベル内と、引用の出典ページの行は除外）
            let quotePageLines = MemoTextBlocks.quotePageLineRanges(in: text)
            let pageFont = UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .medium
            )
            var pageBadges: [NSRange] = []
            for page in MemoPageMarker.ranges(in: text)
            where !linkRanges.contains(where: { $0.contains(page.lowerBound) }) {
                let range = NSRange(page, in: text)
                guard !quotePageLines.contains(where: { NSLocationInRange(range.location, $0) })
                else { continue }
                storage.addAttribute(.font, value: pageFont, range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                // バッジの左右に場所を作る（本文の文字は足さず、字送りだけ広げる）
                let spacing = MemoQuoteBackgroundLayoutManager.pageBadgeSpacing
                storage.addAttribute(
                    .kern, value: spacing, range: NSRange(location: NSMaxRange(range) - 1, length: 1)
                )
                let line = nsText.lineRange(for: range)
                if range.location > line.location {
                    storage.addAttribute(
                        .kern, value: spacing,
                        range: NSRange(location: range.location - 1, length: 1)
                    )
                } else {
                    // 行頭のバッジは字送りでは空きを作れない——直前は前の行の改行なので、
                    // 広げると前の行が伸びる（未確定文字の囲みがはみ出して見えた・2026-08-12 オーナー報告）。
                    // 代わりに行を字下げして、バッジの左端が他の行の文字に揃うようにする
                    let inherited = storage.attribute(
                        .paragraphStyle, at: range.location, effectiveRange: nil
                    ) as? NSParagraphStyle
                    let style = inherited?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    style.firstLineHeadIndent = MemoQuoteBackgroundLayoutManager.pageBadgeInset.width
                    storage.addAttribute(.paragraphStyle, value: style, range: line)
                }
                // 背景は角丸とまわりの余白を持たせるためレイアウト機構が描く
                pageBadges.append(range)
            }
            quoteLayoutManager?.pageBadgeRanges = pageBadges

            // 出典ページの行: 囲みの枠外・右下へ。装飾は付けず小さくするだけ（オーナー指示）。
            // 数字が未入力なら `p.` を隠して案内を描く
            // （行の高さは残す——潰れるとカーソルも案内も置き場を失う）
            var emptyPageLines: [NSRange] = []
            let pageLineFont = UIFont.preferredFont(forTextStyle: .footnote)
            let caret = textView.selectedRange
            for line in quotePageLines {
                let style = NSMutableParagraphStyle()
                style.alignment = .right
                style.minimumLineHeight = pageLineFont.lineHeight
                style.paragraphSpacingBefore = MemoQuoteBackgroundLayoutManager.gapToNeighbor
                style.paragraphSpacing = MemoQuoteBackgroundLayoutManager.gapToNeighbor
                storage.addAttribute(.paragraphStyle, value: style, range: line)
                storage.addAttribute(.font, value: pageLineFont, range: line)
                guard MemoQuotePage.digits(inPageOnlyLine: nsText.substring(with: line))?.isEmpty
                    == true else { continue }

                // 数字が未入力の行: キャレットが乗っている間は `p.` を出す（数字を打つ位置が分かる）。
                // 離れている間は隠して、代わりに案内を描く
                let focused = caret.length == 0
                    && (NSLocationInRange(caret.location, line) || caret.location == NSMaxRange(line))
                if !focused {
                    storage.addAttributes(hiddenAttributes, range: line)
                    emptyPageLines.append(line)
                }
            }
            quoteLayoutManager?.pageHintRanges = emptyPageLines

            // つながり: 中身をテーマ色＋セミボールド、括弧は隠す
            for link in links {
                let range = NSRange(link.range, in: text)
                let linkFont = UIFont.systemFont(
                    ofSize: Self.fontSize(at: range.location, in: storage, fallback: bodyFont),
                    weight: .semibold
                )
                storage.addAttribute(.font, value: linkFont, range: range)
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                let opening = link.range.lowerBound..<text.index(link.range.lowerBound, offsetBy: 2)
                let closing = text.index(link.range.upperBound, offsetBy: -2)..<link.range.upperBound
                for brackets in [opening, closing] {
                    storage.addAttributes(hiddenAttributes, range: NSRange(brackets, in: text))
                }
            }

            // いま中にいるつながりは、テーマ色を薄く敷いて範囲を見せる
            // （**2026-08-12 オーナー指示**——記号が見えないので、色だけではどこまでが
            // ひとまとまりなのか分からない）
            let writingLink = Self.linkRange(enclosing: caret, in: text)
            if let writingLink {
                storage.addAttribute(
                    .backgroundColor,
                    value: accent.withAlphaComponent(MemoEditorTextView.linkBackgroundAlpha),
                    range: writingLink
                )
            }

            // まだ中身が空の `[[]]`（「つなぐ」を押した直後の形）も記号を隠す
            // （2026-08-12 オーナー指示——`[[ ]]` はMarkdownを知らない人には意味が分からない）。
            // 何を書く場所なのかは、キャレットが中にある間だけ案内で伝える
            quoteLayoutManager?.linkHintRange = emptyLinkHint(
                in: text, nsText: nsText, caret: caret, storage: storage,
                hiddenAttributes: hiddenAttributes
            )

            storage.endEditing()
            textView.typingAttributes = typingAttributes(
                base: baseAttributes, writingLink: writingLink,
                in: text, caret: caret, storage: storage, accent: accent
            )
            textView.setNeedsDisplay()
        }

        /// これから打つ文字に当てる属性。**つながりの括弧の中では色を先に決めておく**
        /// （**2026-08-12 オーナー指示**——1打目から色を出す。入力後に当て直す形だと、
        /// 日本語では変換を確定するまで色が変わらず、確定後も一拍遅れて見えた）。
        /// IMEの変換中の文字もこの属性で入るので、打ち始めた瞬間から色と背景が付く
        private func typingAttributes(
            base: [NSAttributedString.Key: Any],
            writingLink: NSRange?,
            in text: String,
            caret: NSRange,
            storage: NSTextStorage,
            accent: UIColor
        ) -> [NSAttributedString.Key: Any] {
            guard writingLink != nil else { return base }
            var attributes = base

            // 行の見た目（引用なら小さめの文字・字下げ）は保つ
            let nsText = text as NSString
            let line = nsText.lineRange(for: NSRange(location: min(caret.location, nsText.length), length: 0))
            if line.length > 0, line.location < storage.length,
               let style = storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) {
                attributes[.paragraphStyle] = style
            }
            let isQuoteLine = line.length >= 2
                && nsText.substring(with: NSRange(location: line.location, length: 2)) == "> "
            let font = UIFont.preferredFont(forTextStyle: isQuoteLine ? .callout : .body)

            attributes[.font] = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
            attributes[.foregroundColor] = accent
            attributes[.backgroundColor] = accent
                .withAlphaComponent(MemoEditorTextView.linkBackgroundAlpha)
            return attributes
        }

        /// キャレットが中にいるつながり（中身が空の `[[]]` も含む）の範囲
        private static func linkRange(enclosing caret: NSRange, in text: String) -> NSRange? {
            guard caret.length == 0,
                  let index = Range(caret, in: text)?.lowerBound,
                  let pair = MemoLinkParser.enclosingPair(in: text, at: index)
            else { return nil }
            return NSRange(pair, in: text)
        }

        /// 変換中の文字がつながりの括弧の中にあるあいだは、その範囲をテーマ色にする
        /// （**2026-08-12 オーナー指示**）。ふだんは打つ前に決めた属性（`typingAttributes`）で
        /// 色が付くが、確定済みの文字を選び直して再変換したときはここが受け持つ。
        ///
        /// 装飾を当て直すのではなく**属性を足すだけ**にするのが要点——`setAttributes` で
        /// 全体を置き換えると、IMEが変換中の文字に付けている下線まで消える。日本語入力の
        /// 変換中は他の装飾に触らないという防御（4.6節）は、この一点をくり抜いて残す
        private func colorMarkedTextInsideLink(in textView: UITextView, accent: UIColor) {
            guard let marked = textView.markedTextRange else { return }
            let location = textView.offset(from: textView.beginningOfDocument, to: marked.start)
            let length = textView.offset(from: marked.start, to: marked.end)
            guard length > 0 else { return }

            let text = textView.text ?? ""
            guard let start = Range(NSRange(location: location, length: 0), in: text)?.lowerBound,
                  let pair = MemoLinkParser.enclosingPair(in: text, at: start)
            else { return }

            let storage = textView.textStorage
            storage.addAttribute(
                .foregroundColor, value: accent,
                range: NSRange(location: location, length: length)
            )
            storage.addAttribute(
                .backgroundColor,
                value: accent.withAlphaComponent(MemoEditorTextView.linkBackgroundAlpha),
                range: NSRange(pair, in: text)
            )
        }

        /// 中身が空の `[[]]` の記号を隠し、案内を描く位置を返す（無ければ `nil`）。
        ///
        /// 案内を出すのは**キャレットが括弧の中にあり、その行に続きの文字が無いとき**だけ——
        /// 行の途中で「つなぐ」を押した場合は、案内が後ろの文字に重なってしまう。
        /// あわせて、記号しか無い行は高さを本文の1行分だけ確保する（隠すと潰れて
        /// カーソルも案内も置き場を失う。出典ページの行と同じ手当て）
        private func emptyLinkHint(
            in text: String,
            nsText: NSString,
            caret: NSRange,
            storage: NSTextStorage,
            hiddenAttributes: [NSAttributedString.Key: Any]
        ) -> NSRange? {
            var hint: NSRange?
            for pair in MemoLinkParser.emptyPairs(in: text) {
                let range = NSRange(pair, in: text)
                storage.addAttributes(hiddenAttributes, range: range)

                let line = nsText.lineRange(for: range)
                let head = NSRange(
                    location: line.location, length: range.location - line.location
                )
                let tail = NSRange(
                    location: NSMaxRange(range),
                    length: max(0, NSMaxRange(line) - NSMaxRange(range))
                )
                let tailIsBlank = isBlank(nsText.substring(with: tail))
                if tailIsBlank, isBlank(nsText.substring(with: head)) {
                    let inherited = storage.attribute(
                        .paragraphStyle, at: range.location, effectiveRange: nil
                    ) as? NSParagraphStyle
                    let style = inherited?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    style.minimumLineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                    storage.addAttribute(.paragraphStyle, value: style, range: line)
                }

                if caret.length == 0, caret.location > range.location,
                   caret.location < NSMaxRange(range), tailIsBlank {
                    hint = range
                }
            }
            return hint
        }

        /// `line` の次が数字未入力の出典ページの行なら、その行（手前の改行を含む）
        private func emptyPageLine(after line: NSRange, in nsText: NSString) -> NSRange? {
            let next = NSMaxRange(line)
            guard next < nsText.length else { return nil }
            let pageLine = nsText.lineRange(for: NSRange(location: next, length: 0))
            let content = nsText.substring(with: pageLine)
                .trimmingCharacters(in: .newlines)
            guard MemoQuotePage.digits(inPageOnlyLine: content)?.isEmpty == true else { return nil }
            return NSRange(location: next - 1, length: content.count + 1)
        }

        private func isBlank(_ text: String) -> Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// その位置に当たっている文字の大きさ（引用行なら小さいほう）
        private static func fontSize(
            at location: Int,
            in storage: NSTextStorage,
            fallback: UIFont
        ) -> CGFloat {
            guard location >= 0, location < storage.length,
                  let font = storage.attribute(.font, at: location, effectiveRange: nil) as? UIFont
            else { return fallback.pointSize }
            return font.pointSize
        }

        /// 引用行の段落スタイル。左右は字下げで、上下はまとまりの最初と最後の行の前後空きで
        /// 余白を作る（この空きは行の領域に含まれ、そのまま囲みの内側の余白になる）。
        /// まとまりの内側の行には前後の空きを付けない（1つの囲みが行ごとに割れないようにする）
        private static func quoteParagraphStyle(
            of lineRange: NSRange,
            in block: NSRange,
            lineFragmentPadding: CGFloat
        ) -> NSParagraphStyle {
            let padding = MemoQuoteBackgroundLayoutManager.padding
            let style = NSMutableParagraphStyle()
            let indent = max(0, padding - lineFragmentPadding)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.tailIndent = -indent
            if lineRange.location == block.location {
                style.paragraphSpacingBefore = padding
            }
            if lineRange.location + lineRange.length == block.location + block.length {
                style.paragraphSpacing = padding
            }
            return style
        }

        /// 囲みの外側（前後の行）に間隔を空ける。囲みは行の領域いっぱいに描くので、
        /// この空きが無いと隣の行の文字が囲みの縁に触れる
        private func applyNeighborGaps(
            around blocks: [NSRange],
            in nsText: NSString,
            storage: NSTextStorage
        ) {
            // 前後どちらの隣にもなる行（引用に挟まれた1行）があるので、行ごとにまとめてから当てる
            var gaps: [Int: (range: NSRange, before: Bool, after: Bool)] = [:]
            func mark(at location: Int, before: Bool) {
                guard location >= 0, location < nsText.length else { return }
                let line = nsText.lineRange(for: NSRange(location: location, length: 0))
                var gap = gaps[line.location] ?? (line, false, false)
                if before { gap.before = true } else { gap.after = true }
                gaps[line.location] = gap
            }

            for block in blocks {
                mark(at: block.location - 1, before: false)
                mark(at: block.location + block.length + 1, before: true)
            }

            for gap in gaps.values {
                // 空行を詰めない（**2026-08-12 オーナー報告**——引用の隣の空行は
                // 「そこに書くために空けた行」なので、詰めると触れる幅が狭くなり、
                // 囲みの内側の余白と紛れてタップが引用に吸われる）。
                // 詰めるのは文字のある行だけ——囲みと本文が離れて見えるのを防ぐための手当てなので、
                // 文字が無いなら詰める理由がない
                let isBlank = nsText.substring(with: gap.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let style = NSMutableParagraphStyle()
                // 囲みに面していない側は段落の空きのまま（本文どうしの行送りを変えない）
                style.paragraphSpacing = MemoEditorTextView.paragraphSpacing
                if !isBlank {
                    if gap.before {
                        style.paragraphSpacingBefore = MemoQuoteBackgroundLayoutManager.gapToNeighbor
                    }
                    if gap.after {
                        style.paragraphSpacing = MemoQuoteBackgroundLayoutManager.gapToNeighbor
                    }
                }
                storage.addAttribute(.paragraphStyle, value: style, range: gap.range)
            }
        }
    }
}
