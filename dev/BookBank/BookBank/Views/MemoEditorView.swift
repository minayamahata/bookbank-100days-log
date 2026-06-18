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
    @FocusState private var isFocused: Bool
    
    let onSave: (String) -> Void
    
    init(memo: Binding<String>, onSave: @escaping (String) -> Void) {
        self._memo = memo
        self._editedText = State(initialValue: memo.wrappedValue)
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
                TextEditor(text: $editedText)
                    .font(.body)
                    .padding(4)
                    .focused($isFocused)
            }
            .padding(.horizontal, 20)
            .navigationTitle("book.memo")
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
