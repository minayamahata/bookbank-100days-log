//
//  ReadingListDetailView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import UniformTypeIdentifiers

/// 読了リスト詳細画面
struct ReadingListDetailView: View {
    
    // MARK: - Properties
    
    /// 遷移時に受け取ったリスト（初期値）。以後は id でストリームから解決し直す
    let initialList: ReadingListDTO

    /// 現在値。値型のコピーなので、表示中に元レコードが削除されても読み取りは安全（設計メモ 8.4節）
    @State private var readingList: ReadingListDTO

    init(list: ReadingListDTO) {
        self.initialList = list
        _readingList = State(initialValue: list)
    }
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRepositories.self) private var repos
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    
    /// 表示通貨での合計金額
    private var displayTotalValue: Int {
        readingList.books.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }

    // MARK: - State
    
    @State private var showBookSelector = false
    @State private var showEditSheet = false
    @State private var bookToRemove: BookDTO?
    @State private var showRemoveAlert = false
    @State private var isReorderMode = false
    @State private var showMoreSheet = false
    @State private var showExportSheet = false
    @State private var showExporter = false
    @State private var exportDocument: MarkdownDocument = MarkdownDocument(text: "")
    @State private var exportFileName: String = ""
    @State private var showDeleteListAlert = false
    
    // シェア関連
    @State private var isSharing = false
    @State private var shareURL: URL?
    @State private var showSharePreview = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    /// テーマカラー（colorIndexに基づく）
    private var themeColor: Color {
        PassbookColor.color(for: readingList.colorIndex ?? 0)
    }
    
    /// テーマカラーが黒かどうか
    private var isBlackTheme: Bool {
        (readingList.colorIndex ?? 0) == PassbookColor.blackThemeIndex
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // テーマカラーに応じた背景
            ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            
            // メインコンテンツ
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // リスト情報セクション
                        listInfoSection
                        
                        // コンテンツカード
                        VStack(spacing: 0) {
                            // 本のリスト
                            listContent
                        }
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: initialList.id) {
            // SwiftUI が同一identityのViewを別のリストで再利用した場合に @State が
            // 前のリストのまま残らないよう、購読前に必ず引数の値へ合わせる
            if readingList.id != initialList.id { readingList = initialList }
            for await lists in repos.readingLists.observeReadingLists() {
                if let updated = lists.first(where: { $0.id == initialList.id }) {
                    readingList = updated
                }
            }
        }
        .sheet(isPresented: $showBookSelector) {
            BookSelectorView(
                listTitle: readingList.title,
                existingBookIds: Set(readingList.books.map(\.id)),
                onAdd: addBooks
            )
        }
        .sheet(isPresented: $showEditSheet) {
            EditReadingListView(list: readingList)
        }
        .sheet(isPresented: $showMoreSheet) {
            MoreActionsSheet(
                title: readingList.title,
                onShare: {
                    showMoreSheet = false
                    shareReadingList()
                },
                onDownload: {
                    showMoreSheet = false
                    showExportSheet = true
                },
                onEdit: {
                    showMoreSheet = false
                    showEditSheet = true
                },
                onDelete: {
                    showMoreSheet = false
                    showDeleteListAlert = true
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSharePreview) {
            if let url = shareURL {
                SharePreviewSheet(readingList: readingList, shareURL: url)
            }
        }
        .alert("readinglist.share.error", isPresented: $showShareError) {
            Button("common.ok") { }
        } message: {
            Text(shareErrorMessage)
        }
        .overlay {
            if isSharing {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("readinglist.share.creating")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.appCardBackground)
                    )
                }
            }
        }
        .alert("readinglist.remove.title", isPresented: $showRemoveAlert) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                if let book = bookToRemove {
                    removeBookFromList(book)
                }
            }
        } message: {
            if let book = bookToRemove {
                Text(L10n.format("readinglist.remove.message", book.title))
            }
        }
        .tint(.primary)
        .alert("readinglist.delete.title", isPresented: $showDeleteListAlert) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                deleteReadingList()
            }
        } message: {
            Text(L10n.format("readinglist.delete.message_alt", readingList.title))
        }
        .tint(.primary)
        .fullScreenCover(isPresented: $isReorderMode) {
            ReorderBooksView(list: readingList)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(
                title: readingList.title,
                bookCount: readingList.books.count,
                totalValue: displayTotalValue,
                sampleBooks: readingList.books.prefix(4).map { book in
                    if let author = book.author, !author.isEmpty {
                        return "\(book.title) / \(author)"
                    } else {
                        return book.title
                    }
                },
                sampleDetailedBook: readingList.books.first.map { book in
                    (
                        title: book.title,
                        author: book.author,
                        price: book.priceAtRegistration,
                        sourceCurrency: book.storedCurrency,
                        publisher: book.publisher,
                        date: formatExportDate(book.registeredAt),
                        isbn: book.isbn,
                        imageURL: book.coverImageURL,
                        memo: book.memo,
                        isFavorite: book.isFavorite
                    )
                },
                onExportTitleOnly: {
                    showExportSheet = false
                    prepareExport(type: .titleOnly)
                },
                onExportDetailed: {
                    showExportSheet = false
                    prepareExport(type: .detailed)
                }
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                #if DEBUG
                print("✅ Export succeeded")
                #endif
            case .failure(let error):
                #if DEBUG
                print("❌ Export failed: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Export Helper
    
    private func prepareExport(type: ExportType) {
        let formatting = ExportFormattingContext(
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        )
        let markdown = generateReadingListMarkdown(readingList: readingList, exportType: type, formatting: formatting)
        exportDocument = MarkdownDocument(text: markdown)
        exportFileName = "\(readingList.title).md"
        showExporter = true
    }
    
    private func formatExportDate(_ date: Date) -> String {
        AppDateFormat.display(date)
    }
    
    // MARK: - List Info Section
    
    private var listInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // サムネイルグリッド（5カラム2列、最大10冊）
            if !readingList.books.isEmpty {
                GeometryReader { geometry in
                    thumbnailGridContent(width: geometry.size.width)
                }
                .frame(height: thumbnailGridHeight)
            }
            
            // タイトル（本棚グリッドとの間隔を確保）
            Text(readingList.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.top, readingList.books.isEmpty ? 0 : 34)
            
            // 説明文
            if let description = readingList.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 冊数と金額（右寄せ）
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Spacer()
                
                BooksCountText(count: readingList.books.count, font: .footnote)
                    .foregroundColor(.secondary)
                
                DisplayCurrencyPriceText(
                    amount: displayTotalValue,
                    font: .system(size: 28, weight: .medium),
                    symbolFont: .system(size: 17, weight: .medium)
                )
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: themeColor, location: 0),
                            Gradient.Stop(color: themeColor, location: 0.6),
                            Gradient.Stop(color: themeColor.opacity(0.3), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .padding(.top, 4)
            
            // アクションボタン
            HStack(spacing: 8) {
                // 追加ボタン
                Button(action: {
                    showBookSelector = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                        Text("common.add")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                    )
                }
                
                // 並べ替えボタン
                Button(action: {
                    isReorderMode = true
                }) {
                    HStack(spacing: 6) {
                        Image("icon-sort")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                        Text("readinglist.sort")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                    )
                }
                
                // シェア
                Button(action: {
                    shareReadingList()
                }) {
                    HStack(spacing: 6) {
                        Image("icon-share")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                        Text("common.share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                    )
                }
                
                // その他ボタン（ボトムシート）
                Button(action: {
                    showMoreSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 33, height: 33)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.1))
                        )
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
    
    // MARK: - Thumbnail Grid
    
    /// グリッドの高さを計算
    private var thumbnailGridHeight: CGFloat {
        let books = Array(readingList.books.prefix(10))
        let totalRows = books.count > 5 ? 2 : 1
        let estimatedCellWidth: CGFloat = 60
        let cellHeight = estimatedCellWidth * 1.5
        let rowSpacing: CGFloat = 8
        return totalRows == 2 ? (cellHeight * 2 + rowSpacing) : cellHeight
    }
    
    private func thumbnailGridContent(width: CGFloat) -> some View {
        let books = Array(readingList.books.prefix(10))
        let topRowBooks = Array(books.prefix(5))
        let bottomRowBooks = books.count > 5 ? Array(books.dropFirst(5)) : []
        let spacing: CGFloat = 4
        let cellWidth = (width - spacing * 4) / 5
        let cellHeight = cellWidth * 1.5
        let rowSpacing: CGFloat = 8
        
        return VStack(spacing: rowSpacing) {
            // 上段（1〜5冊目）
            HStack(spacing: spacing) {
                ForEach(topRowBooks) { book in
                    thumbnailCell(book: book, width: cellWidth, height: cellHeight)
                }
            }
            
            // 下段（6〜10冊目）- 6冊以上の場合のみ
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
    
    // MARK: - List Content
    
    private var listContent: some View {
        Group {
            if readingList.books.isEmpty {
                VStack(spacing: 12) {
                    Text("readinglist.empty")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("book.add_to_list") {
                        showBookSelector = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(readingList.books) { book in
                        bookRow(book: book)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Book Row
    
    private func bookRow(book: BookDTO) -> some View {
        NavigationLink(destination: UserBookDetailView(book: book)) {
            HStack(alignment: .center, spacing: 12) {
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
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 47, height: 70)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                
                // 本の情報
                VStack(alignment: .leading, spacing: 2) {
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
                
                // 金額
                if book.priceAtRegistration != nil {
                    BookPriceText(book: book, font: .subheadline, fontWeight: .medium)
                        .foregroundColor(themeColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : themeColor.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                bookToRemove = book
                showRemoveAlert = true
            } label: {
                Label("readinglist.remove.action", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Actions

    /// 本の追加。`BookSelectorView` から呼ばれ、失敗時は throw して向こうを閉じさせない
    private func addBooks(_ newBooks: [BookDTO]) async throws {
        let previous = readingList
        let existing = Set(previous.books.map(\.id))
        let merged = previous.books + newBooks.filter { !existing.contains($0.id) }
        let updated = previous.replacingBooks(merged, updatedAt: Date())
        readingList = updated
        do {
            try await repos.readingLists.updateReadingList(updated)
        } catch {
            rollback(optimistic: updated, previous: previous)
            throw error
        }
    }

    private func removeBookFromList(_ book: BookDTO) {
        let previous = readingList
        let remaining = previous.books.filter { $0.id != book.id }
        let updated = previous.replacingBooks(remaining, updatedAt: Date())
        readingList = updated

        Task {
            do {
                try await repos.readingLists.updateReadingList(updated)
            } catch {
                rollback(optimistic: updated, previous: previous)
            }
        }
    }

    /// 楽観更新の失敗時ロールバック（鮮度ガードつき・設計メモ 4.5節）。
    /// 待っている間にストリームや別操作が新しい値を入れていたら踏み潰さない
    private func rollback(optimistic: ReadingListDTO, previous: ReadingListDTO) {
        if let value = OptimisticUpdate.rollbackValue(
            current: readingList,
            optimistic: optimistic,
            previous: previous
        ) {
            readingList = value
        }
    }
    
    private func deleteReadingList() {
        let id = readingList.id
        Task {
            do {
                try await repos.readingLists.deleteReadingList(id: id)
            } catch {
                // 削除に失敗したら画面を閉じない（旧 do/catch と同じ意味論）
                return
            }
            dismiss()
        }
    }
    
    private func shareReadingList() {
        isSharing = true

        // 表示通貨に換算した合計を算出して渡す（各本は個別通貨のため単純合算しない）
        let displayCurrency = currencyManager.displayCurrency
        let totalValue = readingList.books.totalDisplayAmount(
            in: displayCurrency,
            exchangeRates: exchangeRates
        )
        let snapshot = readingList

        Task {
            do {
                let url = try await ShareService.shared.shareReadingList(
                    snapshot,
                    displayCurrency: displayCurrency,
                    totalValue: totalValue
                )
                await MainActor.run {
                    isSharing = false
                    shareURL = url
                    showSharePreview = true
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    shareErrorMessage = shareErrorDisplayMessage(for: error)
                    showShareError = true
                }
            }
        }
    }

    /// 共有失敗時にアラートへ表示する文言。
    /// サーバー／ネットワークエラーは技術的な生文言を避け、ローカライズした汎用メッセージを出す。
    private func shareErrorDisplayMessage(for error: Error) -> String {
        if let shareError = error as? ShareError {
            switch shareError {
            case .serverError, .networkError:
                return L10n.string("readinglist.share.error.generic")
            case .invalidURL, .invalidResponse, .decodingError:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Edit Reading List View

/// リスト編集画面
struct EditReadingListView: View {
    let list: ReadingListDTO

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRepositories.self) private var repos
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    
    @State private var title: String = ""
    @State private var listDescription: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var showDeleteAlert = false
    @State private var showExportSheet = false
    @State private var showExporter = false
    @State private var exportDocument: MarkdownDocument = MarkdownDocument(text: "")
    @State private var exportFileName: String = ""
    
    // 元の値を保存（変更検知用）
    @State private var originalTitle: String = ""
    @State private var originalDescription: String = ""
    @State private var originalColorIndex: Int = 0
    
    /// 変更があるかどうか
    private var hasChanges: Bool {
        title != originalTitle || listDescription != originalDescription || selectedColorIndex != originalColorIndex
    }

    /// 表示通貨での合計金額
    private var displayTotalValue: Int {
        list.books.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("book.title_label", text: $title)
                }
                
                Section {
                    TextField("readinglist.description", text: $listDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: listDescription) { _, newValue in
                            if newValue.count > 50 {
                                listDescription = String(newValue.prefix(50))
                            }
                        }
                } footer: {
                    Text("readinglist.description_limit")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("account.theme_color")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 0) {
                            ForEach(0..<PassbookColor.count, id: \.self) { index in
                                Button {
                                    selectedColorIndex = index
                                } label: {
                                    Circle()
                                        .fill(PassbookColor.color(for: index))
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            if selectedColorIndex == index {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(PassbookColor.color(for: index).contrastingTextColor)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button(action: {
                        showExportSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Spacer()
                            Image("icon-download")
                                .renderingMode(.template)
                            Text("readinglist.download_data")
                            Spacer()
                        }
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                    }
                }
                
                Section {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("readinglist.delete.this")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("readinglist.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveChanges()
                    }
                    .disabled(title.isEmpty || !hasChanges)
                    .foregroundColor(hasChanges && !title.isEmpty ? .blue : .primary.opacity(0.4))
                }
            }
            .onAppear {
                title = list.title
                listDescription = String((list.description ?? "").prefix(50))
                selectedColorIndex = list.colorIndex ?? 0
                originalTitle = list.title
                originalDescription = String((list.description ?? "").prefix(50))
                originalColorIndex = list.colorIndex ?? 0
            }
            .alert("readinglist.delete.title", isPresented: $showDeleteAlert) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    deleteList()
                }
            } message: {
                Text(L10n.format("readinglist.delete.message", list.title))
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheetView(
                    title: list.title,
                    bookCount: list.books.count,
                    totalValue: displayTotalValue,
                    sampleBooks: list.books.prefix(4).map { book in
                        if let author = book.author, !author.isEmpty {
                            return "\(book.title) / \(author)"
                        } else {
                            return book.title
                        }
                    },
                    sampleDetailedBook: list.books.first.map { book in
                        (
                            title: book.title,
                            author: book.author,
                            price: book.priceAtRegistration,
                            sourceCurrency: book.storedCurrency,
                            publisher: book.publisher,
                            date: formatExportDate(book.registeredAt),
                            isbn: book.isbn,
                            imageURL: book.coverImageURL,
                            memo: book.memo,
                            isFavorite: book.isFavorite
                        )
                    },
                    onExportTitleOnly: {
                        showExportSheet = false
                        prepareExport(type: .titleOnly)
                    },
                    onExportDetailed: {
                        showExportSheet = false
                        prepareExport(type: .detailed)
                    }
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: exportFileName
            ) { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("✅ Export succeeded")
                    #endif
                case .failure(let error):
                    #if DEBUG
                    print("❌ Export failed: \(error)")
                    #endif
                }
            }
        }
    }
    
    private func prepareExport(type: ExportType) {
        let formatting = ExportFormattingContext(
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        )
        let markdown = generateReadingListMarkdown(readingList: list, exportType: type, formatting: formatting)
        exportDocument = MarkdownDocument(text: markdown)
        exportFileName = "\(list.title).md"
        showExporter = true
    }
    
    private func formatExportDate(_ date: Date) -> String {
        AppDateFormat.display(date)
    }
    
    private func saveChanges() {
        var updated = list
        updated.title = title
        updated.description = listDescription.isEmpty ? nil : String(listDescription.prefix(50))
        updated.colorIndex = selectedColorIndex
        updated.updatedAt = Date()

        Task {
            do {
                try await repos.readingLists.updateReadingList(updated)
            } catch RepositoryError.readingListNotFound {
                // 並行削除。見た目は旧実装（保存が空振りして閉じる）と同じにする（設計メモ 4.5節）
                dismiss()
                return
            } catch {
                // それ以外の失敗では閉じない
                return
            }
            dismiss()
        }
    }
    
    private func deleteList() {
        let id = list.id
        Task {
            do {
                try await repos.readingLists.deleteReadingList(id: id)
            } catch {
                return
            }
            dismiss()
        }
    }
}

// MARK: - Reorder Books View

struct ReorderBooksView: View {
    let list: ReadingListDTO

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRepositories.self) private var repos
    
    @State private var books: [BookDTO] = []
    @State private var originalBooks: [BookDTO] = []
    @State private var showDiscardAlert = false
    
    /// 変更があるかどうか
    private var hasChanges: Bool {
        books.map(\.id) != originalBooks.map(\.id)
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(books) { book in
                    HStack(spacing: 12) {
                        // 削除ボタン
                        Button(action: {
                            withAnimation {
                                if let index = books.firstIndex(where: { $0.id == book.id }) {
                                    books.remove(at: index)
                                }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        
                        // 本の表紙
                        LocalCoverImage(book: book) { coverImage in
                            if let coverImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            } else if let imageURL = book.coverImageURL,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(url: url, width: 50, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                        
                        // 本の情報
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if !book.displayAuthor.isEmpty {
                                Text(book.displayAuthor)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                    }
                    .listRowBackground(Color.appCardBackground)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onMove(perform: moveBooks)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .background(Color.appCardBackground)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 100, for: .scrollContent)
            .navigationTitle("readinglist.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
        .onAppear {
            books = list.books
            originalBooks = list.books
        }
        .overlay {
            if showDiscardAlert {
                // カスタムダイアログ
                ZStack {
                    // 背景の暗いオーバーレイ
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    // ダイアログ本体
                    VStack(spacing: 20) {
                        // タイトルとメッセージ
                        VStack(spacing: 8) {
                            Text("readinglist.discard.title")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("readinglist.discard.message")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // ボタン
                        VStack(spacing: 12) {
                            // 編集を続けるボタン（Tint色、白文字）
                            Button(action: {
                                showDiscardAlert = false
                            }) {
                                Text("readinglist.continue_editing")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue)
                                    )
                            }
                            
                            // やめるボタン
                            Button(action: {
                                showDiscardAlert = false
                                dismiss()
                            }) {
                                Text("readinglist.quit")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.appCardBackground)
                    )
                    .padding(.horizontal, 40)
                }
            }
        }
    }
    
    private func moveBooks(from source: IndexSet, to destination: Int) {
        books.move(fromOffsets: source, toOffset: destination)
    }
    
    private func saveChanges() {
        let updated = list.replacingBooks(books, updatedAt: Date())
        Task {
            do {
                try await repos.readingLists.updateReadingList(updated)
            } catch RepositoryError.readingListNotFound {
                // 並行削除。並び替え先が消えているので閉じる
                dismiss()
                return
            } catch {
                return
            }
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ReadingListDetailView(list: PreviewSupport.sampleReadingList())
    }
    .bookBankPreviewEnvironment()
    .environment(AppShellState())
}

// MARK: - More Actions Sheet

/// その他アクションのボトムシート
struct MoreActionsSheet: View {
    let title: String
    let onShare: () -> Void
    let onDownload: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // シェア
            Button(action: onShare) {
                HStack(spacing: 12) {
                    Image("icon-share")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 24)
                    Text(L10n.format("readinglist.share.title", title))
                        .font(.system(size: 16))
                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
                .padding(.leading, 56)
            
            // ダウンロード
            Button(action: onDownload) {
                HStack(spacing: 12) {
                    Image("icon-download")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 24)
                    Text("common.download")
                        .font(.system(size: 16))
                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
                .padding(.leading, 56)
            
            // 名前と詳細の編集
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image("icon-edit")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .frame(width: 24)
                    Text("readinglist.edit_name_detail")
                        .font(.system(size: 16))
                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
                .padding(.leading, 56)
            
            // このリストを削除
            Button(action: onDelete) {
                HStack(spacing: 12) {
                    Image("icon-delete")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .frame(width: 24)
                    Text("readinglist.delete.this")
                        .font(.system(size: 16))
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Spacer()
        }
        .padding(.top, 20)
    }
}

// MARK: - Share Preview Sheet

/// シェアプレビュー画面
struct SharePreviewSheet: View {
    let readingList: ReadingListDTO
    let shareURL: URL
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    @State private var isCopied = false
    
    /// 表示通貨での合計金額
    private var displayTotalValue: Int {
        readingList.books.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    /// テーマカラー（colorIndexに基づく）
    private var themeColor: Color {
        PassbookColor.color(for: readingList.colorIndex ?? 0)
    }
    
    /// テーマカラーが黒かどうか
    private var isBlackTheme: Bool {
        (readingList.colorIndex ?? 0) == PassbookColor.blackThemeIndex
    }
    
    var body: some View {
        let _ = currencyManager.displayCurrency
        let _ = exchangeRates.lastUpdated

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // URLバー
                    urlBar
                    
                    // プレビューカード
                    previewCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
            .navigationTitle("readinglist.share.preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - URL Bar
    
    private var urlBar: some View {
        HStack(spacing: 12) {
            // URL（タップでブラウザで開く）
            Button(action: openInBrowser) {
                Text(shareURL.absoluteString)
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 0)
            
            // コピーボタン（固定幅）
            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                    Text(isCopied ? "common.copied" : "common.copy")
                        .font(.system(size: 12))
                }
                .foregroundColor(isCopied ? .green : .secondary)
                .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Preview Card
    
    /// グラデーションカラー
    private var gradientColor: Color {
        if colorScheme == .dark && isBlackTheme {
            return Color(hex: "292826")
        }
        return themeColor
    }
    
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // サムネイルグリッド（テーマカラー背景）
            previewThumbnailGrid
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        Color(.systemBackground)
                        
                        RadialGradient(
                            stops: [
                                Gradient.Stop(color: gradientColor, location: 0),
                                Gradient.Stop(color: gradientColor, location: 0.4),
                                Gradient.Stop(color: gradientColor.opacity(0), location: 1)
                            ],
                            center: UnitPoint(x: 0.4, y: 0.1),
                            startRadius: 0,
                            endRadius: 200
                        )
                    }
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16
                    )
                )
            
            // コンテンツ部分（白/ダーク背景）
            VStack(alignment: .leading, spacing: 16) {
                // ヘッダー
                VStack(alignment: .leading, spacing: 4) {
                    Text(readingList.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        BooksCountText(count: readingList.books.count, font: .subheadline)
                            .foregroundColor(.secondary)
                        
                        DisplayCurrencyPriceText(
                            amount: displayTotalValue,
                            font: .system(size: 20, weight: .medium),
                            symbolFont: .system(size: 13, weight: .medium)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: themeColor, location: 0),
                                    Gradient.Stop(color: themeColor, location: 0.6),
                                    Gradient.Stop(color: themeColor.opacity(0.3), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                
                // 本のリスト（最大4冊）
                VStack(spacing: 6) {
                    let displayBooks = Array(readingList.books.prefix(4))
                    ForEach(displayBooks) { book in
                        bookRow(book: book)
                    }
                }
                
                // 残りの冊数
                if readingList.books.count > 4 {
                    Text(L10n.format("readinglist.more_books", Int64(readingList.books.count - 4)))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(16)
            .background(Color.appCardBackground)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 0
                )
            )
        }
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Preview Thumbnail Grid
    
    private var previewThumbnailGrid: some View {
        let books = Array(readingList.books.prefix(10))
        let hasSecondRow = books.count > 5
        let spacing: CGFloat = 4
        let rowSpacing: CGFloat = 8
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let cellWidth = (availableWidth - spacing * 4) / 5
            let cellHeight = cellWidth * 1.5
            
            VStack(spacing: rowSpacing) {
                // 上段（1〜5冊目）
                HStack(spacing: spacing) {
                    ForEach(0..<min(5, books.count), id: \.self) { index in
                        previewBookThumbnail(book: books[index], width: cellWidth, height: cellHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // 下段（6〜10冊目）- 6冊以上の場合のみ
                if hasSecondRow {
                    HStack(spacing: spacing) {
                        ForEach(5..<books.count, id: \.self) { index in
                            previewBookThumbnail(book: books[index], width: cellWidth, height: cellHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .aspectRatio(hasSecondRow ? 5.0 / 3.2 : 5.0 / 1.5, contentMode: .fit)
    }
    
    private func previewBookThumbnail(book: BookDTO, width: CGFloat, height: CGFloat) -> some View {
        LocalCoverImage(book: book) { coverImage in
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else if let imageURL = book.coverImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: height)
            }
        }
    }
    
    private func bookRow(book: BookDTO) -> some View {
        HStack(spacing: 12) {
            // サムネイル
            LocalCoverImage(book: book) { coverImage in
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else if let imageURL = book.coverImageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url, width: 36, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 36, height: 54)
                }
            }
            
            // 本の情報
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !book.displayAuthor.isEmpty {
                    Text(book.displayAuthor)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 金額
            if book.priceAtRegistration != nil {
                BookPriceText(book: book, font: .subheadline, fontWeight: .medium)
                    .foregroundColor(themeColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : themeColor.opacity(0.1))
        )
    }
    
    // MARK: - Actions
    
    private func copyToClipboard() {
        UIPasteboard.general.string = shareURL.absoluteString
        
        withAnimation {
            isCopied = true
        }
        
        // 1.5秒後に元に戻す
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func openInBrowser() {
        UIApplication.shared.open(shareURL)
    }
}
