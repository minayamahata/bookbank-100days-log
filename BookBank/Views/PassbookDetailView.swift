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
    
    // MARK: - State
    
    /// 本の検索画面の表示フラグ
    @State private var isShowingBookSearch = false
    
    // MARK: - SwiftData Query
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        allUserBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 上部：口座情報
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
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            
            // 中央：書籍リスト
            if userBooks.isEmpty {
                // 書籍が0件の場合
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("まだ本が登録されていません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // 書籍一覧を表示
                List(userBooks) { book in
                    VStack(alignment: .leading, spacing: 8) {
                        // タイトル
                        Text(book.title)
                            .font(.headline)
                        
                        // 著者
                        if !book.displayAuthor.isEmpty {
                            Text(book.displayAuthor)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // 価格と登録日
                        HStack {
                            if let priceText = book.displayPrice {
                                Text(priceText)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            Text(book.registeredAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("通帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 本を検索・追加ボタン
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isShowingBookSearch = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingBookSearch) {
            BookSearchView(passbook: passbook)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PassbookDetailView(passbook: Passbook.createOverall())
    }
    .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
