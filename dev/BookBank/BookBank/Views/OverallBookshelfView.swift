//
//  OverallBookshelfView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

/// 総合口座の本棚ビュー（全口座の本を表示）
struct OverallBookshelfView: View {
    @Environment(\.modelContext) private var context
    
    // すべての本を取得（登録日降順）
    @Query(sort: \UserBook.registeredAt, order: .reverse) private var allBooks: [UserBook]
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            if allBooks.isEmpty {
                // 空状態
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("本棚はまだ空です")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("本を登録して本棚を埋めましょう")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // 本棚グリッド
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(allBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2) // 左右の余白を2pxに
                .padding(.bottom, 100) // タブバー分の余白を確実に確保
            }
        }
        .ignoresSafeArea(edges: .bottom) // タブバーの下まで表示
        .navigationTitle("総合口座")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    // サンプル本を追加
    for i in 1...10 {
        let book = UserBook(
            title: "サンプル本 \(i)",
            author: "著者\(i)",
            price: 1500,
            passbook: passbook
        )
        if i % 3 == 0 {
            book.isFavorite = true
        }
        container.mainContext.insert(book)
    }
    
    return OverallBookshelfView()
        .modelContainer(container)
}
