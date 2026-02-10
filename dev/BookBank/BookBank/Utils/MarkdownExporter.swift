import SwiftUI
import UniformTypeIdentifiers

// MARK: - Markdown Document

/// マークダウンファイルを表すドキュメント
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var text: String
    
    init(text: String) {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export Type

/// ダウンロードの種類
enum ExportType {
    case titleOnly
    case detailed
}

// MARK: - Passbook Export

/// 口座のマークダウンを生成
func generatePassbookMarkdown(passbook: Passbook, books: [UserBook], exportType: ExportType) -> String {
    var markdown = "# 本棚ダウンロード\n\n"
    
    // 口座情報
    let totalValue = books.reduce(0) { $0 + ($1.priceAtRegistration ?? 0) }
    markdown += "## \(passbook.name)（\(books.count)冊 / \(totalValue.formatted())円）\n\n"
    
    // 本のリスト
    for book in books {
        if exportType == .detailed {
            markdown += "### \(book.title)"
            if book.isFavorite {
                markdown += " ⭐️"
            }
            markdown += "\n"
            if let author = book.author, !author.isEmpty {
                markdown += "- 著者: \(author)\n"
            }
            if let price = book.priceAtRegistration {
                markdown += "- 金額: \(price.formatted())円\n"
            }
            if let publisher = book.publisher, !publisher.isEmpty {
                markdown += "- 出版社: \(publisher)\n"
            }
            markdown += "- 登録日: \(formatDate(book.registeredAt))\n"
            if let isbn = book.isbn, !isbn.isEmpty {
                markdown += "- ISBN: \(isbn)\n"
            }
            if let imageURL = book.imageURL, !imageURL.isEmpty {
                markdown += "- 表紙画像: \(imageURL)\n"
            }
            if let memo = book.memo, !memo.isEmpty {
                markdown += "- メモ:\n"
                // メモを引用ブロックとして整形
                let memoLines = memo.components(separatedBy: .newlines)
                for line in memoLines {
                    markdown += "  > \(line)\n"
                }
            }
            markdown += "\n"
        } else {
            // タイトルと著者名
            if let author = book.author, !author.isEmpty {
                markdown += "- \(book.title) / \(author)\n"
            } else {
                markdown += "- \(book.title)\n"
            }
        }
    }
    
    return markdown
}

// MARK: - Reading List Export

/// 読了リストのマークダウンを生成
func generateReadingListMarkdown(readingList: ReadingList, exportType: ExportType) -> String {
    var markdown = "# 読了リストダウンロード\n\n"
    
    // リスト情報
    let books = readingList.books
    let totalValue = books.reduce(0) { $0 + ($1.priceAtRegistration ?? 0) }
    markdown += "## \(readingList.title)（\(books.count)冊 / \(totalValue.formatted())円）\n\n"
    
    if let description = readingList.listDescription, !description.isEmpty {
        markdown += "> \(description)\n\n"
    }
    
    // 本のリスト
    for book in books {
        if exportType == .detailed {
            markdown += "### \(book.title)"
            if book.isFavorite {
                markdown += " ⭐️"
            }
            markdown += "\n"
            if let author = book.author, !author.isEmpty {
                markdown += "- 著者: \(author)\n"
            }
            if let price = book.priceAtRegistration {
                markdown += "- 金額: \(price.formatted())円\n"
            }
            if let publisher = book.publisher, !publisher.isEmpty {
                markdown += "- 出版社: \(publisher)\n"
            }
            markdown += "- 登録日: \(formatDate(book.registeredAt))\n"
            if let isbn = book.isbn, !isbn.isEmpty {
                markdown += "- ISBN: \(isbn)\n"
            }
            if let imageURL = book.imageURL, !imageURL.isEmpty {
                markdown += "- 表紙画像: \(imageURL)\n"
            }
            if let memo = book.memo, !memo.isEmpty {
                markdown += "- メモ:\n"
                // メモを引用ブロックとして整形
                let memoLines = memo.components(separatedBy: .newlines)
                for line in memoLines {
                    markdown += "  > \(line)\n"
                }
            }
            markdown += "\n"
        } else {
            // タイトルと著者名
            if let author = book.author, !author.isEmpty {
                markdown += "- \(book.title) / \(author)\n"
            } else {
                markdown += "- \(book.title)\n"
            }
        }
    }
    
    return markdown
}

// MARK: - Helper

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter.string(from: date)
}

// MARK: - Export Sheet View

/// ダウンロード形式選択シート
struct ExportSheetView: View {
    let title: String
    let bookCount: Int
    let totalValue: Int
    let sampleBooks: [String]  // 最初の数冊のタイトル
    let sampleDetailedBook: (title: String, author: String?, price: Int?, publisher: String?, date: String, isbn: String?, imageURL: String?, memo: String?, isFavorite: Bool)?
    let onExportTitleOnly: () -> Void
    let onExportDetailed: () -> Void
    
    private var platinumManager: PlatinumManager { PlatinumManager.shared }
    @State private var showPlatinumAlert = false
    
