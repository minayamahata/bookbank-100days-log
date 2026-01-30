//
//  AddReadingListView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData

/// 読了リスト作成画面（ステップ形式）
struct AddReadingListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingLists: [ReadingList]
    
    @State private var title: String = ""
    @State private var showError: Bool = false
    @State private var createdList: ReadingList?
    @State private var showBookSelector = false
    @FocusState private var isFocused: Bool
    
    /// デフォルトのリスト名を生成
    private var defaultTitle: String {
        "Myリスト#\(existingLists.count + 1)"
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.appGroupedBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 閉じるボタン
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                Spacer()
                
                // メインコンテンツ
                VStack(spacing: 32) {
                    // タイトル
                    Text("読了リストの名前はどうしますか？")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    
                    // 入力フィールド
                    TextField("", text: $title)
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.appCardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                    
                    // 作成ボタン
                    Button(action: {
                        createReadingList()
                    }) {
                        Text("作成する")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(title.isEmpty ? Color.gray : Color.blue)
                            )
                    }
                    .disabled(title.isEmpty)
                }
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            // デフォルト名を設定
            title = defaultTitle
            // キーボードを表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("リストの作成に失敗しました")
        }
        .fullScreenCover(isPresented: $showBookSelector, onDismiss: {
            // 本の追加画面が閉じたら、この画面も閉じる
            dismiss()
        }) {
            if let list = createdList {
                AddBooksToNewListView(readingList: list)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func createReadingList() {
        guard !title.isEmpty else { return }
        
        let newList = ReadingList(title: title)
        context.insert(newList)
        
        do {
            try context.save()
            print("✅ New reading list created: \(title)")
            createdList = newList
            showBookSelector = true
        } catch {
            print("❌ Error creating reading list: \(error)")
            showError = true
        }
    }
}

// MARK: - Step 2: 本を追加する画面

/// 新規作成したリストに本を追加する画面
struct AddBooksToNewListView: View {
    @Bindable var readingList: ReadingList
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \UserBook.registeredAt, order: .reverse) private var allBooks: [UserBook]
    @State private var selectedBookIDs: Set<PersistentIdentifier> = []
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appGroupedBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ヘッダー
                    VStack(spacing: 4) {
                        Text("「\(readingList.title)」に")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("本を追加しましょう")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    if allBooks.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("本棚が空です")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        // 選択状態
                        HStack {
                            Text("\(selectedBookIDs.count)冊選択中")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        
                        // 本棚グリッド
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(allBooks) { book in
                                    selectableBookCover(book: book)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("スキップ") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了 (\(selectedBookIDs.count))") {
                        addSelectedBooks()
                    }
                    .disabled(selectedBookIDs.isEmpty)
                }
            }
        }
    }
    
    private func selectableBookCover(book: UserBook) -> some View {
        let isSelected = selectedBookIDs.contains(book.persistentModelID)
        
        return Button(action: {
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
                                .fill(Color.secondary.opacity(0.2))
                        }
                        .id(imageURL)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay {
                                Image(systemName: "book.closed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                    }
                    
                    // 選択状態アイコン
                    if isSelected {
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
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .padding(6)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .aspectRatio(2/3, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
    
    private func addSelectedBooks() {
        let booksToAdd = allBooks.filter { selectedBookIDs.contains($0.persistentModelID) }
        
        for book in booksToAdd {
            readingList.books.append(book)
        }
        
        readingList.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to add books: \(error)")
        }
    }
}

#Preview {
    AddReadingListView()
        .modelContainer(for: [ReadingList.self, UserBook.self, Passbook.self])
}
