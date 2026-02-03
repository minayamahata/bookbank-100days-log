//
//  BookSelectorView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData

/// 本選択画面（読了リストに本を追加するため）
struct BookSelectorView: View {
    
    // MARK: - Properties
    
    /// 追加先の読了リスト
    @Bindable var readingList: ReadingList
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - SwiftData Query
    
    /// すべての本を取得（登録日順）
    @Query(sort: \UserBook.registeredAt, order: .reverse) private var allBooks: [UserBook]
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    // MARK: - State
    
    /// 選択された本のID
    @State private var selectedBookIDs: Set<PersistentIdentifier> = []
    
    /// 現在選択中の口座インデックス
    @State private var selectedPassbookIndex: Int = 0
    
    /// 既にリストに含まれている本のID
    private var existingBookIDs: Set<PersistentIdentifier> {
        Set(readingList.books.map { $0.persistentModelID })
    }
    
    /// アクティブな口座のみ
    private var activePassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// 指定した口座の本を取得
    private func books(for passbook: Passbook) -> [UserBook] {
        allBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // スティッキーヘッダー
                stickyHeader
                
                if allBooks.isEmpty {
                    emptyStateView
                } else if activePassbooks.isEmpty {
                    emptyStateView
                } else {
                    // 口座タブ
                    passbookTabBar
                    
                    // 口座別スワイプビュー
                    GeometryReader { geometry in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(activePassbooks.enumerated()), id: \.element.id) { index, passbook in
                                    bookListView(for: passbook)
                                        .frame(width: geometry.size.width - 40)
                                        .id(index)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 20)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: Binding(
                            get: { selectedPassbookIndex },
                            set: { if let newValue = $0 { selectedPassbookIndex = newValue } }
                        ))
                    }
                }
            }
            .background(Color.appGroupedBackground)
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Subviews
    
    /// スティッキーヘッダー
    private var stickyHeader: some View {
        HStack {
            // キャンセルボタン
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            
            Spacer()
            
            // リスト名
            VStack(spacing: 2) {
                Text("追加先")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(readingList.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 追加ボタン
            Button(action: {
                addSelectedBooks()
            }) {
                Text("追加")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selectedBookIDs.isEmpty ? .secondary : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedBookIDs.isEmpty ? Color.secondary.opacity(0.15) : Color.blue)
                    )
            }
            .disabled(selectedBookIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    /// 口座タブバー
    private var passbookTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(activePassbooks.enumerated()), id: \.element.id) { index, passbook in
                        let bookCount = books(for: passbook).count
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPassbookIndex = index
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(passbook.name)
                                    .font(.subheadline)
                                Text("(\(bookCount))")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedPassbookIndex == index ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedPassbookIndex == index ? Color.primary.opacity(0.1) : Color.clear)
                            )
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedPassbookIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(Color.appGroupedBackground)
    }
    
    /// 本のリストビュー（口座ごと）
    private func bookListView(for passbook: Passbook) -> some View {
        let passbookBooks = books(for: passbook)
        
        return ScrollView {
            LazyVStack(spacing: 0) {
                // 選択状態
                HStack {
                    Text("\(selectedBookIDs.count)冊選択中")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                
                // 本のリスト
                ForEach(passbookBooks) { book in
                    selectableBookRow(book: book)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appCardBackground)
            )
            .padding(.bottom, 100)
        }
    }
    
    /// 選択可能な本の行
    private func selectableBookRow(book: UserBook) -> some View {
        let isAlreadyInList = existingBookIDs.contains(book.persistentModelID)
        let isSelected = selectedBookIDs.contains(book.persistentModelID)
        
        return Button(action: {
            if isAlreadyInList { return }
            
            if isSelected {
                selectedBookIDs.remove(book.persistentModelID)
            } else {
                selectedBookIDs.insert(book.persistentModelID)
            }
        }) {
            HStack(spacing: 12) {
                // 本の表紙
                if let imageURL = book.imageURL,
                   let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .id(imageURL)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 75)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                }
                
                // 本の情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if !book.displayAuthor.isEmpty {
                        Text(book.displayAuthor)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // 登録日
                    Text(formatDate(book.registeredAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 選択状態アイコン
                if isAlreadyInList {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isAlreadyInList ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyInList)
    }
    
    /// 空状態ビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("本棚が空です")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("先に本を登録してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func addSelectedBooks() {
        let booksToAdd = allBooks.filter { selectedBookIDs.contains($0.persistentModelID) }
        
        for book in booksToAdd {
            if !readingList.books.contains(where: { $0.persistentModelID == book.persistentModelID }) {
                readingList.books.append(book)
            }
        }
        
        readingList.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to add books to reading list: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ReadingList.self, UserBook.self, Passbook.self, configurations: config)
    
    let list = ReadingList(title: "2024年ベスト")
    container.mainContext.insert(list)
    
    return BookSelectorView(readingList: list)
        .modelContainer(container)
}