    // VSCode風のカラー（ダークモード時は黒）
    private let codeBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black  // ダークモード: 黒
            : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)  // ライトモード: #2D2D2D
    })
    private let headerBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)  // ダークモード: #1E1E1E
            : UIColor(red: 55/255, green: 55/255, blue: 55/255, alpha: 1)  // ライトモード: #373737
    })
    private let headingColor = Color(red: 86/255, green: 156/255, blue: 214/255)  // #569CD6 (青)
    private let listMarkerColor = Color(red: 206/255, green: 145/255, blue: 120/255)  // #CE9178 (オレンジ)
    private let textColor = Color(red: 212/255, green: 212/255, blue: 212/255)  // #D4D4D4
    private let propertyColor = Color(red: 156/255, green: 220/255, blue: 254/255)  // #9CDCFE (水色)
    
    // Proグラデーション
    private let proGradient = LinearGradient(
        colors: [
            Color(red: 34/255, green: 128/255, blue: 226/255),  // #2280e2
            Color(red: 253/255, green: 112/255, blue: 32/255)   // #fd7020
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    // タイトルと著者名のみプレビュー
                    VStack(alignment: .leading, spacing: 12) {
                        Text("タイトルと著者名のみ")
                            .font(.headline)
                        
                        // VSCode風コードブロック
                        codeBlock(content: titleOnlyAttributedContent)
                        
                        // ダウンロードボタン
                        Button(action: onExportTitleOnly) {
                            HStack(spacing: 8) {
                                Spacer()
                                Image("icon-download")
                                    .renderingMode(.template)
                                Text("タイトルと著者名のみでダウンロード")
                                Spacer()
                            }
                            .font(.system(size: 15))
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // 詳細情報プレビュー
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("詳細情報を含める")
                                .font(.headline)
                            
                            if !platinumManager.isPlatinum {
                                Text("Platinum")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(proGradient)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        // VSCode風コードブロック
                        codeBlock(content: detailedAttributedContent)
                        
                        // ダウンロードボタン（Platinum）
                        Button(action: {
                            if platinumManager.isPlatinum {
                                onExportDetailed()
                            } else {
                                showPlatinumAlert = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Spacer()
                                Image("icon-download")
                                    .renderingMode(.template)
                                Text(platinumManager.isPlatinum ? "詳細情報でダウンロード" : "詳細情報でダウンロード（Platinum）")
                                Spacer()
                            }
                            .font(.system(size: 15))
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(platinumManager.isPlatinum ? AnyShapeStyle(Color.primary.opacity(0.1)) : AnyShapeStyle(proGradient.opacity(0.1)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(platinumManager.isPlatinum ? AnyShapeStyle(Color.primary.opacity(0.3)) : AnyShapeStyle(proGradient), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("ダウンロード形式を選択")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Platinum機能", isPresented: $showPlatinumAlert) {
                Button("Platinum機能を体験する") { }
                    .tint(Color(red: 34/255, green: 128/255, blue: 226/255))  // #2280e2
            } message: {
                Text("詳細情報を含むダウンロードはPlatinum版の機能です。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Code Block View
    
    @ViewBuilder
    private func codeBlock(content: some View) -> some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 12, height: 12)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 12, height: 12)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 12, height: 12)
                Spacer()
                Text("markdown")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)
            
            // コード部分
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(codeBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Attributed Content
    
    @ViewBuilder
    private var titleOnlyAttributedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 見出し
            Text("# \(title)（\(bookCount)冊 / \(totalValue.formatted())円）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(headingColor)
            
            Text("")
            
            // リストアイテム
            ForEach(Array(sampleBooks.prefix(3).enumerated()), id: \.offset) { index, bookTitle in
                HStack(spacing: 0) {
                    Text("- ")
                        .foregroundColor(listMarkerColor)
                    Text(bookTitle)
                        .foregroundColor(textColor)
                }
                .font(.system(size: 11, design: .monospaced))
            }
            
            if sampleBooks.count > 3 {
                Text("...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }
    
    @ViewBuilder
    private var detailedAttributedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 口座名ヘッダー（h1）
            Text("# \(title)（\(bookCount)冊 / \(totalValue.formatted())円）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(headingColor)
            
            Text("")
            
            if let book = sampleDetailedBook {
                // 本のタイトル（h2）+ お気に入りマーク
                HStack(spacing: 0) {
                    Text("## \(book.title)")
                        .foregroundColor(headingColor)
                    if book.isFavorite {
                        Text(" ⭐️")
                            .foregroundColor(textColor)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                
                // プロパティ
                if let author = book.author, !author.isEmpty {
                    propertyLine(marker: "- ", key: "著者: ", value: author)
                }
                if let price = book.price {
                    propertyLine(marker: "- ", key: "金額: ", value: "\(price.formatted())円")
                }
                if let publisher = book.publisher, !publisher.isEmpty {
                    propertyLine(marker: "- ", key: "出版社: ", value: publisher)
                }
                propertyLine(marker: "- ", key: "登録日: ", value: book.date)
                if let isbn = book.isbn, !isbn.isEmpty {
                    propertyLine(marker: "- ", key: "ISBN: ", value: isbn)
                }
                if let imageURL = book.imageURL, !imageURL.isEmpty {
                    propertyLine(marker: "- ", key: "表紙画像: ", value: imageURL)
                }
                if let memo = book.memo, !memo.isEmpty {
                    propertyLine(marker: "- ", key: "メモ: ", value: memo)
                }
                
                Text("")
                Text("...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                Text("### サンプル本")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(headingColor)
                propertyLine(marker: "- ", key: "著者: ", value: "著者名")
                propertyLine(marker: "- ", key: "金額: ", value: "1,000円")
            }
        }
    }
    
    @ViewBuilder
    private func propertyLine(marker: String, key: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(marker)
                .foregroundColor(listMarkerColor)
            Text(key)
                .foregroundColor(propertyColor)
            Text(value)
                .foregroundColor(textColor)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
