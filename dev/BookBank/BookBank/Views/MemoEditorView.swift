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
    
    let title: LocalizedStringKey
    /// 入力サジェストの候補元。`nil` ならサジェストしない（月メモはT1のスコープ外＝設計メモ 4.3節）
    let linkIndex: MemoLinkIndex?
    /// つながりの着色とページ番号バッジに使う色（黒テーマ＋ダーク時の退避は呼び出し側の責務）
    let accentColor: Color
    let onSave: (String) -> Void
    
    init(
        memo: Binding<String>,
        title: LocalizedStringKey = "book.memo",
        linkIndex: MemoLinkIndex? = nil,
        accentColor: Color = .accentColor,
        onSave: @escaping (String) -> Void
    ) {
        self._memo = memo
        self._editedText = State(initialValue: memo.wrappedValue)
        self.title = title
        self.linkIndex = linkIndex
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
                    accentColor: accentColor
                )
            }
            .padding(.horizontal, 20)
            .safeAreaInset(edge: .bottom) {
                // ツールバーは常設、サジェストは候補があるときだけその上に出る（設計メモ 4.5節）
                VStack(spacing: 0) {
                    linkSuggestionRow
                    editorToolbar
                }
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

    /// 左から つなぐ・太字・引用・ページ番号。書式はMarkdown記法を本文に埋め込む方式で、
    /// ボタンは記号を挿入するだけ（独自のリッチテキスト形式を持たない）。
    /// アイコンではなく**テキストラベル**で出す——リンクの図像は外部リンク（https://）に
    /// 見えるなど、図像では操作の意味が伝わらないため（2026-08-11 オーナー指示）。
    /// 「つなぐ」は書籍メモのみ——月メモは候補元が無い（`linkIndex == nil`・4.3節のスコープ）
    private var editorToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if linkIndex != nil {
                    toolbarButton("memo.toolbar.link", action: insertLinkBrackets)
                }
                toolbarButton("memo.toolbar.bold", action: wrapSelectionInBold)
                toolbarButton("memo.toolbar.quote", action: insertQuote)
                toolbarButton("memo.toolbar.page", action: insertPageMarker)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func toolbarButton(
        _ label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// いま選択している範囲。無選択（キャレットのみ）は空範囲、変換できなければ末尾扱い
    private var currentSelectionRange: Range<String.Index> {
        Range(selectedRange, in: editedText) ?? (editedText.endIndex..<editedText.endIndex)
    }

    /// 範囲を置き換え、置き換え開始から `caretOffset` 文字目へキャレットを移す
    private func replaceRange(_ range: Range<String.Index>, with insertion: String, caretOffset: Int) {
        let startOffset = editedText.distance(from: editedText.startIndex, to: range.lowerBound)
        editedText.replaceSubrange(range, with: insertion)
        let caret = editedText.index(editedText.startIndex, offsetBy: startOffset + caretOffset)
        selectedRange = NSRange(caret..<caret, in: editedText)
    }

    /// 選択中ならそれを `[[ ]]` で囲み、無選択なら空の括弧を挿す。
    /// どちらもキャレットは `]]` の手前に置くので、サジェスト（下記）がそのまま出る
    private func insertLinkBrackets() {
        let range = currentSelectionRange
        let selected = String(editedText[range])
        replaceRange(range, with: "[[\(selected)]]", caretOffset: 2 + selected.count)
    }

    /// 選択中ならそれを `**` で囲んで直後へ、無選択なら `****` を挿してキャレットを中へ
    private func wrapSelectionInBold() {
        let range = currentSelectionRange
        let selected = String(editedText[range])
        let caretOffset = selected.isEmpty ? 2 : selected.count + 4
        replaceRange(range, with: "**\(selected)**", caretOffset: caretOffset)
    }

    /// 行頭に `> ` を入れる（表示側が解釈するのはこの形だけ＝設計メモ 4.6節）。
    /// 引用は行単位の仕組みなので、行の一部を選んだときは**その部分だけを独立した行に切り出す**——
    /// 選んでいない前後の文字まで囲みに入るのを避けるため（2026-08-11 オーナー指示）
    private func insertQuote() {
        let range = currentSelectionRange
        let selected = String(editedText[range])

        guard !selected.isEmpty else {
            let caret = range.lowerBound
            let lineStart = editedText[..<caret].lastIndex(where: \.isNewline)
                .map { editedText.index(after: $0) } ?? editedText.startIndex
            let caretDistance = editedText.distance(from: lineStart, to: caret)
            replaceRange(lineStart..<lineStart, with: "> ", caretOffset: caretDistance + 2)
            return
        }

        // 複数行を選んだ場合は各行に付ける（連続する引用行はひとつの囲みにまとまる）
        let quoted = selected.components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
        // 選択が行の途中から始まる／途中で終わるときだけ改行で行を切る（空行を増やさない）
        let opensLine = range.lowerBound == editedText.startIndex
            || editedText[editedText.index(before: range.lowerBound)].isNewline
        let closesLine = range.upperBound == editedText.endIndex
            || editedText[range.upperBound].isNewline
        let insertion = (opensLine ? "" : "\n") + quoted + (closesLine ? "" : "\n")

        replaceRange(
            range,
            with: insertion,
            caretOffset: (opensLine ? 0 : 1) + quoted.count
        )
    }

    /// `p.` を挿してキャレットを直後へ（数字はユーザーが打つ）。文字の挿入だけの入力補助。
    /// 続けて数字を打つので、キーボードも数字が並んだものへ切り替える（2026-08-11 オーナー指示）
    private func insertPageMarker() {
        let range = currentSelectionRange
        replaceRange(range, with: "p.", caretOffset: 2)
        prefersNumericKeyboard = true
    }

    // MARK: - つながりの入力サジェスト（設計メモ 4.1節）

    /// `[[` を打った瞬間から既存のつながりを候補に出す。表記ゆれの発生自体を抑えるのが狙いで、
    /// 候補が無いときは行そのものを出さない（つながりを使わない人の編集画面は現状のまま）
    @ViewBuilder
    private var linkSuggestionRow: some View {
        if !linkSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(linkSuggestions, id: \.key) { link in
                        Button {
                            complete(with: link)
                        } label: {
                            Text(verbatim: link.display)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private var linkSuggestions: [MemoLinkIndex.Link] {
        guard let linkIndex, let draft = currentDraftLink else { return [] }
        let alreadyWritten = Set(MemoLinkParser.parse(editedText).map(\.key))
        return Array(
            linkIndex.suggestions(matching: draft.partialKey, excluding: alreadyWritten).prefix(8)
        )
    }

    private var currentDraftLink: MemoDraftLink? {
        guard let caret = caretIndex else { return nil }
        return MemoLinkParser.draftLink(in: editedText, before: caret)
    }

    /// キャレット位置。範囲を選択している間はサジェストを出さない
    private var caretIndex: String.Index? {
        guard selectedRange.length == 0 else { return nil }
        return Range(selectedRange, in: editedText)?.lowerBound
    }

    /// 入力途中のつながりを候補で置き換える（キャレット直後の `]]` も範囲に含まれるので、
    /// ツールバー挿入直後の `[[]]` も丸ごと差し替わる）。末尾の空白は続きを書きやすくするため
    private func complete(with link: MemoLinkIndex.Link) {
        guard let draft = currentDraftLink else { return }
        replaceRange(draft.range, with: "[[\(link.display)]] ", caretOffset: link.display.count + 5)
    }

    /// 変更があるかチェック
    private var hasChanges: Bool {
        return editedText != memo
    }
    
    /// 保存して閉じる
    private func saveAndDismiss() {
        #if DEBUG
        print("💾 [メモモーダル] 保存して閉じる: \"\(editedText)\"")
        #endif
        onSave(editedText)
        dismiss()
    }
}

#Preview {
    @Previewable @State var memo = "サンプルメモ"
    
    MemoEditorView(memo: $memo) { _ in }
}
