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
    
    /// 表示対象の口座
    let passbook: Passbook
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    // MARK: - State
    
    // (削除: 検索画面の表示フラグは不要)
    
    // MARK: - SwiftData Query
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID
        }
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            // 口座情報
            Section {
                VStack(spacing: 8) {
                    Text(passbook.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("¥\(passbook.totalValue.formatted())")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("登録書籍: \(passbook.bookCount)冊")
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
    }
    
    // MARK: - Actions
    
    /// 日付をYYYY.MM.DD形式でフォーマット
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PassbookDetailView(passbook: Passbook.createOverall())
    }
    .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
