//
//  ReadingListView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData

/// 読了リスト一覧画面
struct ReadingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var readingLists: [ReadingList]
    
    @State private var showAddList = false
    @State private var listToDelete: ReadingList?
    @State private var showDeleteAlert = false
    
    // 2カラムグリッド
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            if readingLists.isEmpty {
                // 空状態
                emptyStateView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                // 2カラムカード一覧
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(readingLists) { list in
                        NavigationLink(value: list) {
                            readingListCard(list: list)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                listToDelete = list
                                showDeleteAlert = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("読了リスト")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ReadingList.self) { list in
            ReadingListDetailView(readingList: list)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showAddList = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddList) {
            AddReadingListView()
        }
        .alert("リストを削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let list = listToDelete {
                    deleteList(list)
                }
            }
        } message: {
            if let list = listToDelete {
                Text("「\(list.title)」を削除しますか？\nリストに含まれる本は削除されません。")
            }
        }
    }
    
    // MARK: - Subviews
    
    /// 空状態ビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("自分の本棚の中から\n読了リストを作りましょう")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    /// カード形式のリストビュー
    private func readingListCard(list: ReadingList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 3x3グリッドサムネイル（正方形）
            GeometryReader { geometry in
                gridThumbnail(for: list, size: geometry.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // リスト情報
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text("\(list.bookCount)冊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if list.totalValue > 0 {
                        Text("・")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(list.displayTotalValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCardBackground)
        )
    }
    
    /// 3x3グリッドサムネイル
    private func gridThumbnail(for list: ReadingList, size: CGFloat) -> some View {
        let books = Array(list.books.prefix(9))
        let spacing: CGFloat = 2
        let cellSize: CGFloat = (size - spacing * 2) / 3
        
        return VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col
                        if index < books.count, let imageURL = books[index].imageURL {
                            AsyncImage(url: URL(string: imageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.15))
                                }
                            }
                            .frame(width: cellSize, height: cellSize)
                            .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
    
    /// プレースホルダー画像
    private var placeholderImage: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
    }
    
    // MARK: - Private Methods
    
    private func deleteList(_ list: ReadingList) {
        context.delete(list)
        do {
            try context.save()
        } catch {
            print("❌ Failed to delete reading list: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        ReadingListView()
    }
    .environment(ThemeManager())
    .modelContainer(for: [ReadingList.self, UserBook.self, Passbook.self])
}
