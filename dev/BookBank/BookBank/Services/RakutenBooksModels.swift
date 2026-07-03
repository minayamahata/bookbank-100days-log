//
//  RakutenBooksModels.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import Foundation
import SwiftData

// MARK: - 総合検索APIのレスポンス構造（formatVersion=2）

/// 楽天Books 総合検索APIのレスポンス
struct RakutenBooksTotalSearchResponse: Codable {
    let count: Int
    let page: Int
    let first: Int
    let last: Int
    let hits: Int
    let carrier: Int
    let pageCount: Int
    let Items: [RakutenTotalBookItem]
}

/// 総合検索APIの1件のアイテム（formatVersion=2形式）
/// formatVersion=2では、Items配列の各要素が直接アイテム情報を持つ
struct RakutenTotalBookItem: Codable {
    let title: String?
    let author: String?
    let artistName: String?       // CD/DVDの場合
    let publisherName: String?
    let label: String?            // CD/DVDの場合
    let isbn: String?
    let jan: String?
    let hardware: String?         // ゲームの場合
    let os: String?               // ソフトウェアの場合
    let itemCaption: String?
    let salesDate: String?
    let itemPrice: Int?
    let listPrice: Int?
    let discountRate: Int?
    let discountPrice: Int?
    let itemUrl: String?
    let affiliateUrl: String?
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?
    let chirayomiUrl: String?
    let availability: String?
    let postageFlag: Int?
    let limitedFlag: Int?
    let reviewCount: Int?
    let reviewAverage: String?
    let booksGenreId: String?
    
    // seriesNameとsizeは総合検索APIには含まれないことがある
    let size: String?
    let seriesName: String?
    
    /// RakutenBookに変換
    func toRakutenBook() -> RakutenBook? {
        // タイトルがない場合は無効
        guard let title = title, !title.isEmpty else {
            return nil
        }
        
        // ISBNまたはJANコードを識別子として使用
        let identifier = isbn ?? jan ?? ""
        
        // 著者名（書籍の場合はauthor、CD/DVDの場合はartistName）
        let authorName = author ?? artistName ?? ""
        
        // 出版社/レーベル
        let publisher = publisherName ?? label ?? ""
        
        return RakutenBook(
            title: title,
            author: authorName,
            publisherName: publisher,
            isbn: identifier,
            itemPrice: itemPrice ?? 0,
            salesDate: salesDate ?? "",
            itemCaption: itemCaption ?? "",
            mediumImageUrl: mediumImageUrl,
            largeImageUrl: largeImageUrl,
            size: size,
            seriesName: seriesName,
            booksGenreId: booksGenreId
        )
    }
}

// MARK: - 共通の書籍モデル

/// 楽天Booksの書籍詳細（アプリ内で使用する共通モデル）
struct RakutenBook: Codable, Identifiable {
    // Identifiableに準拠するためのID
    var id: String { isbn.isEmpty ? UUID().uuidString : isbn }
    
    let title: String
    let author: String
    let publisherName: String
    let isbn: String
    let itemPrice: Int
    let salesDate: String
    let itemCaption: String
    let mediumImageUrl: String?
    let largeImageUrl: String?
    let size: String?
    let seriesName: String?
    let booksGenreId: String?
    /// 価格の通貨（楽天は JPY、NAVER は KRW）。既定は JPY。
    var sourceCurrencyCode: String = AppCurrency.jpy.code
    
    /// 商品説明（長い）
    var itemDescription: String? {
        itemCaption.isEmpty ? nil : itemCaption
    }
    
    /// 出版年を取得（salesDateから）
    var publishedYear: Int? {
        // "2012年09月07日" 形式
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        if let date = formatter.date(from: salesDate) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        // "2012年09月" 形式
        formatter.dateFormat = "yyyy年MM月"
        if let date = formatter.date(from: salesDate) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        // "2012年" 形式
        formatter.dateFormat = "yyyy年"
        if let date = formatter.date(from: salesDate) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        return nil
    }

    /// 表示用の発行形態（APIの size、未取得時は nil）
    var displayFormat: String? {
        guard let size, !size.isEmpty else { return nil }
        return size
    }

