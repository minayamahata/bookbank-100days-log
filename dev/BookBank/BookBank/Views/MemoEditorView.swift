//
//  MemoEditorView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI

struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var memo: String
    
    @State private var editedText: String
    @State private var showCancelAlert = false
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var prefersNumericKeyboard = false
    /// ツールバーの書き換えと「ひとつ戻す」をテキストビューへ渡す通り道
    @State private var bridge = MemoEditorBridge()
    
    let title: LocalizedStringKey
    /// 「つなぐ」ボタンを出すか。月メモはT1のスコープ外なので出さない（設計メモ 4.3節）
    let allowsLinks: Bool
    /// つながりの着色とページ番号バッジに使う色（黒テーマ＋ダーク時の退避は呼び出し側の責務）
    let accentColor: Color
    let onSave: (String) -> Void
    
    init(
        memo: Binding<String>,
        title: LocalizedStringKey = "book.memo",
        allowsLinks: Bool = false,
        accentColor: Color = .accentColor,
        onSave: @escaping (String) -> Void
    ) {
        self._memo = memo
        // 既にある引用にも出典ページの案内を出す（入力されなければ保存時に落ちる）
        self._editedText = State(
            initialValue: MemoQuotePage.preparedForEditing(memo.wrappedValue)
        )
        self.title = title
        self.allowsLinks = allowsLinks
        self.accentColor = accentColor
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                // プレースホルダー
                if editedText.isEmpty {
                    Text("book.memo.placeholder")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
                
                // 編集中も表示と同じ装飾をその場で反映するエディタ（設計メモ 4.6節）
                MemoEditorTextView(
                    text: $editedText,
                    selectedRange: $selectedRange,
                    prefersNumericKeyboard: $prefersNumericKeyboard,
                    accentColor: accentColor,
                    bridge: bridge
                )
            }
            .padding(.horizontal, 20)
            .safeAreaInset(edge: .bottom) {
                // ツールバーは編集中**ずっと**出す（設計メモ 4.5節）。テンキー中に畳む仕様は
                // **2026-08-12 オーナー確定で廃止**——ページ番号ボタンをトグルにした以上、
                // 押した直後に畳むと「押し間違いをもう一度押して消す」ができない。
                // 条件分岐が無くなったので、帯を出し入れして壊す余地も無くなる
                editorToolbar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左：キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        if hasChanges {
                            showCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                // 右：保存ボタン
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveAndDismiss()
                    }
                }
            }
            .alert("memo.discard.title", isPresented: $showCancelAlert) {
                Button("common.discard", role: .destructive) {
                    dismiss()
                }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("memo.discard.message")
            }
            .interactiveDismissDisabled(hasChanges)
        }
    }
    
    // MARK: - ツールバー（設計メモ 4.5節）

    /// 左から つなぐ｜太字・引用・ページ番号。書式はMarkdown記法を本文に埋め込む方式で、
    /// ボタンは記号を挿入するだけ（独自のリッチテキスト形式を持たない）。
    /// **アイコン＋ラベル**で出し、役割ごとに区切り線で分ける（2026-08-11 オーナー指示）——
    /// 図像だけでは操作の意味が伝わらないため、ラベルは残す。
    /// 「つなぐ」は書籍メモのみ——月メモはT1のスコープ外（`allowsLinks == false`・4.3節）。
    /// キャレットが入っている装飾のボタンは色を変えて光らせる（2026-08-12 オーナー指示・
    /// 記号を隠したぶん、いまどの装飾の中にいるかを画面から読み取れないため）
    private var editorToolbar: some View {
        // 横スクロールはしない。ボタンはラベルの幅に合わせ、余りを均等な間隔に配る——
        // 幅を等分すると、ラベルが短いボタン（太字・引用）の周りだけ隙間が広く見える
        let active = activeFormats
        return HStack(spacing: 0) {
            if allowsLinks {
                toolbarButton(
                    "memo.toolbar.link", icon: "icn_node",
                    isActive: active.link, action: insertLinkBrackets
                )
                toolbarGap
                toolbarDivider
                toolbarGap
            }
            toolbarButton(
                "memo.toolbar.bold", icon: "icon_bold",
                isActive: active.bold, action: wrapSelectionInBold
            )
            toolbarGap
            toolbarButton(
                "memo.toolbar.quote", icon: "icon_quote",
                isActive: active.quote, action: insertQuote
            )
            toolbarGap
            toolbarButton(
                "memo.toolbar.page", icon: "icn_pagenum",
                enabled: canTogglePageMarker,
                isActive: active.page, action: togglePageMarker
            )
            toolbarGap
            toolbarDivider
            toolbarGap
            toolbarButton("memo.toolbar.clear", icon: "icn_clear", action: clearFormatting)
            toolbarGap
            toolbarButton(
                "memo.toolbar.undo",
                icon: "icn_back",
                enabled: bridge.canUndo,
                action: bridge.undo
            )
        }
        // カプセルの丸みが端のボタンを削らないよう、内側の余白は丸みの分だけ広げる。
        // 左は「つなぐ」が縁に近く見えるのでさらに広く（2026-08-11 オーナー指示）
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        // 浮いて見せるので、輪郭と影を持たせる——本文と同じ白の上では素の材質だと境目が消える
        .background(.bar, in: Capsule())
        .overlay(Capsule().stroke(Color(.separator).opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        // キーボードとのあいだに隙間を空ける（2026-08-11 オーナー指示）
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    /// アイコンの表示サイズ。図像がすべて18×18の同じ画布で書き出されているので、
    /// ボタンごとに大きさを振り分けずこの1つで揃える（2026-08-11 オーナー指示）
    private static let toolbarIconSize: CGFloat = 20

    private func toolbarButton(
        _ label: LocalizedStringKey,
        icon: String,
        enabled: Bool = true,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.toolbarIconSize, height: Self.toolbarIconSize)
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // 光らせる色は本文の装飾と同じテーマ色にする——つながりの文字色と揃うので、
            // ボタンと本文のどちらを見ても同じ意味に読める
            .foregroundColor(isActive ? accentColor : .primary)
            .opacity(enabled ? 1 : 0.35)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// ボタンのあいだの間隔。余りを均等に配るので、どの隙間も同じ幅になる
    private var toolbarGap: some View {
        Spacer(minLength: 6)
    }

    /// 役割の区切り。カプセルの内側に収まる高さにする（縁に触ると囲みが割れて見える）
    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 32)
    }

    /// いま選択している範囲。無選択（キャレットのみ）は空範囲、変換できなければ末尾扱い
    private var currentSelectionRange: Range<String.Index> {
        Range(selectedRange, in: editedText) ?? (editedText.endIndex..<editedText.endIndex)
    }

    /// 範囲を置き換え、置き換え開始から `caretOffset` 文字目へキャレットを移す。
    /// 書き換えはテキストビュー経由で行う——文字列を直接差し替えると「ひとつ戻す」の履歴に残らない
    private func replaceRange(_ range: Range<String.Index>, with insertion: String, caretOffset: Int) {
        let startOffset = editedText.distance(from: editedText.startIndex, to: range.lowerBound)
        let target = NSRange(range, in: editedText)

        var updated = editedText
        updated.replaceSubrange(range, with: insertion)
        let caret = updated.index(updated.startIndex, offsetBy: startOffset + caretOffset)
        let caretLocation = NSRange(caret..<caret, in: updated).location

        if bridge.replace(target, with: insertion, caretLocation: caretLocation) { return }
        // テキストビューがまだ無いとき（プレビューなど）は従来どおり文字列を差し替える
        editedText = updated
        selectedRange = NSRange(location: caretLocation, length: 0)
    }

    /// メモ全体から装飾の記号を外す（2026-08-11 オーナー確定）。組み立ては `MemoPlainText`
    private func clearFormatting() {
        let stripped = MemoPlainText.stripped(from: editedText)
        guard stripped != editedText else { return }
        replaceRange(
            editedText.startIndex..<editedText.endIndex,
            with: stripped,
            caretOffset: min(
                editedText.distance(from: editedText.startIndex, to: currentSelectionRange.lowerBound),
                stripped.count
            )
        )
    }

    /// つながりのトグル（組み立ては `MemoFormatToggle`）
    private func insertLinkBrackets() {
        apply(MemoFormatToggle.link(in: editedText, selecting: currentSelectionRange))
    }

    /// 太字のトグル
    private func wrapSelectionInBold() {
        apply(MemoFormatToggle.bold(in: editedText, selecting: currentSelectionRange))
    }

    /// 引用のトグル
    private func insertQuote() {
        apply(MemoFormatToggle.quote(in: editedText, selecting: currentSelectionRange))
    }

    private func apply(_ edit: MemoFormatToggle.Edit) {
        replaceRange(edit.replaced, with: edit.text, caretOffset: edit.caretOffset)
    }

    /// `p.` を挿してキャレットを直後へ（数字はユーザーが打つ）。文字の挿入だけの入力補助。
    /// 続けて数字を打つので、キーボードもテンキーへ切り替える（2026-08-11 オーナー指示）。
    /// ページ番号の中で押したときは外す側に回る（**2026-08-12 オーナー指示**・`MemoFormatToggle`）
    private func togglePageMarker() {
        let range = currentSelectionRange
        guard let edit = MemoFormatToggle.page(in: editedText, selecting: range) else { return }
        let isInsertion = MemoPageMarker.enclosingOutsideLinks(range.lowerBound, in: editedText) == nil
        apply(edit)
        // 外したときはテンキーのままにしない（キャレットが数字から離れる）
        prefersNumericKeyboard = isInsertion
    }

    /// ページ番号の中にいれば外せる。外にいて英数字の直後なら挿せない（解析と同じ境界）
    private var canTogglePageMarker: Bool {
        MemoFormatToggle.page(in: editedText, selecting: currentSelectionRange) != nil
    }

    /// キャレットがいま入っている装飾（判定は `MemoActiveFormats`）。
    /// 範囲を選んでいるときは光らせない——選択の中に装飾の内と外が混ざりうるため
    private var activeFormats: MemoActiveFormats {
        guard selectedRange.length == 0,
              let caret = Range(selectedRange, in: editedText)?.lowerBound
        else { return .none }
        return MemoActiveFormats.at(caret, in: editedText)
    }

    /// 変更があるかチェック。比べるのは保存する形——編集のために足した案内や空行では
    /// 「変更あり」にしない
    private var hasChanges: Bool {
        return savedText != memo
    }

    /// 保存する形。入力されなかった出典ページの行・中身を書かなかった `[[ ]]`・
    /// 編集のために用意した末尾の空行を落とす
    private var savedText: String {
        var text = MemoQuotePage.removingEmptyPageLines(from: editedText)
        text = MemoLinkParser.removingEmptyPairs(from: text)
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }
    
    /// 保存して閉じる。出典ページを入力しなかった引用からは `p.` の行を落とす（入力は任意）。
    /// 編集のために用意した末尾の空行も落とす（メモの中身ではない）
    private func saveAndDismiss() {
        let saved = savedText
        #if DEBUG
        print("💾 [メモモーダル] 保存して閉じる: \"\(saved)\"")
        #endif
        onSave(saved)
        dismiss()
    }
}

#Preview {
    @Previewable @State var memo = "サンプルメモ"
    
    MemoEditorView(memo: $memo) { _ in }
}
