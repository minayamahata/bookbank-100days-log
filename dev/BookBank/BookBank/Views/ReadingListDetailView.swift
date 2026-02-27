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
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - State
    
    @State private var showBookSelector = false
    @State private var showEditSheet = false
    @State private var bookToRemove: UserBook?
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
    
    /// テーマカラーが黒（index 0）かどうか
    private var isBlackTheme: Bool {
        (readingList.colorIndex ?? 0) == 0
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
        .tint(.primary)
        .alert("リストを削除", isPresented: $showDeleteListAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                deleteReadingList()
            }
        } message: {
            Text("「\(readingList.title)」を削除しますか？\nリスト内の本は本棚に残ります。")
        }
        .tint(.primary)
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
            if let description = readingList.listDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 冊数と金額（右寄せ）
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Spacer()
                
                Text("\(readingList.bookCount)冊")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(readingList.totalValue.formatted())")
                        .font(.system(size: 28, weight: .medium))
                    Text("円")
                        .font(.system(size: 15, weight: .medium))
                }
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
                        Text("並べ替え")
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
                        Text("シェア")
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
                    if let imageURL = book.imageURL {
                        CachedAsyncImage(
                            url: URL(string: imageURL),
                            width: cellWidth,
                            height: cellHeight
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
            
            // 下段（6〜10冊目）- 6冊以上の場合のみ
            if !bottomRowBooks.isEmpty {
                HStack(spacing: spacing) {
                    ForEach(bottomRowBooks) { book in
                        if let imageURL = book.imageURL {
                            CachedAsyncImage(
                                url: URL(string: imageURL),
                                width: cellWidth,
                                height: cellHeight
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
    
    private func bookRow(book: UserBook) -> some View {
        NavigationLink(destination: UserBookDetailView(book: book)) {
            HStack(alignment: .center, spacing: 12) {
                // 本の表紙
                if let imageURL = book.imageURL,
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
                    .foregroundColor(themeColor)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                Label("リストから削除", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Book Cover
    
    private func bookCover(book: UserBook) -> some View {
        NavigationLink(destination: UserBookDetailView(book: book)) {
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
            }
            .aspectRatio(2/3, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                bookToRemove = book
                showRemoveAlert = true
            } label: {
                Label("リストから削除", systemImage: "trash")
            }
        }
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル", text: $title)
                }
                
                Section {
                    TextField("説明（任意）", text: $listDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: listDescription) { _, newValue in
                            if newValue.count > 50 {
                                listDescription = String(newValue.prefix(50))
                            }
                        }
                } footer: {
                    Text("50文字まで")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("テーマカラー")
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
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: 2)
                                                    .frame(width: 30, height: 30)
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
                listDescription = String((readingList.listDescription ?? "").prefix(50))
                selectedColorIndex = readingList.colorIndex ?? 0
                originalTitle = readingList.title
                originalDescription = String((readingList.listDescription ?? "").prefix(50))
                originalColorIndex = readingList.colorIndex ?? 0
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
        readingList.listDescription = listDescription.isEmpty ? nil : String(listDescription.prefix(50))
        readingList.colorIndex = selectedColorIndex
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
                    Image("icon-share")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
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
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
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
                    Image("icon-edit")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
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
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .frame(width: 24)
                    Text("このリストを削除")
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
    let readingList: ReadingList
    let shareURL: URL
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isCopied = false
    
    /// テーマカラー（colorIndexに基づく）
    private var themeColor: Color {
        PassbookColor.color(for: readingList.colorIndex ?? 0)
    }
    
    /// テーマカラーが黒（index 0）かどうか
    private var isBlackTheme: Bool {
        (readingList.colorIndex ?? 0) == 0
    }
    
    var body: some View {
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
            .navigationTitle("シェアプレビュー")
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
                    Text(isCopied ? "コピーしました" : "コピー")
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
                        Text("\(readingList.bookCount)冊")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(readingList.totalValue.formatted())")
                                .font(.system(size: 20, weight: .medium))
                            Text("円")
                                .font(.system(size: 12, weight: .medium))
                        }
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
                if readingList.bookCount > 4 {
                    Text("他\(readingList.bookCount - 4)冊")
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
    
    private func previewBookThumbnail(book: UserBook, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let imageURL = book.imageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: height)
            }
        }
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