    /// 文庫・単行本・コミックなどの判別（displayFormat から分類）
    var formatKind: BookFormatKind? {
        BookFormatKind.from(displayFormat)
    }

    /// 楽天APIから表紙URLが取得できているか（noimage プレースホルダーは除外）
    var hasCoverImageURL: Bool {
        BookCoverImageURL.isValid(largeImageUrl ?? mediumImageUrl)
    }

    /// 発行形態（size）を差し替えたコピーを返す
    func withSize(_ newSize: String?) -> RakutenBook {
        RakutenBook(
            title: title,
            author: author,
            publisherName: publisherName,
            isbn: isbn,
            itemPrice: itemPrice,
            salesDate: salesDate,
            itemCaption: itemCaption,
            mediumImageUrl: mediumImageUrl,
            largeImageUrl: largeImageUrl,
            size: newSize ?? size,
            seriesName: seriesName,
            booksGenreId: booksGenreId,
            sourceCurrencyCode: sourceCurrencyCode
        )
    }
}

/// 検索結果の発行形態カテゴリ
enum BookFormatKind: String, CaseIterable, Hashable {
    case bunko
    case tankobon
    case comic
    case other

    /// 楽天APIの size 文字列から判別
    static func from(_ size: String?) -> BookFormatKind? {
        guard let size, !size.isEmpty else { return nil }
        if size.contains("文庫") { return .bunko }
        if size.contains("単行本") { return .tankobon }
        if size.contains("コミック") || size.contains("漫画") { return .comic }
        return .other
    }
}

// MARK: - 書籍検索API（発行形態 size 取得用）

struct RakutenBooksBookSearchResponse: Codable {
    let Items: [RakutenBooksBookSearchItem]
}

struct RakutenBooksBookSearchItem: Codable {
    let Item: RakutenBookSearchItemDetail
}

struct RakutenBookSearchItemDetail: Codable {
    let size: String?
}

// MARK: - UserBookへの変換

extension RakutenBook {
    /// RakutenBookからUserBookを生成
    func toUserBook(passbook: Passbook, coverImageData: Data? = nil) -> UserBook {
        UserBook(
            title: title,
            author: author.isEmpty ? nil : author,
            isbn: isbn.isEmpty ? nil : isbn,
            publisher: publisherName.isEmpty ? nil : publisherName,
            publishedYear: publishedYear,
            seriesName: seriesName,
            price: itemPrice,
            imageURL: BookCoverImageURL.normalized(largeImageUrl ?? mediumImageUrl),
            coverImageData: coverImageData,
            bookFormat: displayFormat,
            pageCount: extractPageCount(),
            source: .api,
            passbook: passbook,
            currencyCode: AppCurrency(code: sourceCurrencyCode)?.code ?? AppCurrency.jpy.code
        )
    }
    
    /// itemCaptionからページ数を抽出（例：「320ページ」から320を抽出）
    private func extractPageCount() -> Int? {
        let pattern = "(\\d+)ページ"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = itemCaption as NSString
            let results = regex.matches(in: itemCaption, options: [], range: NSRange(location: 0, length: nsString.length))
            
            if let match = results.first {
                let pageString = nsString.substring(with: match.range(at: 1))
                return Int(pageString)
            }
        }
        return nil
    }
}

// MARK: - 為替レート

