//
//  ReadingListDetailView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // 背景色（ライト: #F2F2F7, ダーク: #1C1C1E）
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1)  // #1C1C1E
                    : UIColor.systemGroupedBackground
            })
                .ignoresSafeArea()
            
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
                            
                            // スクロール最下部の余白（背景色を継続）
                            Color(UIColor { traits in
                                traits.userInterfaceStyle == .dark
                                    ? UIColor(red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1)  // #1C1C1E
                                    : UIColor.systemGroupedBackground
                            })
                                .frame(height: 100)
                        }
                        .frame(minHeight: geometry.size.height + 100)
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
            .animation(nil, value: showBookCarousel)
            
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
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBookSelector) {
            BookSelectorView(readingList: readingList)
        }
        .sheet(isPresented: $showEditSheet) {
            EditReadingListView(readingList: readingList)
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
        .alert("シェアエラー", isPresented: $showShareError) {
            Button("OK") { }
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
                        Text("シェアリンクを作成中...")
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
        .alert("リストを削除", isPresented: $showDeleteListAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                deleteReadingList()
            }
        } message: {
            Text("「\(readingList.title)」を削除しますか？\nリスト内の本は本棚に残ります。")
        }
        .fullScreenCover(isPresented: $isReorderMode) {
            ReorderBooksView(readingList: readingList)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(
                title: readingList.title,
                bookCount: readingList.books.count,
                totalValue: readingList.books.reduce(0) { $0 + ($1.priceAtRegistration ?? 0) },
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
                        publisher: book.publisher,
                        date: formatExportDate(book.registeredAt),
                        isbn: book.isbn,
                        imageURL: book.imageURL,
                        memo: book.memo,
                        isFavorite: book.isFavorite
                    )
                },
                onExportTitleOnly: {
                    showExportSheet = false
                    prepareExport()
                },
                onExportDetailed: {
                    // Pro機能（将来実装）
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
                print("✅ Export succeeded")
            case .failure(let error):
                print("❌ Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Export Helper
    
    private func prepareExport() {
        let markdown = generateReadingListMarkdown(readingList: readingList, exportType: .titleOnly)
        exportDocument = MarkdownDocument(text: markdown)
        exportFileName = "\(readingList.title).md"
        showExporter = true
    }
    
    private func formatExportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
    
    // MARK: - List Info Section
    
    private var listInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // サムネイルグリッド（5カラム2列、最大10冊）
            if !readingList.books.isEmpty {
                thumbnailGrid
            }
            
            // タイトル
            Text(readingList.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // 説明文
            if let description = readingList.listDescription, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            // 金額と冊数
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(readingList.totalValue.formatted())")
                        .font(.system(size: 20))
                    Text("円")
                        .font(.system(size: 13))
                }
                .foregroundColor(.blue)
                
                Text("\(readingList.bookCount)冊")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
                        Text("追加")
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
                
                // 並べ替え&削除ボタン
                Button(action: {
                    isReorderMode = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                        Text("並べ替え&削除")
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
                    Image("icon-more")
                        .renderingMode(.template)
                        .frame(width: 10, height: 10)
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
    
    private var thumbnailGrid: some View {
        let books = Array(readingList.books.prefix(10))
        let spacing: CGFloat = 4
        let sideMargin: CGFloat = 12
        let totalRows = 2
        
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width - sideMargin * 2
            let cellWidth = (availableWidth - spacing * 4) / 5
            let cellHeight = cellWidth * 1.5
            
            VStack(spacing: 16) {
                ForEach(0..<totalRows, id: \.self) { row in
                    // 奥行き係数: 0.0（最上段）〜 1.0（最下段）
                    let depth = CGFloat(row) / CGFloat(max(totalRows - 1, 1))
                    
                    // 棚板の高さと色の濃さを行によって変える
                    let shelfHeight: CGFloat = 6 + (4 * depth)  // 6pt 〜 10pt
                    let shelfThickness: CGFloat = 2 + (2 * depth)  // 2pt 〜 4pt
                    let shadowOpacity = 0.08 + (0.08 * depth)  // 0.08 〜 0.16
                    let shadowY: CGFloat = 4 + (6 * depth)  // 4pt 〜 10pt
                    
                    VStack(spacing: 0) {
                        // 本の行
                        // 下段（row == 1）はセンタリング
                        if row == 1 {
                            HStack(spacing: spacing) {
                                ForEach(5..<min(10, books.count), id: \.self) { index in
                                    if let imageURL = books[index].imageURL {
                                        CachedAsyncImage(
                                            url: URL(string: imageURL),
                                            width: cellWidth,
                                            height: cellHeight
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            // 上段は従来通り
                            HStack(spacing: spacing) {
                                ForEach(0..<5, id: \.self) { col in
                                    let index = col
                                    if index < books.count, let imageURL = books[index].imageURL {
                                        CachedAsyncImage(
                                            url: URL(string: imageURL),
                                            width: cellWidth,
                                            height: cellHeight
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                    } else {
                                        Color.clear
                                            .frame(width: cellWidth, height: cellHeight)
                                    }
                                }
                            }
                            .padding(.horizontal, sideMargin)
                        }
                        
                        // 棚板（奥行き表現）
                        VStack(spacing: 0) {
                            // 棚板の上面
                            Rectangle()
                                .fill(Color(UIColor { traits in
                                    traits.userInterfaceStyle == .dark
                                        ? UIColor.black  // ダーク: 黒
                                        : UIColor.white  // ライト: 白
                                }))
                                .frame(height: shelfHeight)
                            
                            // 棚板の側面（厚み）- 奥行きで変化
                            Rectangle()
                                .fill(Color(UIColor { traits in
                                    traits.userInterfaceStyle == .dark
                                        ? UIColor(white: 0.15, alpha: 1)  // ダーク: 濃いグレー（黒に近い）
                                        : UIColor(white: 0.92, alpha: 1)  // ライト: 薄いグレー
                                }))
                                .frame(height: shelfThickness)
                        }
                        .shadow(
                            color: Color(UIColor { traits in
                                traits.userInterfaceStyle == .dark
                                    ? UIColor.black.withAlphaComponent(0.3)  // ダーク: 黒いシャドウ
                                    : UIColor.black.withAlphaComponent(shadowOpacity)  // ライト: 黒いシャドウ
                            }),
                            radius: 6,
                            x: 3,
                            y: shadowY
                        )
                    }
                }
            }
        }
        // アスペクト比を調整（棚板の高さと余白を考慮）
        .aspectRatio(5.0 / 3.6, contentMode: .fit)
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        Group {
            if readingList.books.isEmpty {
                VStack(spacing: 12) {
                    Text("まだ本がありません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("本を追加する") {
                        showBookSelector = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(readingList.books) { book in
                        bookRow(book: book)
                    }
                }
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Book Row
    
    private func bookRow(book: UserBook) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 本の表紙
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 75)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            if let price = book.priceAtRegistration {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(price.formatted())")
                        .font(.subheadline)
                    Text("円")
                        .font(.caption2)
                }
                .foregroundColor(.blue)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
    
    // MARK: - Book Cover
    
    private func bookCover(book: UserBook) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // 本の表紙
                if let imageURL = book.imageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(
                        url: url,
                        width: geometry.size.width,
                        height: geometry.size.width * 1.5
                    )
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
    
    private func deleteReadingList() {
        context.delete(readingList)
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to delete reading list: \(error)")
        }
    }
    
    private func shareReadingList() {
        isSharing = true
        
        Task {
            do {
                let url = try await ShareService.shared.shareReadingList(readingList)
                await MainActor.run {
                    isSharing = false
                    shareURL = url
                    showSharePreview = true
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    shareErrorMessage = error.localizedDescription
                    showShareError = true
                }
            }
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
    @State private var showExportSheet = false
    @State private var showExporter = false
    @State private var exportDocument: MarkdownDocument = MarkdownDocument(text: "")
    @State private var exportFileName: String = ""
    
    // 元の値を保存（変更検知用）
    @State private var originalTitle: String = ""
    @State private var originalDescription: String = ""
    
    /// 変更があるかどうか
    private var hasChanges: Bool {
        title != originalTitle || listDescription != originalDescription
    }
    
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
                    Button(action: {
                        showExportSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Spacer()
                            Image("icon-download")
                                .renderingMode(.template)
                            Text("リストデータをダウンロードする")
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
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                    }
                    .disabled(title.isEmpty || !hasChanges)
                    .foregroundColor(hasChanges && !title.isEmpty ? .blue : .primary.opacity(0.4))
                }
            }
            .onAppear {
                title = readingList.title
                listDescription = readingList.listDescription ?? ""
                originalTitle = readingList.title
                originalDescription = readingList.listDescription ?? ""
            }
            .alert("リストを削除", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    deleteList()
                }
            } message: {
                Text("「\(readingList.title)」を削除しますか？\nリストに含まれる本は削除されません。")
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheetView(
                    title: readingList.title,
                    bookCount: readingList.books.count,
                    totalValue: readingList.books.reduce(0) { $0 + ($1.priceAtRegistration ?? 0) },
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
                            publisher: book.publisher,
                            date: formatExportDate(book.registeredAt),
                            isbn: book.isbn,
                            imageURL: book.imageURL,
                            memo: book.memo,
                            isFavorite: book.isFavorite
                        )
                    },
                    onExportTitleOnly: {
                        showExportSheet = false
                        prepareExport()
                    },
                    onExportDetailed: {
                        // Pro機能（将来実装）
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
                    print("✅ Export succeeded")
                case .failure(let error):
                    print("❌ Export failed: \(error)")
                }
            }
        }
    }
    
    private func prepareExport() {
        let markdown = generateReadingListMarkdown(readingList: readingList, exportType: .titleOnly)
        exportDocument = MarkdownDocument(text: markdown)
        exportFileName = "\(readingList.title).md"
        showExporter = true
    }
    
    private func formatExportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
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
                CachedAsyncImage(url: url, width: 140, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
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
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
    }
}

// MARK: - Reorder Books View

struct ReorderBooksView: View {
    @Bindable var readingList: ReadingList
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var books: [UserBook] = []
    @State private var originalBooks: [UserBook] = []
    @State private var showDiscardAlert = false
    
    /// 変更があるかどうか
    private var hasChanges: Bool {
        guard books.count == originalBooks.count else { return true }
        for (index, book) in books.enumerated() {
            if book.id != originalBooks[index].id {
                return true
            }
        }
        return false
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
                        if let imageURL = book.imageURL,
                           let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url, width: 50, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 50, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
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
            .navigationTitle("リストを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
        .onAppear {
            books = readingList.books
            originalBooks = readingList.books
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
                            Text("変更を取り消しますか？")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("いま終了すると、変更した内容は保存されません。")
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
                                Text("編集を続ける")
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
                                Text("やめる")
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
        // 本の順序を更新
        readingList.books = books
        readingList.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Failed to save reordered books: \(error)")
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
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .frame(width: 24)
                    Text("「\(title)」をシェア")
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
                        .frame(width: 24)
                    Text("ダウンロード")
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
                    Image(systemName: "pencil")
                        .font(.system(size: 18))
                        .frame(width: 24)
                    Text("名前と詳細の編集")
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
                        .frame(width: 24)
                    Text("このリストを削除")
                        .font(.system(size: 16))
                    Spacer()
                }
                .foregroundColor(.primary)
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
    let readingList: ReadingList
    let shareURL: URL
    
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false
    
    // カード背景色
    private let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1)  // #2C2C2E
            : UIColor.white
    })
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // プレビューカード
                    previewCard
                    
                    // アクションボタン
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("シェアプレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(.secondarySystemFill)))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Preview Card
    
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 4) {
                Text(readingList.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text("\(readingList.totalValue.formatted())円")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    Text("・")
                        .foregroundColor(.secondary)
                    
                    Text("\(readingList.bookCount)冊")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // 本のリスト（最大4冊）
            let displayBooks = Array(readingList.books.prefix(4))
            ForEach(displayBooks) { book in
                bookRow(book: book)
            }
            
            // 残りの冊数
            if readingList.bookCount > 4 {
                Text("他\(readingList.bookCount - 4)冊")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    private func bookRow(book: UserBook) -> some View {
        HStack(spacing: 12) {
            // サムネイル
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: 36, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 36, height: 54)
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
            if let price = book.priceAtRegistration {
                Text("\(price.formatted())円")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // リンクをコピー
            Button(action: copyToClipboard) {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16))
                    Text(isCopied ? "コピーしました！" : "リンクをコピー")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                )
                .foregroundColor(.primary)
            }
            .disabled(isCopied)
            
            // Xでシェア
            Button(action: shareOnX) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 16))
                    Text("Xでシェア")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
                .foregroundColor(.white)
            }
        }
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
    
    private func shareOnX() {
        let tweetText = "「\(readingList.title)」を共有しました"
        let encodedText = tweetText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedURL = shareURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "https://x.com/intent/tweet?text=\(encodedText)&url=\(encodedURL)") {
            UIApplication.shared.open(url)
        }
    }
}
