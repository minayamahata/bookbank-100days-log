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
    
    /// 登録先の口座（初期値）
    let passbook: Passbook
    
    /// 口座選択を許可するかどうか
    let allowPassbookChange: Bool
    
    /// 保存成功時のコールバック（親画面を閉じるため）
    var onSave: (() -> Void)?
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// カスタム口座のみ取得
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    // MARK: - Form State
    
    /// 選択中の口座
    @State private var selectedPassbook: Passbook?
    
    /// 書籍タイトル（必須）
    @State private var title: String = ""
    
    /// 著者名（任意）
    @State private var author: String = ""
    
    /// 価格（任意）
    @State private var priceText: String = ""
    
    /// キーボードフォーカス
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, author, price
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook, allowPassbookChange: Bool = false, onSave: (() -> Void)? = nil) {
        self.passbook = passbook
        self.allowPassbookChange = allowPassbookChange
        self.onSave = onSave
        _selectedPassbook = State(initialValue: passbook)
    }
    
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
                // 口座選択セクション（allowPassbookChangeがtrueの場合のみ表示）
                if allowPassbookChange {
                    Section {
                        Picker("口座", selection: $selectedPassbook) {
                            ForEach(customPassbooks) { passbook in
                                Text(passbook.name)
                                    .foregroundColor(.primary)
                                    .tag(passbook as Passbook?)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.primary)
                    } header: {
                        Text("登録先の口座")
                            .font(.footnote)
                    }
                }
                
                // 基本情報セクション
                Section {
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
                            .focused($focusedField, equals: .title)
                    }
                    
                    // 著者名（任意）
                    TextField("著者名", text: $author)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .author)
                    
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
                                .focused($focusedField, equals: .price)
                        }
                    }
                } header: {
                    Text("基本情報")
                        .font(.footnote)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle("本の登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
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
        guard let price = Int(priceText),
              let targetPassbook = selectedPassbook else {
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
            memo: nil,
            isFavorite: false,
            passbook: targetPassbook
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画口座", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return AddBookView(passbook: passbook)
        .modelContainer(container)
}