/// 為替レート（JPY 基準・1 JPY あたりの各通貨量）
@Observable
@MainActor
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    private(set) var ratesFromJPY: [String: Double] = ["JPY": 1.0]
    private(set) var lastUpdated: Date?

    private let cacheKey = "exchangeRatesFromJPY"
    private let cacheDateKey = "exchangeRatesUpdatedAt"
    private let refreshInterval: TimeInterval = 24 * 60 * 60

    private init() {
        loadCache()
        if Self.isRunningForPreviews {
            seedPreviewRatesIfNeeded()
        }
    }

    private static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func seedPreviewRatesIfNeeded() {
        guard !hasValidRates else { return }
        ratesFromJPY = [
            "JPY": 1.0,
            "USD": 0.0067,
            "TWD": 0.21,
            "CNY": 0.048,
            "KRW": 9.2
        ]
        lastUpdated = Date()
    }

    /// 必要に応じて API からレートを取得
    func refreshIfNeeded() async {
        guard !Self.isRunningForPreviews else { return }
        if hasValidRates,
           let lastUpdated,
           Date().timeIntervalSince(lastUpdated) < refreshInterval {
            return
        }
        await refresh()
    }

    /// サポート通貨のレートが揃っているか
    private var hasValidRates: Bool {
        AppCurrency.allCases.allSatisfy { ratesFromJPY[$0.code] != nil }
    }

    func refresh() async {
        guard !Self.isRunningForPreviews else { return }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/JPY") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            guard response.result == "success" else { return }

            var rates = response.rates
            rates["JPY"] = 1.0
            ratesFromJPY = rates
            lastUpdated = Date()
            saveCache()
        } catch {
            #if DEBUG
            print("❌ Exchange rate fetch failed: \(error)")
            #endif
        }
    }

    /// 元通貨の金額（最小通貨単位の整数）を表示通貨の最小単位へ換算
    func convert(_ amount: Int, from source: AppCurrency, to target: AppCurrency) -> Int {
        if source == target { return amount }

        // 最小単位 → メジャー単位
        let sourceMajor = Double(amount) / Double(source.minorUnitDivisor)

        // メジャー単位を一旦 JPY 建てに揃える
        let majorInJPY: Double
        if source == .jpy {
            majorInJPY = sourceMajor
        } else {
            guard let sourceRate = ratesFromJPY[source.code], sourceRate > 0 else {
                return amount
            }
            majorInJPY = sourceMajor / sourceRate
        }

        // JPY 建てから表示通貨のメジャー単位へ
        let targetMajor: Double
        if target == .jpy {
            targetMajor = majorInJPY
        } else {
            guard let targetRate = ratesFromJPY[target.code] else {
                return amount
            }
            targetMajor = majorInJPY * targetRate
        }

        // メジャー単位 → 最小単位（整数）
        return Int((targetMajor * Double(target.minorUnitDivisor)).rounded())
    }

    private func loadCache() {
        if let saved = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Double] {
            ratesFromJPY = saved
        }
        if let timestamp = UserDefaults.standard.object(forKey: cacheDateKey) as? Date {
            lastUpdated = timestamp
        }
    }

    private func saveCache() {
        UserDefaults.standard.set(ratesFromJPY, forKey: cacheKey)
        UserDefaults.standard.set(lastUpdated, forKey: cacheDateKey)
    }
}

private struct ExchangeRateResponse: Decodable {
    let result: String
    let baseCode: String
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case rates
        case conversionRates = "conversion_rates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decode(String.self, forKey: .result)
        baseCode = try container.decode(String.self, forKey: .baseCode)
        if let rates = try container.decodeIfPresent([String: Double].self, forKey: .rates) {
            self.rates = rates
        } else if let conversionRates = try container.decodeIfPresent([String: Double].self, forKey: .conversionRates) {
            self.rates = conversionRates
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.rates,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing rates or conversion_rates")
            )
        }
    }
}

// MARK: - 通貨マイグレーション

enum CurrencyMigration {
    private static let didMigrateV1Key = "didMigrateCurrencyCodeV1"

    /// 通貨コード未設定の既存書籍に JPY を付与する
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        migrateV1IfNeeded(context: context)
    }

    /// 通貨コード未設定の既存書籍に JPY を付与
    @MainActor
    private static func migrateV1IfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didMigrateV1Key) else { return }

        let descriptor = FetchDescriptor<UserBook>()
        guard let books = try? context.fetch(descriptor) else { return }

        var changed = false
        for book in books {
            if book.currencyCode == nil || book.currencyCode?.isEmpty == true {
                book.currencyCode = AppCurrency.jpy.code
                changed = true
            }
        }

        if changed {
            try? context.save()
        }

        UserDefaults.standard.set(true, forKey: didMigrateV1Key)
    }
}
