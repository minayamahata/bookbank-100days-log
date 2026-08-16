//
//  ReadingListView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI

/// 読了リスト一覧画面
struct ReadingListView: View {
    var themeColor: Color = .accentColor
    var onNavigateToPassbook: (() -> Void)?
    
    @Environment(AppRepositories.self) private var repos
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates

    /// 読了リスト（リポジトリストリーム・`updatedAt` 降順）。
    /// 初回yield前は同期スナップショットで補い、空状態UIが1フレーム瞬くのを防ぐ（設計メモ 5.1節）
    @State private var loadedLists: [ReadingListDTO]?
    private var readingLists: [ReadingListDTO] { loadedLists ?? repos.readingLists.latestSnapshot }
    /// 一度でも値が確定したか（未確定のうちは空状態UIを出さない＝レビュー S4-2 と同型）
    private var hasResolvedLists: Bool {
        loadedLists != nil || !repos.readingLists.latestSnapshot.isEmpty
    }
    
    @State private var showAddList = false
    /// 削除確認の対象。**提示の有無もこの値だけで決まる**（`showDeleteAlert` のような
    /// 別フラグを併走させると、提示と値の反映がずれた瞬間に中身が空のアラートが出る＝
    /// 設計メモ 8.3節-18 と同型。V-2 はこれの `fullScreenCover` 版だった）
    @State private var listToDelete: ReadingListDTO?
    
    // 1カラム
    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        let _ = currencyManager.displayCurrency
        let _ = exchangeRates.lastUpdated

        ScrollView {
            if readingLists.isEmpty {
                // 空状態
                if hasResolvedLists {
                    emptyStateView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
            } else {
                // 1カラムカード一覧
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(readingLists) { list in
                        NavigationLink(value: list) {
                            readingListCard(list: list)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                listToDelete = list
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Color.appGroupedBackground
                    
                    Image("bg_glow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 2.2)
                        .blendMode(.screen)
                        .opacity(1)
                    
                    Image("bg_noise")
                        .resizable(resizingMode: .tile)
                        .blendMode(.overlay)
                        .opacity(0.2)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
        )
        .navigationTitle("readinglist.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ReadingListDTO.self) { list in
            ReadingListDetailView(list: list)
        }
        .task {
            for await value in repos.readingLists.observeReadingLists() {
                loadedLists = value
            }
        }
        .sheet(isPresented: $showAddList) {
            AddReadingListView(themeColor: themeColor, onNavigateToPassbook: onNavigateToPassbook)
        }
        .alert(
            "readinglist.delete.title",
            isPresented: Binding(
                get: { listToDelete != nil },
                set: { if !$0 { listToDelete = nil } }
            ),
            presenting: listToDelete
        ) { list in
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                deleteList(list)
            }
        } message: { list in
            Text(L10n.format("readinglist.delete.message", list.title))
        }
        .tint(.primary)
    }
    
    // MARK: - Subviews
    
    /// 空状態ビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("readinglist.create_prompt")
                .font(.app(.body))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    /// カード形式のリストビュー
    private func readingListCard(list: ReadingListDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 5カラム1行サムネイル（最大5冊、本の比率 2:3）
            GeometryReader { geometry in
                rowThumbnail(for: list, width: geometry.size.width)
            }
            .aspectRatio(list.books.count > 5 ? 10/6.3 : 10/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // リスト情報
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.app(.subheadline))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    BooksCountText(count: list.books.count, font: .app(.caption))
                        .foregroundColor(.secondary)
                    
                    if convertedTotalValue(for: list) > 0 {
                        Text("・")
                            .font(.app(.caption))
                            .foregroundColor(.secondary)
                        DisplayCurrencyPriceText(
                            amount: convertedTotalValue(for: list),
                            font: .app(.caption)
                        )
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appCardBackground)
                RoundedRectangle(cornerRadius: 16)
                    .fill(PassbookColor.color(for: list.colorIndex ?? 0).opacity(0.3))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func convertedTotalValue(for list: ReadingListDTO) -> Int {
        list.books.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    /// 5カラム×最大2行サムネイル（最大10冊、本の比率 2:3）
    private func rowThumbnail(for list: ReadingListDTO, width: CGFloat) -> some View {
        let books = Array(list.books.prefix(10))
        let topRowBooks = Array(books.prefix(5))
        let bottomRowBooks = books.count > 5 ? Array(books.dropFirst(5)) : []
        let spacing: CGFloat = 4
        let cellWidth: CGFloat = (width - spacing * 4) / 5
        let cellHeight: CGFloat = cellWidth * 1.5
        let rowSpacing: CGFloat = 8
        
        return VStack(spacing: rowSpacing) {
            HStack(spacing: spacing) {
                ForEach(topRowBooks) { book in
                    thumbnailCell(book: book, width: cellWidth, height: cellHeight)
                }
            }
            
            if !bottomRowBooks.isEmpty {
                HStack(spacing: spacing) {
                    ForEach(bottomRowBooks) { book in
                        thumbnailCell(book: book, width: cellWidth, height: cellHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func thumbnailCell(book: BookDTO, width: CGFloat, height: CGFloat) -> some View {
        LocalCoverImage(book: book) { coverImage in
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else if let imageURL = book.coverImageURL {
                CachedAsyncImage(
                    url: URL(string: imageURL),
                    width: width,
                    height: height
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))
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
    
    private func deleteList(_ list: ReadingListDTO) {
        Task {
            try? await repos.readingLists.deleteReadingList(id: list.id)
        }
    }
}

#Preview {
    NavigationStack {
        ReadingListView()
    }
    .bookBankPreviewEnvironment()
}
