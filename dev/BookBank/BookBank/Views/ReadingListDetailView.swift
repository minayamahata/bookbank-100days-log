//
//  ReadingListDetailView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData

/// 読了リスト詳細画面
struct ReadingListDetailView: View {
    
    // MARK: - Properties
    
    /// 表示対象のリスト
    @Bindable var readingList: ReadingList
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var showBookSelector = false
    @State private var showEditSheet = false
    @State private var bookToRemove: UserBook?
    @State private var showRemoveAlert = false
    @State private var selectedBookIndex: Int?
    @State private var showBookCarousel = false
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // メインコンテンツ
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // リスト情報セクション
                        listInfoSection
                        
                        // コンテンツカード
                        VStack(spacing: 0) {
                            // ヘッダー
                            HStack {
                                Text("\(readingList.bookCount)冊")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // 本を追加ボタン
                                Button(action: {
                                    showBookSelector = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("本を追加")
                                    }
                                    .font(.footnote)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 28)
                            .padding(.bottom, 12)
                            
                            // 本棚グリッド
                            gridContent
                        }
                        .frame(minHeight: geometry.size.height)
                        .background(Color(.systemBackground))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 40,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 40
                            )
                        )
                    }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            
            // カルーセルオーバーレイ
            if showBookCarousel, let index = selectedBookIndex {
                BookCarouselView(
                    books: readingList.books,
                    initialIndex: index,
                    readingList: readingList,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showBookCarousel = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .navigationTitle(readingList.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showEditSheet = true
                }) {
                    Text("編集")
                        .font(.footnote)
                }
            }
        }
        .sheet(isPresented: $showBookSelector) {
            BookSelectorView(readingList: readingList)
        }
        .sheet(isPresented: $showEditSheet) {
            EditReadingListView(readingList: readingList)
        }
        .alert("リストから削除", isPresented: $showRemoveAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let book = bookToRemove {
                    removeBookFromList(book)
                }
            }
        } message: {
            if let book = bookToRemove {
                Text("「\(book.title)」をリストから削除しますか？\n本棚からは削除されません。")
            }
        }
    }
    
    // MARK: - List Info Section
    
    private var listInfoSection: some View {
        VStack(spacing: 8) {
            // 説明文
            if let description = readingList.listDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            
            // 合計金額
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(readingList.totalValue.formatted())")
                    .font(.system(size: 32))
                Text("円")
                    .font(.system(size: 18))
            }
            .foregroundColor(.blue)
            
            Text("\(readingList.bookCount)冊")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 60)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if readingList.books.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("まだ本がありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showBookSelector = true
                    }) {
                        Text("本を追加する")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(readingList.books) { book in
                        bookCover(book: book)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 100)
    }
    
    // MARK: - Book Cover
    
    private func bookCover(book: UserBook) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
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
                    .id(imageURL)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .onTapGesture {
                if let index = readingList.books.firstIndex(where: { $0.id == book.id }) {
                    selectedBookIndex = index
                    withAnimation(.easeIn(duration: 0.2)) {
                        showBookCarousel = true
                    }
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    bookToRemove = book
                    showRemoveAlert = true
                } label: {
                    Label("リストから削除", systemImage: "minus.circle")
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
    }
    
    // MARK: - Actions
    
    private func removeBookFromList(_ book: UserBook) {
        readingList.books.removeAll { $0.persistentModelID == book.persistentModelID }
        readingList.updatedAt = Date()
        
        do {
            try context.save()
        } catch {
            print("❌ Failed to remove book from list: \(error)")
        }
    }
}

// MARK: - Edit Reading List View

/// リスト編集画面
struct EditReadingListView: View {
    @Bindable var readingList: ReadingList
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var listDescription: String = ""
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル", text: $title)
                }
                
                Section {
                    TextField("説明（任意）", text: $listDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("このリストを削除")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("リストを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onAppear {
                title = readingList.title
                listDescription = readingList.listDescription ?? ""
            }
            .alert("リストを削除", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    deleteList()
                }
            } message: {
                Text("「\(readingList.title)」を削除しますか？\nリストに含まれる本は削除されません。")
            }
        }
    }
    
    private func saveChanges() {
        readingList.title = title
        readingList.listDescription = listDescription.isEmpty ? nil : listDescription
        readingList.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to save reading list: \(error)")
        }
    }
    
    private func deleteList() {
        context.delete(readingList)
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to delete reading list: \(error)")
        }
    }
}

// MARK: - Book Carousel View

/// 本の詳細をカルーセル形式で表示するポップアップ
struct BookCarouselView: View {
    let books: [UserBook]
    let initialIndex: Int
    let readingList: ReadingList
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentBookId: PersistentIdentifier?
    
    init(books: [UserBook], initialIndex: Int, readingList: ReadingList, onDismiss: @escaping () -> Void) {
        self.books = books
        self.initialIndex = initialIndex
        self.readingList = readingList
        self.onDismiss = onDismiss
        
        // 初期値をここで設定
        if initialIndex < books.count {
            _currentBookId = State(initialValue: books[initialIndex].persistentModelID)
        }
    }
    
    private var currentIndex: Int {
        guard let id = currentBookId else { return 0 }
        return books.firstIndex(where: { $0.persistentModelID == id }) ?? 0
    }
    
    var body: some View {
        ZStack {
            // 背景の暗いオーバーレイ（タップで閉じる）
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // 浮いているカード
            VStack(spacing: 0) {
                // 閉じるボタン
                HStack {
                    Spacer()
                    Button(action: {
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                // リスト情報
                VStack(spacing: 4) {
                    Text(readingList.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let description = readingList.listDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // カルーセル（次の要素が見えるデザイン）
                GeometryReader { geometry in
                    let spacing: CGFloat = 16
                    let cardWidth = geometry.size.width * 0.65  // カード幅は65%
                    let sideInset = (geometry.size.width - cardWidth) / 2 - spacing / 2  // 左右の余白
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                bookDetailCard(book: book)
                                    .frame(width: cardWidth)
                                    .scrollTransition { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.85)
                                            .opacity(phase.isIdentity ? 1 : 0.7)
                                    }
                                    .id(book.persistentModelID)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, sideInset)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $currentBookId)
                }
                .frame(height: 450)
                
                Spacer()
                
                // ページインジケーター
                Text("\(currentIndex + 1) / \(books.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 60)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
    
    // 本の詳細カード
    private func bookDetailCard(book: UserBook) -> some View {
        VStack(spacing: 20) {
            // 本の表紙
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        bookPlaceholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        bookPlaceholder
                    }
                }
                .frame(width: 140, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: Color.primary.opacity(0.2), radius: 20, x: 0, y: 10)
            } else {
                bookPlaceholder
            }
            
            // 本の情報
            VStack(spacing: 8) {
                // タイトル
                Text(book.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                // 著者
                if !book.displayAuthor.isEmpty {
                    Text(book.displayAuthor)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // 金額
                if let price = book.priceAtRegistration {
                    Text("¥\(price.formatted())")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            
            // メモ
            if let memo = book.memo, !memo.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("メモ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(memo)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appCardBackground)
                )
            }
        }
        .padding(.vertical, 20)
    }
    
    private var bookPlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ReadingList.self, UserBook.self, Passbook.self, configurations: config)
    
    let list = ReadingList(title: "2024年ベスト", listDescription: "今年読んで良かった本たち")
    container.mainContext.insert(list)
    
    return NavigationStack {
        ReadingListDetailView(readingList: list)
    }
    .modelContainer(container)
}
