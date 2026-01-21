//
//  PassbookDetailView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/14.
//

import SwiftUI
import SwiftData

/// 通帳画面
/// 選択した口座の詳細と、登録されている書籍の一覧を表示
struct PassbookDetailView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nilの場合は総合口座）
    let passbook: Passbook?
    
    /// 総合口座モードかどうか
    let isOverall: Bool
    
    // MARK: - State
    
    /// 編集モーダルの表示フラグ
    @State private var showEditPassbook = false
    
    /// 編集中の口座名
    @State private var editingName = ""
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// 画面を閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得（総合口座の計算用）
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        if isOverall {
            // 総合口座: すべての本を表示
            return allUserBooks
        } else if let passbook = passbook {
            // カスタム口座: その口座の本のみ
            return allUserBooks.filter { book in
                book.passbook?.persistentModelID == passbook.persistentModelID
            }
        } else {
            return []
        }
    }
    
    /// 表示用の口座名
    private var displayName: String {
        isOverall ? "総合口座" : (passbook?.name ?? "")
    }
    
    /// 合計金額（総合口座の場合はすべての口座の合計）
    private var totalValue: Int {
        if isOverall {
            return allPassbooks.filter { $0.type == .custom && $0.isActive }
                .reduce(0) { $0 + $1.totalValue }
        } else {
            return passbook?.totalValue ?? 0
        }
    }
    
    /// 登録書籍数
    private var bookCount: Int {
        if isOverall {
            return allPassbooks.filter { $0.type == .custom && $0.isActive }
                .reduce(0) { $0 + $1.bookCount }
        } else {
            return passbook?.bookCount ?? 0
        }
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook?, isOverall: Bool = false) {
        self.passbook = passbook
        self.isOverall = isOverall
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            // 口座情報
            Section {
                VStack(spacing: 8) {
                    Text("¥\(totalValue.formatted())")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("登録書籍: \(bookCount)冊")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // 書籍リスト
            Section {
                if userBooks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("まだ本が登録されていません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(userBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDate(book.registeredAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(book.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    
                                    if !book.displayAuthor.isEmpty {
                                        Text(book.displayAuthor)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if let priceText = book.displayPrice {
                                    Text(priceText)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 総合口座以外は編集ボタンを表示
            if !isOverall {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        editingName = passbook?.name ?? ""
                        showEditPassbook = true
                    }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditPassbook) {
            EditPassbookSheet(
                passbookName: $editingName,
                passbook: passbook,
                bookCount: bookCount,
                onSave: {
                    savePassbookName()
                },
                onDelete: {
                    deletePassbook()
                }
            )
        }
    }
    
    // MARK: - Actions
    
    /// 口座名を保存
    private func savePassbookName() {
        guard let passbook = passbook else { return }
        
        // 空白のみの名前は許可しない
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        passbook.name = trimmedName
        passbook.updatedAt = Date()
        
        do {
            try context.save()
            print("✅ 口座名を更新しました: \(trimmedName)")
        } catch {
            print("❌ 口座名の更新に失敗しました: \(error)")
        }
    }
    
    /// 口座を削除
    private func deletePassbook() {
        guard let passbook = passbook else { return }
        
        let passbookName = passbook.name
        let booksCount = passbook.userBooks.count
        
        // 口座を削除（関連する本も cascade で削除される）
        context.delete(passbook)
        
        do {
            try context.save()
            print("✅ 口座「\(passbookName)」を削除しました（\(booksCount)冊の本も削除）")
            // 画面を閉じて口座一覧に戻る
            dismiss()
        } catch {
            print("❌ 口座の削除に失敗しました: \(error)")
        }
    }
    
    /// 日付をYYYY.MM.DD形式でフォーマット
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

// MARK: - EditPassbookSheet

/// 口座名編集シート
struct EditPassbookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var passbookName: String
    let passbook: Passbook?
    let bookCount: Int
    let onSave: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("口座名", text: $passbookName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("口座名")
                } footer: {
                    Text("この口座の名前を変更できます")
                }
                
                // 削除セクション
                Section {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("この口座を削除")
                            Spacer()
                        }
                    }
                } footer: {
                    if bookCount > 0 {
                        Text("この口座に登録されている\(bookCount)冊の本も削除されます")
                            .foregroundColor(.red)
                    } else {
                        Text("この口座は空です")
                    }
                }
            }
            .navigationTitle("口座を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                    .disabled(passbookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("口座を削除しますか？", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                if bookCount > 0 {
                    Text("「\(passbookName)」を削除すると、この口座に登録されている\(bookCount)冊の本も削除されます。\n\nこの操作は取り消せません。")
                } else {
                    Text("「\(passbookName)」を削除してもよろしいですか？\n\nこの操作は取り消せません。")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画口座", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return NavigationStack {
        PassbookDetailView(passbook: passbook, isOverall: false)
    }
    .modelContainer(container)
}
