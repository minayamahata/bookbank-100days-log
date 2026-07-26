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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRepositories.self) private var repos
    
    // MARK: - Repository Streams / State

    /// すべての本（リポジトリストリーム・登録日降順）。
    /// 初回yield前は同期スナップショットで補い、空状態UIが1フレーム瞬くのを防ぐ
    @State private var loadedBooks: [BookDTO]?
    private var allBooks: [BookDTO] { loadedBooks ?? repos.books.latestSnapshot }

    /// すべての口座（リポジトリストリーム）
    @State private var passbooks: [PassbookDTO] = []

    // MARK: - State

    /// 選択された本のID（uuid・設計メモ 5.4節）
    @State private var selectedBookIDs: Set<String> = []

    /// 現在選択中の口座インデックス
    @State private var selectedPassbookIndex: Int = 0

    /// 既にリストに含まれている本のID
    private var existingBookIDs: Set<String> {
        Set(readingList.books.map { $0.uuid })
    }

    /// アクティブな口座のみ
    private var activePassbooks: [PassbookDTO] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }

    /// 指定した口座の本を取得
    private func books(for passbook: PassbookDTO) -> [BookDTO] {
        allBooks.filter { $0.passbookId == passbook.id }
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
            .background(Color.clear)
            .navigationBarHidden(true)
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    passbooks = value
                }
            }
            .task {
                for await value in repos.books.observeBooks() {
                    loadedBooks = value
                }
            }
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
                Text("selector.destination")
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
                Text("common.add")
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
                                Text(L10n.format("common.book_count_paren", Int64(bookCount)))
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
        .background(Color.clear)
    }
    
    /// 本のリストビュー（口座ごと）
    private func bookListView(for passbook: PassbookDTO) -> some View {
        let passbookBooks = books(for: passbook)
        let themeColor = PassbookColor.color(for: passbook.colorIndex ?? 0)
        
        return ScrollView {
            LazyVStack(spacing: 6) {
                // 選択状態
                HStack {
                    Text(L10n.format("selector.selected_count", Int64(selectedBookIDs.count)))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 4)
                
                // 本のリスト
                ForEach(passbookBooks) { book in
                    selectableBookRow(book: book, themeColor: themeColor)
                }
            }
            .padding(.bottom, 100)
        }
    }
    
    /// 選択可能な本の行
    private func selectableBookRow(book: BookDTO, themeColor: Color) -> some View {
        let isAlreadyInList = existingBookIDs.contains(book.id)
        let isSelected = selectedBookIDs.contains(book.id)

        return Button(action: {
            if isAlreadyInList { return }

            if isSelected {
                selectedBookIDs.remove(book.id)
            } else {
                selectedBookIDs.insert(book.id)
            }
        }) {
            HStack(spacing: 12) {
                // 本の表紙
                LocalCoverImage(book: book) { coverImage in
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 47, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else if let imageURL = book.coverImageURL,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url, width: 47, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 47, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .overlay {
                                Image(systemName: "book.closed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                
                // 本の情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDate(book.registeredAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text(book.title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if !book.displayAuthor.isEmpty {
                        Text(book.displayAuthor)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 選択状態アイコン
                if isAlreadyInList {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.gray)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.blue)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : themeColor.opacity(0.1))
            )
            .contentShape(Rectangle())
            .opacity(isAlreadyInList ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyInList)
    }
    
    /// 空状態ビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("selector.recent_prompt")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func addSelectedBooks() {
        // ReadingList.books（SwiftDataリレーション）への追記はステップ5まで @Model が要る。
        // 表示順（allBooks の正準ソート順）を保ったまま uuid → @Model を解決する。
        let idsToAdd = allBooks.map(\.id).filter { selectedBookIDs.contains($0) }
        let booksToAdd = BookModelLookup.fetch(ids: idsToAdd, context: context)
        let currentOrdered = readingList.orderedBooks

        for book in booksToAdd {
            if !readingList.books.contains(where: { $0.uuid == book.uuid }) {
                readingList.books.append(book)
            }
        }

        let newOrder = currentOrdered + booksToAdd.filter { newBook in
            !currentOrdered.contains(where: { $0.uuid == newBook.uuid })
        }
        readingList.saveBookOrder(newOrder)
        readingList.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            #if DEBUG
            print("❌ Failed to add books to reading list: \(error)")
            #endif
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        AppDateFormat.display(date)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ReadingList.self, UserBook.self, Passbook.self, configurations: config)
    
    let list = ReadingList(title: "2024年ベスト")
    container.mainContext.insert(list)
    
    return BookSelectorView(readingList: list)
        .modelContainer(container)
        .environment(PreviewSupport.repositories)
}
