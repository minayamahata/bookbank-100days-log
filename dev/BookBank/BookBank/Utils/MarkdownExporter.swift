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

/// エクスポート時の表示通貨・換算設定
struct ExportFormattingContext {
    let displayCurrency: AppCurrency
    let exchangeRates: ExchangeRateService
    let locale: Locale
}

/// 口座のマークダウンを生成
@MainActor
func generatePassbookMarkdown(
    passbook: Passbook,
    books: [UserBook],
    exportType: ExportType,
    formatting: ExportFormattingContext
) -> String {
    var markdown = "\(String(localized: "export.passbook_header"))\n\n"
    
    // 口座情報
    let totalValue = books.totalDisplayAmount(in: formatting.displayCurrency, exchangeRates: formatting.exchangeRates)
    let totalText = MoneyDisplay.format(
        amount: totalValue,
        currency: formatting.displayCurrency,
        locale: formatting.locale
    )
    markdown += L10n.format("export.section_header", passbook.name, Int64(books.count), totalText) + "\n\n"
    
    // 本のリスト
    for book in books {
        if exportType == .detailed {
            markdown += "### \(book.title)"
            if book.isFavorite {
                markdown += " ⭐️"
            }
            markdown += "\n"
            if let author = book.author, !author.isEmpty {
                markdown += "- \(String(localized: "export.md.author"))\(author)\n"
            }
            if let priceText = MoneyDisplay.formattedPrice(
                amount: book.priceAtRegistration,
                sourceCurrency: book.storedCurrency,
                displayCurrency: formatting.displayCurrency,
                exchangeRates: formatting.exchangeRates,
                locale: formatting.locale
            ) {
                markdown += "- \(String(localized: "export.md.price"))\(priceText)\n"
            }
            if let publisher = book.publisher, !publisher.isEmpty {
                markdown += "- \(String(localized: "export.md.publisher"))\(publisher)\n"
            }
            markdown += "- \(String(localized: "export.md.registration_date"))\(formatDate(book.registeredAt))\n"
            if let isbn = book.isbn, !isbn.isEmpty {
                markdown += "- \(String(localized: "export.md.isbn"))\(isbn)\n"
            }
            if let imageURL = book.coverImageURL, !imageURL.isEmpty {
                markdown += "- \(String(localized: "export.md.cover"))\(imageURL)\n"
            }
            if let memo = book.memo, !memo.isEmpty {
                markdown += "- \(String(localized: "export.md.memo"))\n"
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
@MainActor
func generateReadingListMarkdown(
    readingList: ReadingList,
    exportType: ExportType,
    formatting: ExportFormattingContext
) -> String {
    var markdown = "\(String(localized: "export.readinglist_header"))\n\n"
    
    // リスト情報
    let books = readingList.books
    let totalValue = books.totalDisplayAmount(in: formatting.displayCurrency, exchangeRates: formatting.exchangeRates)
    let totalText = MoneyDisplay.format(
        amount: totalValue,
        currency: formatting.displayCurrency,
        locale: formatting.locale
    )
    markdown += L10n.format("export.section_header", readingList.title, Int64(books.count), totalText) + "\n\n"
    
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
                markdown += "- \(String(localized: "export.md.author"))\(author)\n"
            }
            if let priceText = MoneyDisplay.formattedPrice(
                amount: book.priceAtRegistration,
                sourceCurrency: book.storedCurrency,
                displayCurrency: formatting.displayCurrency,
                exchangeRates: formatting.exchangeRates,
                locale: formatting.locale
            ) {
                markdown += "- \(String(localized: "export.md.price"))\(priceText)\n"
            }
            if let publisher = book.publisher, !publisher.isEmpty {
                markdown += "- \(String(localized: "export.md.publisher"))\(publisher)\n"
            }
            markdown += "- \(String(localized: "export.md.registration_date"))\(formatDate(book.registeredAt))\n"
            if let isbn = book.isbn, !isbn.isEmpty {
                markdown += "- \(String(localized: "export.md.isbn"))\(isbn)\n"
            }
            if let imageURL = book.coverImageURL, !imageURL.isEmpty {
                markdown += "- \(String(localized: "export.md.cover"))\(imageURL)\n"
            }
            if let memo = book.memo, !memo.isEmpty {
                markdown += "- \(String(localized: "export.md.memo"))\n"
                let memoLines = memo.components(separatedBy: .newlines)
                for line in memoLines {
                    markdown += "  > \(line)\n"
                }
            }
            markdown += "\n"
        } else {
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
    AppDateFormat.display(date)
}

// MARK: - Export Sheet View

/// ダウンロード形式選択シート
struct ExportSheetView: View {
    let title: String
    let bookCount: Int
    let totalValue: Int
    let sampleBooks: [String]  // 最初の数冊のタイトル
    let sampleDetailedBook: (
        title: String,
        author: String?,
        price: Int?,
        sourceCurrency: AppCurrency,
        publisher: String?,
        date: String,
        isbn: String?,
        imageURL: String?,
        memo: String?,
        isFavorite: Bool
    )?
    let onExportTitleOnly: () -> Void
    let onExportDetailed: () -> Void
    
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    @State private var showUnlimitedPaywall = false
    
    // VSCode風のカラー（ダークモード時は黒）
    private let codeBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black  // ダークモード: #000000
            : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)  // ライトモード: #2D2D2D
    })
    private let headerBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 50/255, green: 50/255, blue: 50/255, alpha: 1)  // ダークモード: #323232
            : UIColor(red: 55/255, green: 55/255, blue: 55/255, alpha: 1)  // ライトモード: #373737
    })
    private let headingColor = Color(red: 86/255, green: 156/255, blue: 214/255)  // #569CD6 (青)
    private let listMarkerColor = Color(red: 206/255, green: 145/255, blue: 120/255)  // #CE9178 (オレンジ)
    private let textColor = Color(red: 212/255, green: 212/255, blue: 212/255)  // #D4D4D4
    private let propertyColor = Color(red: 156/255, green: 220/255, blue: 254/255)  // #9CDCFE (水色)
    
    private let unlimitedColor = Color(hex: "A1975D")
    
    private let proGradient = LinearGradient(
        colors: [
            Color(hex: "A1975D"),
            Color(hex: "A1975D")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        let _ = currencyManager.displayCurrency
        let _ = exchangeRates.lastUpdated

        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    // タイトルと著者名のみプレビュー
                    VStack(alignment: .leading, spacing: 12) {
                        Text("export.title_only")
                            .font(.headline)
                        
                        // VSCode風コードブロック
                        codeBlock(content: titleOnlyAttributedContent)
                        
                        // ダウンロードボタン
                        Button(action: onExportTitleOnly) {
                            HStack(spacing: 8) {
                                Spacer()
                                Image("icon-download")
                                    .renderingMode(.template)
                                Text("export.download")
                                Spacer()
                            }
                            .font(.system(size: 15))
                            .foregroundColor(Color(UIColor.systemBackground))
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.label))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // 詳細情報プレビュー
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("export.detailed")
                                .font(.headline)
                            
                            if !unlimitedManager.isUnlimited {
                                Text("paywall.unlimited")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(unlimitedColor)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        // VSCode風コードブロック
                        codeBlock(content: detailedAttributedContent)
                        
                        Button(action: {
                            if unlimitedManager.isUnlimited {
                                onExportDetailed()
                            } else {
                                showUnlimitedPaywall = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Spacer()
                                Image("icon-download")
                                    .renderingMode(.template)
                                Text("export.download")
                                Spacer()
                            }
                            .font(.system(size: 15))
                            .foregroundColor(unlimitedManager.isUnlimited ? Color(UIColor.systemBackground) : .white)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(unlimitedManager.isUnlimited ? AnyShapeStyle(Color(UIColor.label)) : AnyShapeStyle(unlimitedColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("export.title")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showUnlimitedPaywall) {
                UnlimitedPaywallView()
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
                Text("export.markdown_label")
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
            Text(L10n.format("export.preview_heading", title, Int64(bookCount), formattedTotalValue))
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
            Text(L10n.format("export.preview_heading", title, Int64(bookCount), formattedTotalValue))
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
                
                // プロパティ（すべて表示してフォーマットを示す）
                propertyLine(marker: "- ", key: String(localized: "export.md.author"), value: book.author ?? String(localized: "export.sample.author"))
                propertyLine(marker: "- ", key: String(localized: "export.md.price"), value: formattedSamplePrice(for: book))
                propertyLine(marker: "- ", key: String(localized: "export.md.publisher"), value: book.publisher ?? String(localized: "export.sample.publisher"))
                propertyLine(marker: "- ", key: String(localized: "export.md.registration_date"), value: book.date)
                propertyLine(marker: "- ", key: String(localized: "export.md.isbn"), value: book.isbn ?? "9784000000000")
                propertyLine(marker: "- ", key: String(localized: "export.md.cover"), value: "https://...")
                propertyLine(marker: "- ", key: String(localized: "export.md.memo"), value: book.memo ?? String(localized: "export.sample.memo"))
                
                Text("")
                Text("...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                Text("export.sample.book")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(headingColor)
                propertyLine(marker: "- ", key: String(localized: "export.md.author"), value: String(localized: "export.sample.author"))
                propertyLine(marker: "- ", key: String(localized: "export.md.price"), value: String(localized: "export.sample.price"))
                propertyLine(marker: "- ", key: String(localized: "export.md.publisher"), value: String(localized: "export.sample.publisher"))
                propertyLine(marker: "- ", key: String(localized: "export.md.registration_date"), value: "2024.01.01")
                propertyLine(marker: "- ", key: String(localized: "export.md.isbn"), value: "9784000000000")
                propertyLine(marker: "- ", key: String(localized: "export.md.cover"), value: "https://...")
                propertyLine(marker: "- ", key: String(localized: "export.md.memo"), value: String(localized: "export.sample.memo"))
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

    private var formattedTotalValue: String {
        MoneyDisplay.format(
            amount: totalValue,
            currency: currencyManager.displayCurrency,
            locale: languageManager.resolvedLocale
        )
    }

    private func formattedSamplePrice(
        for book: (
            title: String,
            author: String?,
            price: Int?,
            sourceCurrency: AppCurrency,
            publisher: String?,
            date: String,
            isbn: String?,
            imageURL: String?,
            memo: String?,
            isFavorite: Bool
        )
    ) -> String {
        MoneyDisplay.formattedPrice(
            amount: book.price,
            sourceCurrency: book.sourceCurrency,
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        ) ?? String(localized: "export.sample.price")
    }
}
