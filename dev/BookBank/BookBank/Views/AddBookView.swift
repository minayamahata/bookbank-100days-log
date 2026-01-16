//
//  AddBookView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import SwiftUI
import SwiftData

/// 本の登録画面
/// モーダルで表示され、手動で書籍情報を入力して登録する
struct AddBookView: View {
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// 登録先の口座
    let passbook: Passbook
    
    /// 保存成功時のコールバック（親画面を閉じるため）
    var onSave: (() -> Void)?
    
    // MARK: - Form State
    
    /// 書籍タイトル（必須）
    @State private var title: String = ""
    
    /// 著者名（任意）
    @State private var author: String = ""
    
    /// 価格（任意）
    @State private var priceText: String = ""
    
    /// メモ（任意）
    @State private var memo: String = ""
    
    /// お気に入りフラグ
    @State private var isFavorite: Bool = false
    
    // MARK: - Validation
    
    /// 保存ボタンが有効かどうか（タイトルと金額が必須）
    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasValidPrice = Int(priceText) != nil && !priceText.isEmpty
        return hasTitle && hasValidPrice
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本情報セクション
                Section(header: Text("基本情報")) {
                    // タイトル（必須）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("タイトル")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        TextField("タイトルを入力", text: $title)
                            .autocorrectionDisabled()
                    }
                    
                    // 著者名（任意）
                    TextField("著者名", text: $author)
                        .autocorrectionDisabled()
                    
                    // 価格（必須）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("価格")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack {
                            Text("¥")
                                .foregroundColor(.secondary)
                            TextField("価格を入力（半角数字）", text: $priceText)
                                .keyboardType(.numberPad)
                        }
                    }
                }
                
                // メモセクション
                Section(header: Text("メモ")) {
                    TextEditor(text: $memo)
                        .frame(minHeight: 100)
                }
                
                // その他セクション
                Section(header: Text("その他")) {
                    Toggle("お気に入り", isOn: $isFavorite)
                }
            }
            .navigationTitle("本の登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                // 保存ボタン
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveBook()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// 本を保存する
    private func saveBook() {
        // 価格の数値変換（必須なのでアンラップ）
        guard let price = Int(priceText) else {
            return
        }
        
        // UserBookインスタンスを作成
        let newBook = UserBook(
            title: title.trimmingCharacters(in: .whitespaces),
            author: author.isEmpty ? nil : author.trimmingCharacters(in: .whitespaces),
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            price: price,
            imageURL: nil,
            source: .manual,
            memo: memo.isEmpty ? nil : memo.trimmingCharacters(in: .whitespaces),
            isFavorite: isFavorite,
            passbook: passbook
        )
        
        // SwiftDataに保存
        context.insert(newBook)
        
        do {
            try context.save()
            // 保存成功後にモーダルを閉じる
            dismiss()
            // 親画面（検索画面）も閉じる
            onSave?()
        } catch {
            // エラーハンドリング（現時点ではコンソール出力のみ）
            print("Error saving book: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    AddBookView(passbook: Passbook.createOverall())
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
