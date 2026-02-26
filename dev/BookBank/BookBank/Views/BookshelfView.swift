//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI
import SwiftData

/// 本棚画面
struct BookshelfView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座
    let passbook: Passbook
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    // MARK: - State
    
    /// お気に入りフィルター
    @State private var showFavoritesOnly = false
    
    /// メモありフィルター
    @State private var showWithMemoOnly = false
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        var books = allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID
        }
        
        // お気に入りフィルター
        if showFavoritesOnly {
            books = books.filter { $0.isFavorite }
        }
        
        // メモありフィルター
        if showWithMemoOnly {
            books = books.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }
        }
        
        return books
    }
    
    /// カスタム口座のリスト
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// この口座のテーマカラー
    private var themeColor: Color {
        PassbookColor.color(for: passbook, in: customPassbooks)
    }
    
    /// テーマカラーが黒（index 0）かどうか
    private var isBlackTheme: Bool {
        if let colorIndex = passbook.colorIndex {
            return colorIndex == 0
        }
        if let index = customPassbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return index == 0
        }
        return false
    }
    
    /// この口座の全書籍数
    private var allBooksCount: Int {
        allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID
        }.count
    }
    
    /// お気に入りの書籍数
    private var favoriteCount: Int {
        allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID && book.isFavorite
        }.count
    }
    
    /// メモありの書籍数
    private var memoCount: Int {
        allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID &&
            book.memo != nil && !(book.memo?.isEmpty ?? true)
        }.count
    }
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    // MARK: - Initialization
    
    init(passbook: Passbook) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // フィルターセクション
                    filterSection
                    
                    // 本棚グリッド
                    gridContent
                }
            }
        }
        .id(passbook.persistentModelID) // 口座が変わったら強制的にViewを再生成
        .background(ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme))
        .navigationTitle("本棚")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        HStack(spacing: 8) {
            // All ボタン
            Button(action: {
                showFavoritesOnly = false
                showWithMemoOnly = false
            }) {
                HStack(spacing: 6) {
                    Text("すべて")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(allBooksCount)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                .foregroundColor(!showFavoritesOnly && !showWithMemoOnly ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(!showFavoritesOnly && !showWithMemoOnly ? Color.white : Color.white.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Like ボタン
            Button(action: {
                showFavoritesOnly.toggle()
                if showFavoritesOnly {
                    showWithMemoOnly = false
                }
            }) {
                HStack(spacing: 6) {
                    Text("お気に入り")
                        .font(.system(size: 11, weight: .medium))
                    if favoriteCount > 0 {
                        Text("\(favoriteCount)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .foregroundColor(showFavoritesOnly ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(showFavoritesOnly ? Color.white : Color.white.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Memo ボタン
            Button(action: {
                showWithMemoOnly.toggle()
                if showWithMemoOnly {
                    showFavoritesOnly = false
                }
            }) {
                HStack(spacing: 6) {
                    Text("メモ")
                        .font(.system(size: 11, weight: .medium))
                    if memoCount > 0 {
                        Text("\(memoCount)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .foregroundColor(showWithMemoOnly ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(showWithMemoOnly ? Color.white : Color.white.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
                VStack(spacing: 8) {
                    Text("最近どんな本を読みましたか？")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(userBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .animation(nil, value: userBooks.count)
            }
        }
        .padding(.bottom, 100)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return NavigationStack {
        BookshelfView(passbook: passbook)
    }
    .modelContainer(container)
}
