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
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
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
        .background(themeColor.opacity(0.1).ignoresSafeArea())
        .navigationTitle("本棚")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        HStack(spacing: 8) {
            // お気に入りフィルター
            Button(action: {
                showFavoritesOnly.toggle()
            }) {
                HStack(spacing: 6) {
                    Image("icon-favorite")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("お気に入り")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(showFavoritesOnly ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(showFavoritesOnly ? themeColor : Color.white)
                )
            }
            
            // メモありフィルター
            Button(action: {
                showWithMemoOnly.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .medium))
                    Text("メモあり")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(showWithMemoOnly ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(showWithMemoOnly ? themeColor : Color.white)
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
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
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(userBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
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
