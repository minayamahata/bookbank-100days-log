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
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool
    
    let title: LocalizedStringKey
    /// 入力サジェストの候補元。`nil` ならサジェストしない（月メモはT1のスコープ外＝設計メモ 4.3節）
    let linkIndex: MemoLinkIndex?
    let onSave: (String) -> Void
    
    init(
        memo: Binding<String>,
        title: LocalizedStringKey = "book.memo",
        linkIndex: MemoLinkIndex? = nil,
        onSave: @escaping (String) -> Void
    ) {
        self._memo = memo
        self._editedText = State(initialValue: memo.wrappedValue)
        self.title = title
        self.linkIndex = linkIndex
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
                
                // TextEditor
                TextEditor(text: $editedText, selection: $selection)
                    .font(.body)
                    .padding(4)
                    .focused($isFocused)
            }
            .padding(.horizontal, 20)
            .safeAreaInset(edge: .bottom) {
                linkSuggestionRow
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
            .onAppear {
                // 画面表示時に自動フォーカス
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
        }
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
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return range.isEmpty ? range.lowerBound : nil
        default:
            return nil
        }
    }

    /// 入力途中のつながりを候補で置き換える（キャレット直後の `]]` も範囲に含まれるので、
    /// ツールバー挿入直後の `[[]]` も丸ごと差し替わる）。末尾の空白は続きを書きやすくするため
    private func complete(with link: MemoLinkIndex.Link) {
        guard let draft = currentDraftLink else { return }
        let insertion = "[[\(link.display)]] "
        // 置き換えで既存の String.Index は無効になるため、先に開始位置を数で取る
        let offset = editedText.distance(from: editedText.startIndex, to: draft.range.lowerBound)
        editedText.replaceSubrange(draft.range, with: insertion)
        let caret = editedText.index(editedText.startIndex, offsetBy: offset + insertion.count)
        selection = TextSelection(insertionPoint: caret)
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
