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
                    Text("メモを入力...")
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
            .navigationTitle("メモ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左：キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasChanges {
                            showCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                // 右：完了ボタン
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("変更を破棄しますか？", isPresented: $showCancelAlert) {
                Button("破棄", role: .destructive) {
                    dismiss()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("編集中の内容は保存されません。")
            }
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
        print("💾 [メモモーダル] 保存して閉じる: \"\(editedText)\"")
        onSave(editedText)
        dismiss()
    }
}

#Preview {
    @Previewable @State var memo = "サンプルメモ"
    
    MemoEditorView(memo: $memo) { newMemo in
        print("保存: \(newMemo)")
    }
}
