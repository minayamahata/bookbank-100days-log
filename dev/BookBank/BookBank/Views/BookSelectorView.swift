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
    
    // MARK: - State
    
    /// 選択された本のID
    @State private var selectedBookIDs: Set<PersistentIdentifier> = []
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    /// 既にリストに含まれている本のID
    private var existingBookIDs: Set<PersistentIdentifier> {
        Set(readingList.books.map { $0.persistentModelID })
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if allBooks.isEmpty {
                        emptyStateView
                    } else {
                        // 選択状態の表示
                        HStack {
                            Text("\(selectedBookIDs.count)冊選択中")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        
                        // 本棚グリッド
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(allBooks) { book in
                                selectableBookCover(book: book)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 100)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("本を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加 (\(selectedBookIDs.count))") {
                        addSelectedBooks()
                    }
                    .disabled(selectedBookIDs.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    /// 選択可能な本の表紙
    private func selectableBookCover(book: UserBook) -> some View {
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
                    
                    // 選択状態またはリスト内アイコン
                    if isAlreadyInList {
                        // 既にリストに含まれている
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 18, height: 18)
                            )
                            .padding(6)
                    } else if isSelected {
                        // 選択中
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 18, height: 18)
                            )
                            .padding(6)
                    } else {
                        // 未選択
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(6)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .opacity(isAlreadyInList ? 0.5 : 1.0)
            }
            .aspectRatio(2/3, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyInList)
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
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ReadingList.self, UserBook.self, Passbook.self, configurations: config)
    
    let list = ReadingList(title: "2024年ベスト")
    container.mainContext.insert(list)
    
    return BookSelectorView(readingList: list)
        .modelContainer(container)
}
