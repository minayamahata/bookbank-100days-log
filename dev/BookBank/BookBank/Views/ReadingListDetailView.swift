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
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // MARK: - Body
    
    var body: some View {
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
