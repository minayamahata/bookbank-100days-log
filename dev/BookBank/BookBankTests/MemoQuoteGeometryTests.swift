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
            style.paragraphSpacing = MemoQuoteBackgroundLayoutManager.paddingBottom
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
            #expect(
                box.maxY - textArea.maxY >= MemoQuoteBackgroundLayoutManager.paddingBottom - 0.5,
                "下の余白が残る: \(text)"
            )
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

    /// つながりの案内も本文の文字ではなく描画であることを固定する（**2026-08-12 オーナー指摘13**——
    /// 「つなぐ」を押すとキーボード上部の予測変換バーに表示が出る件の切り分け）。
    /// 本文に入るのは括弧の4文字だけで、案内は一切混ざらない
    @Test func linkHintIsDrawnAndNeverEntersTheMemoText() {
        let text = "[[]]"
        let (textView, layoutManager, _) = makeTextView(text: text)
        let pair = (text as NSString).range(of: text)
        textView.textStorage.addAttributes(
            [.font: UIFont.systemFont(ofSize: 0.01), .foregroundColor: UIColor.clear],
            range: pair
        )
        layoutManager.linkHintRange = pair
        layoutManager.ensureLayout(for: textView.textContainer)

        let everything = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: (text as NSString).length),
            actualCharacterRange: nil
        )
        func render(hint: NSAttributedString?) -> Data? {
            layoutManager.linkHint = hint
            return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
                .image { _ in layoutManager.drawBackground(forGlyphRange: everything, at: .zero) }
                .pngData()
        }

        let hint = NSAttributedString(
            string: "つながりを入力",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.tertiaryLabel
            ]
        )
        #expect(render(hint: hint) != render(hint: nil), "案内が描かれている")
        #expect(textView.text == text, "案内は本文の文字にならない（バーに出るのは記号への反応）")
    }

    /// メモの先頭が引用のとき、見た目の行頭でEnterを押したら**引用の上に**空行ができる
    /// （**2026-08-12 オーナー報告**——行頭に見える位置は隠れた `> ` の先なので、そのまま
    /// 通すと改行が引用の内側に入り、上に行を足せなかった）。
    /// 書き換えはテキストビュー経由なので「ひとつ戻す」でも戻せる
    @Test func returnAtTheHeadOfAQuoteOpensALineAbove() {
        let memo = "> 引用の行\np."
        let bridge = MemoEditorBridge()
        let editor = MemoEditorTextView(
            text: .constant(memo),
            selectedRange: .constant(NSRange(location: 2, length: 0)),
            prefersNumericKeyboard: .constant(false),
            accentColor: .blue,
            bridge: bridge
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        textView.text = memo
        textView.selectedRange = NSRange(location: 2, length: 0)
        bridge.textView = textView

        let allowed = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 2, length: 0),
            replacementText: "\n"
        )

        #expect(allowed == false, "改行は自分で入れる（そのまま通すと引用の内側に入る）")
        #expect(textView.text == "\n" + memo, "引用の上に空行ができ、引用は下がる")
        #expect(textView.selectedRange.location == 0, "キャレットは作った空行に入る（そのまま書ける）")
        #expect(bridge.canUndo, "「ひとつ戻す」で戻せる")
    }

    /// ページ番号と同じ行の余白を触ったら、番号の外へ出て通常のキーボードに戻る
    /// （**2026-08-12 オーナー報告**——メモの末尾がページ番号だと、テンキーに改行キーが
    /// 無いぶん先へ進めなくなっていた）。行より下の広い余白は対象にしない——そちらは
    /// 「キャレットを動かさずキーボードだけ戻す」ままにする（同日の別の手当て）
    @Test func tappingPastAPageNumberLeavesTheNumberPad() throws {
        func escape(memo: String, caret: Int, point: (CGRect) -> CGPoint) throws -> (
            escaped: Bool, numeric: Bool, caret: Int
        ) {
            // 編集画面に載る形（ページ番号で終わるメモには行き先の空行が付く）で測る
            let prepared = MemoQuotePage.preparedForEditing(memo)
            let numeric = Flag(true)
            let editor = MemoEditorTextView(
                text: .constant(prepared),
                selectedRange: .constant(NSRange(location: caret, length: 0)),
                prefersNumericKeyboard: Binding(
                    get: { numeric.value }, set: { numeric.value = $0 }
                ),
                accentColor: .blue,
                bridge: MemoEditorBridge()
            )
            let coordinator = editor.makeCoordinator()
            let (textView, manager, storage) = makeTextView(text: prepared)
            coordinator.quoteLayoutManager = manager
            coordinator.textStorage = storage
            textView.selectedRange = NSRange(location: caret, length: 0)
            // 出典ページの行は右寄せなど見た目の手当てが入るので、本番と同じ組み方で測る
            coordinator.applyStyling(to: textView, accent: .blue)
            manager.ensureLayout(for: textView.textContainer)

            let line = manager.lineFragmentUsedRect(
                forGlyphAt: manager.glyphIndexForCharacter(at: caret - 1), effectiveRange: nil
            ).offsetBy(dx: 0, dy: textView.textContainerInset.top)
            let escaped = coordinator.escapePageMarker(in: textView, tappedAt: point(line))
            return (escaped, numeric.value, textView.selectedRange.location)
        }

        // 末尾がページ番号: 同じ行の右の余白を触ると番号の外へ出て、通常のキーボードに戻る
        let sameLine = try escape(memo: "本文p.42", caret: 6) {
            CGPoint(x: $0.maxX + 40, y: $0.midY)
        }
        #expect(sameLine.escaped)
        #expect(sameLine.numeric == false, "テンキーから抜ける（ここから改行できる）")
        #expect(sameLine.caret == 6, "キャレットはページ番号の直後")

        // 行より下（行き先の空行やその下の余白）は現状維持——キャレットを動かさず
        // キーボードだけ戻す側の担当
        let below = try escape(memo: "本文p.42", caret: 6) {
            CGPoint(x: $0.maxX + 40, y: $0.maxY + 40)
        }
        #expect(below.escaped == false)
        #expect(below.numeric, "触った先が行の外なら、この規則は何もしない")

        // 文字の上を触ったときも何もしない（`UITextView` が自分でその場所へ入れる）
        let onText = try escape(memo: "本文p.42", caret: 6) {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        #expect(onText.escaped == false)

        // 行末に番号が無ければ触らない（行末へ入るのが当たり前の動き）
        let midLine = try escape(memo: "本文p.42のところ", caret: 6) {
            CGPoint(x: $0.maxX + 40, y: $0.midY)
        }
        #expect(midLine.escaped == false)

        // 触ったこと自体を受け取れる状態か——キャレットが既に行末に在ると位置が動かず、
        // 選択の変化を待つ作りではこの場面を拾えない（それで抜けられなくなっていた）
        let (editorTextView, _) = try Self.makeEditor(memo: "本文p.42")
        #expect(
            editorTextView.gestureRecognizers?.contains {
                $0 is UITapGestureRecognizer && $0.delegate is MemoEditorTextView.Coordinator
            } == true
        )
        #expect(editorTextView.text == "本文p.42\n", "文中のページ番号でも行き先の空行を用意する")

        // 引用の出典ページ（右寄せの行）は、余白が番号の**左**にある
        let quotePage = try escape(memo: "> 引用\np.83", caret: 8) {
            CGPoint(x: max($0.minX - 40, 0), y: $0.midY)
        }
        #expect(quotePage.escaped)
        #expect(quotePage.numeric == false)
    }

    private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    /// 引用の冒頭がつながりでも、行頭でEnterを押せば上に空行ができる
    /// （**2026-08-12 オーナー報告A**——`> ` を飛ばした先がそのまま `[[` の中になり、
    /// 行頭に見える位置がつながりの内側だった。そこでEnterを押すと「括弧の外へ出る」規則が
    /// 先に効いて、引用の上に行を足せなかった）
    @Test func quoteThatStartsWithALinkStillOpensALineAbove() throws {
        let memo = "> [[負け]]るのは\np."
        let (textView, manager) = try Self.makeEditor(memo: memo)

        // 見た目の行頭（文字の直前）を触ると、キャレットはつながりの**外**に立つ
        let quoteLine = manager.lineFragmentUsedRect(
            forGlyphAt: manager.glyphIndexForCharacter(at: 0), effectiveRange: nil
        ).offsetBy(dx: 0, dy: textView.textContainerInset.top)
        let position = try #require(
            textView.closestPosition(to: CGPoint(x: quoteLine.minX + 1, y: quoteLine.midY))
        )
        let tapped = textView.offset(from: textView.beginningOfDocument, to: position)
        let caret = MemoHiddenMarkers.caretLocation(snapping: tapped, in: textView.text)
        #expect(caret == 2, "行頭は `> ` の先・`[[` の前（つながりの中に入らない）")

        // そこでEnterを押すと引用の上に空行ができる（つながりの外へ出る規則より先）
        textView.selectedRange = NSRange(location: caret, length: 0)
        let allowed = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: NSRange(location: caret, length: 0),
            replacementText: "\n"
        ) ?? true
        #expect(allowed == false)
        #expect(textView.text == "\n" + "> [[負け]]るのは\np.\n", "引用の上に空行ができる")
        #expect(textView.selectedRange.location == 0, "キャレットは作った空行に入る")
    }

    /// 引用の隣の空行は触れる幅を残す（**2026-08-12 オーナー報告**——引用の上の空行を
    /// タップするとカーソルが引用に入ってしまい、作った空行に書けなかった）。
    /// 囲みの内側の余白（18pt）は引用の行の領域なので、そこを触れば引用に入るのが正しい。
    /// 空行の領域が狭いと指のわずかなずれで余白側に落ちるため、空行は詰めないでおく
    @Test func blankLinesNextToAQuoteStayTappable() throws {
        let lineHeight = AppTypography.uiFont(.body).lineHeight

        for memo in [
            "\n> 引用の行\np.",
            // 引用の冒頭がつながり（**2026-08-12 オーナー報告A**——この形でだけ空行へ戻れなかった）
            "\n> [[負け]]るのは\np.",
            "> 引用の行\np.\n\nあとの行",
            "> 一\np.\n\n> 二\np."
        ] {
            let (textView, manager) = try Self.makeEditor(memo: memo)
            let nsText = textView.text as NSString

            var blanks: [Int] = []
            var location = 0
            while location < nsText.length {
                let line = nsText.lineRange(for: NSRange(location: location, length: 0))
                if nsText.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    blanks.append(line.location)
                }
                location = NSMaxRange(line)
            }
            try #require(!blanks.isEmpty, "空行のあるメモで見る: \(memo.debugDescription)")

            for blank in blanks {
                let glyph = manager.glyphIndexForCharacter(at: blank)
                let band = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    .offsetBy(dx: 0, dy: textView.textContainerInset.top)

                #expect(
                    band.height >= lineHeight + MemoEditorTextView.paragraphSpacing - 0.5,
                    "引用の隣でも空行は詰めない: \(memo.debugDescription)"
                )
                for y in [band.minY + 2, band.midY, band.maxY - 2] {
                    let position = try #require(
                        textView.closestPosition(to: CGPoint(x: 150, y: y))
                    )
                    #expect(
                        textView.offset(from: textView.beginningOfDocument, to: position) == blank,
                        "空行の領域を触ったら空行にカーソルが入る: \(memo.debugDescription) y=\(y)"
                    )
                }
            }
        }
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

    /// 空けるのは引用の**まとまりの下**——囲みと出典ページのあいだは詰めたまま、
    /// 出典ページの下を広く空ける（**2026-08-12 オーナー指示**で18→30）
    @Test func quoteKeepsAWiderGapBelowItsPageLine() throws {
        let (textView, manager) = try Self.makeEditor(memo: "まえの行\n> 引用\np.83\nあとの行")
        let box = try #require(manager.quoteBoxes().first)
        let nsText = textView.text as NSString

        let page = nsText.range(of: "p.83")
        let pageRect = manager.lineFragmentUsedRect(
            forGlyphAt: manager.glyphIndexForCharacter(at: page.location), effectiveRange: nil
        )
        #expect(
            pageRect.minY - box.maxY < MemoQuoteBackgroundLayoutManager.gapBelowQuote,
            "囲みと出典ページは同じかたまりとして詰まっている"
        )

        let tail = nsText.range(of: "あとの行")
        let tailTop = manager.lineFragmentUsedRect(
            forGlyphAt: manager.glyphIndexForCharacter(at: tail.location), effectiveRange: nil
        ).minY
        #expect(
            tailTop - pageRect.maxY >= MemoQuoteBackgroundLayoutManager.gapBelowQuote - 0.5,
            "出典ページの下は30空ける"
        )

        let headBottom = manager.lineFragmentUsedRect(
            forGlyphAt: manager.glyphIndexForCharacter(at: 0), effectiveRange: nil
        ).maxY
        #expect(
            box.minY - headBottom >= MemoQuoteBackgroundLayoutManager.gapToNeighbor - 0.5,
            "囲みの上の空きは残る"
        )
        #expect(
            box.minY - headBottom < MemoQuoteBackgroundLayoutManager.gapBelowQuote,
            "広げるのは下だけ（上は6のまま）"
        )
    }

    /// バッジ直後のカーソルは、テンキーで打っているあいだは枠の中、抜けたら枠の右外に立つ
    /// （**2026-08-12 オーナー指示**——タップで抜けても枠の中に見えたままで、
    /// Enterを押して初めて抜けたと分かる状態だった。位置は同じで、見せ方だけを切り替える）
    @Test func caretStepsOutOfThePageBadgeAfterLeavingTheNumberPad() throws {
        let (textView, manager) = try Self.makeEditor(memo: "本文p.42")
        let aligned = try #require(textView as? MemoCaretAlignedTextView)
        let position = try #require(
            textView.position(from: textView.beginningOfDocument, offset: 6)
        )
        let badge = try #require(manager.pageBadgeBoxes().first)

        aligned.pullsCaretIntoPageBadge = true
        let typing = textView.caretRect(for: position)
        #expect(typing.minX < badge.maxX, "番号を打っているあいだは枠の中")

        aligned.pullsCaretIntoPageBadge = false
        let escaped = textView.caretRect(for: position)
        #expect(escaped.minX >= badge.maxX, "抜けたら背景の右外（字送りの余白）に立つ")
        #expect(
            abs((escaped.minX - typing.minX) - MemoQuoteBackgroundLayoutManager.pageBadgeSpacing)
                < 0.5,
            "違いは字送りの寄せだけ（文書の中の位置は同じ）"
        )
    }

    /// 下からのデリート長押しは出典ページ行を飛び越える（設計メモ 4.6節・2026-08-20 オーナー報告）。
    /// テンキーへ切り替わらず、キーリピートごとに削除が前進し、全文を消し切れることを固定する
    @Test func deletingFromBelowSkipsThePageLineAndKeepsTheDefaultKeyboard() throws {
        // 数字未入力の p.
        let empty = makeDeletionEditor(memo: "> 引用\np.\n", caret: 8)
        #expect(pressBackspace(empty.textView, coordinator: empty.coordinator))
        #expect(empty.textView.text == "> 引\np.\n", "ページ行を飛ばして引用側の削除が1段階進む")
        #expect(empty.textView.selectedRange == NSRange(location: 3, length: 0))
        #expect(empty.numeric.value == false, "テンキーへ切り替わらない（「3」に変わらない）")

        // 長押し相当: 途中で止まらず全文を消し切り、ページ番号が残らない
        for _ in 0..<20 where !empty.textView.text.isEmpty {
            let before = (empty.textView.text ?? "", empty.textView.selectedRange)
            #expect(pressBackspace(empty.textView, coordinator: empty.coordinator),
                    "キャレットの前に消すものがある限り前進する")
            #expect(empty.numeric.value == false, "全区間でテンキーへ切り替わらない")
            let after = (empty.textView.text ?? "", empty.textView.selectedRange)
            try #require(before != after, "削除が空振りしない（長押しがページ番号で停止しない）")
        }
        #expect(empty.textView.text == "", "全文削除でページ番号だけが残らない")

        // 数字入りの p.42 でも同じ（複数行の引用＋連続する引用）
        let filled = makeDeletionEditor(memo: "> 一\n> 二\np.12\n> 三\np.34\n", caret: nil)
        for _ in 0..<40 where !filled.textView.text.isEmpty {
            let before = (filled.textView.text ?? "", filled.textView.selectedRange)
            _ = pressBackspace(filled.textView, coordinator: filled.coordinator)
            #expect(filled.numeric.value == false)
            let after = (filled.textView.text ?? "", filled.textView.selectedRange)
            try #require(before != after, "p.42 形式でも停止しない")
        }
        #expect(filled.textView.text == "", "連続する引用でも各ページ行ごと消し切れる")
    }

    /// 削除を途中でやめれば引用とページ番号は保持され、「ひとつ戻す」で復元できる。
    /// 絵文字は途中で壊さない
    @Test func stoppingMidwayKeepsThePageLineAndUndoRestoresTheDeletion() throws {
        let editor = makeDeletionEditor(memo: "> 引用\np.42\nあと", caret: 12)
        // 「あと」→ページ行の改行（振り替え）まで3回消して止める
        for _ in 0..<3 {
            #expect(pressBackspace(editor.textView, coordinator: editor.coordinator))
        }
        #expect(editor.textView.text == "> 引\np.42\n", "通過中のページ番号は引用に付いたまま残る")
        #expect(editor.numeric.value == false)

        // 「ひとつ戻す」で直前の削除（振り替えで消えた引用側の1文字）が戻る
        editor.bridge.undo()
        #expect(editor.textView.text == "> 引用\np.42\n", "振り替えた削除も取り消しの履歴に載る")

        // 絵文字を含む引用: 家族の絵文字は1回の削除で丸ごと消える
        let family = makeDeletionEditor(memo: "> 👨‍👩‍👧‍👦\np.\n", caret: nil)
        #expect(pressBackspace(family.textView, coordinator: family.coordinator))
        #expect(family.textView.text == "> \np.\n", "サロゲートペアを途中で壊さない")
    }

    /// 従来動作の維持: ページ番号を自分でタップすればテンキー、引用内のEnterでページ番号へ移動、
    /// ページ番号の直接編集中は数字を1文字ずつ消せる
    @Test func tappingAndReturnStillReachThePageNumberAsBefore() throws {
        let editor = makeDeletionEditor(memo: "> 引用\np.42\n", caret: 4)

        // 引用の中でEnter → その引用のページ番号の行末へ移動し、テンキーになる
        let returnAllowed = editor.coordinator.textView(
            editor.textView,
            shouldChangeTextIn: NSRange(location: 4, length: 0),
            replacementText: "\n"
        )
        #expect(returnAllowed == false)
        #expect(editor.textView.selectedRange == NSRange(location: 9, length: 0),
                "引用内のEnterは従来どおりページ番号へ移動する")
        #expect(editor.numeric.value, "移動先ではテンキーになる")

        // ページ番号の直接編集中: 数字は従来どおり1文字ずつ消せる（振り替えない）
        let digitAllowed = editor.coordinator.textView(
            editor.textView,
            shouldChangeTextIn: NSRange(location: 8, length: 1),
            replacementText: ""
        )
        #expect(digitAllowed, "数字の削除はそのまま通す")

        // ページ番号を自分でタップした場合もテンキー（下からの削除で到達した場合と区別する）
        let tapped = makeDeletionEditor(memo: "> 引用\np.42\n", caret: 4)
        tapped.textView.selectedRange = NSRange(location: 9, length: 0)
        #expect(tapped.numeric.value, "タップでページ番号に入ればテンキー")

        // 引用と無関係な単独の p.42 は飛ばさない（ふつうに改行の削除が通る）
        let standalone = makeDeletionEditor(memo: "本文\np.42\nあ", caret: 8)
        let plainAllowed = standalone.coordinator.textView(
            standalone.textView,
            shouldChangeTextIn: NSRange(location: 7, length: 1),
            replacementText: ""
        )
        #expect(plainAllowed, "単独のページ番号行は特別扱いしない")
    }

    /// 削除の飛び越えテスト用のエディタ一式。`caret: nil` は本文末尾
    private func makeDeletionEditor(
        memo: String, caret: Int?
    ) -> (
        textView: UITextView,
        coordinator: MemoEditorTextView.Coordinator,
        numeric: Flag,
        bridge: MemoEditorBridge
    ) {
        let numeric = Flag(false)
        let bridge = MemoEditorBridge()
        let location = caret ?? (memo as NSString).length
        let editor = MemoEditorTextView(
            text: .constant(memo),
            selectedRange: .constant(NSRange(location: location, length: 0)),
            prefersNumericKeyboard: Binding(
                get: { numeric.value }, set: { numeric.value = $0 }
            ),
            accentColor: .blue,
            bridge: bridge
        )
        let coordinator = editor.makeCoordinator()
        let (textView, manager, storage) = makeTextView(text: memo)
        coordinator.quoteLayoutManager = manager
        coordinator.textStorage = storage
        textView.delegate = coordinator
        bridge.textView = textView
        textView.selectedRange = NSRange(location: location, length: 0)
        coordinator.applyStyling(to: textView, accent: .blue)
        return (textView, coordinator, numeric, bridge)
    }

    /// デリートキー1回ぶんの後退削除（キーリピートの1周期に相当）。
    /// 消すものが無ければ false。許可された削除はシステムと同じ順で反映する
    @discardableResult
    private func pressBackspace(
        _ textView: UITextView, coordinator: MemoEditorTextView.Coordinator
    ) -> Bool {
        let caret = textView.selectedRange
        guard caret.length == 0, caret.location > 0 else { return false }
        let nsText = textView.text as NSString
        let target = nsText.rangeOfComposedCharacterSequence(at: caret.location - 1)
        let allowed = coordinator.textView(textView, shouldChangeTextIn: target, replacementText: "")
        if allowed {
            textView.textStorage.replaceCharacters(in: target, with: "")
            textView.selectedRange = NSRange(location: target.location, length: 0)
            coordinator.textViewDidChange(textView)
        }
        return true
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
