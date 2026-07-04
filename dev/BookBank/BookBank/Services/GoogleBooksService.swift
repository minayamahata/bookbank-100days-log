//
//  GoogleBooksService.swift
//  BookBank
//
//  Google Books 書籍検索API（Vercelプロキシ経由）と通信するサービスクラス
//

import Foundation

/// Google Books API と通信するサービスクラス（英語・繁体字・簡体字向け）
///
/// 認証（APIキー）はプロキシ側で付与されるため、Swift側では渡さない。
/// プロキシは `query` に加えて `country` / `startIndex` / `maxResults` を受け付ける。
@MainActor
final class GoogleBooksService {

    /// Google Books APIプロキシのURL（Vercelにデプロイ済み）
    private let proxyURL = "https://bookbank-share.vercel.app/api/google"

    /// 1ページあたりの取得件数
    /// - Note: Google Books API は maxResults に 40 まで指定できるが、実際には
    ///         1 リクエストあたり最大 20 件しか返さない。呼び出し側（BookSearchView）の
    ///         Google 用 pageSize と必ず揃えること（startIndex がこの値刻みになるため）。
    static let pageSize = 20

    /// 価格取得に使う Google Play ブックスの市場（国コード）
    ///
    /// Google Books は英語・中国語圏向けのため、検索言語に連動した市場を指定する。
    /// これにより自国市場で販売中の書籍の価格（saleInfo）が返りやすくなる。
    /// - en → US（洋書の価格ヒット率が最も高い）
    /// - zh-Hant / zh-Hans → TW（中国語書籍の Google Play 主要市場。本土は非対応のため）
    /// - その他 → US（フォールバック）
    private static var marketCountryCode: String {
        switch AppLanguage.effective {
        case .english: return "US"
        case .traditionalChinese, .simplifiedChinese: return "TW"
        case .japanese: return "JP"
        case .korean: return "KR"
        case .system: return "US"
        }
    }

    /// キーワードで書籍を検索
    /// - Note: `page`（1 起点）を Google Books の `startIndex` に換算してページングする。
    func search(_ keyword: String, page: Int = 1) async throws -> BookSearchPage {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, page >= 1 else {
            return BookSearchPage(books: [], totalCount: 0, hasMorePages: false)
        }

        let startIndex = (page - 1) * Self.pageSize

        var components = URLComponents(string: proxyURL)
        components?.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            // 価格（saleInfo）は市場（国）ごとに返るため、検索言語に合わせた市場を指定する
            URLQueryItem(name: "country", value: Self.marketCountryCode),
            URLQueryItem(name: "startIndex", value: String(startIndex)),
            URLQueryItem(name: "maxResults", value: String(Self.pageSize))
        ]

        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }

        #if DEBUG
        print("🔍 Google Booksキーワード検索: \(trimmed)")
        #endif
        return try await performRequest(url: url)
    }

    /// ISBNで書籍を検索
    /// - Note: プロキシは query パラメータのみ対応のため、ISBNをキーワードとして検索する。
    func searchByISBN(_ isbn: String) async throws -> [RakutenBook] {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        guard !cleanISBN.isEmpty else {
            return []
        }
        return try await search("isbn:\(cleanISBN)").books
    }

    // MARK: - Private

    private func performRequest(url: URL) async throws -> BookSearchPage {
        #if DEBUG
        print("📡 Google Books API Request: \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RakutenBooksError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RakutenBooksError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GoogleBooksSearchResponse.self, from: data)

        #if DEBUG
        print("✅ Google Books API Response: \(decoded.items?.count ?? 0)件の書籍を取得")
        #endif

        // 次ページの有無は、変換後（nil除外後）ではなくAPIが返した生の件数で判定する。
        // 1 リクエスト最大 pageSize 件が満杯なら、まだ後続ページがあるとみなす。
        let rawItemCount = decoded.items?.count ?? 0
        let books = (decoded.items ?? []).compactMap { $0.toRakutenBook() }
        return BookSearchPage(
            books: books,
            totalCount: decoded.totalItems,
            hasMorePages: rawItemCount >= Self.pageSize
        )
    }
}

// MARK: - Google Books レスポンス構造

/// Google Books API のレスポンス
struct GoogleBooksSearchResponse: Codable {
    /// 検索にヒットした総件数（Google が返す推定値）
    let totalItems: Int?
    let items: [GoogleBookItem]?
}

/// Google Books API の1件のアイテム
struct GoogleBookItem: Codable {
    let volumeInfo: GoogleVolumeInfo?
    let saleInfo: GoogleSaleInfo?

    /// アプリ内共通モデル RakutenBook へ変換
    func toRakutenBook() -> RakutenBook? {
        guard let volumeInfo,
              let title = volumeInfo.title, !title.isEmpty else {
            return nil
        }

        // 著者は配列。カンマ区切りで結合
        let author = (volumeInfo.authors ?? []).joined(separator: ", ")

        // 表紙画像は http を https に置換（App Transport Security 対策）
        let imageURL = volumeInfo.imageLinks?.thumbnail
            .map { $0.replacingOccurrences(of: "http://", with: "https://") }

        // saleInfo から価格を取得（retailPrice 優先、なければ listPrice）
        // 通貨は Google が返す currencyCode を尊重。価格なし（Google Play 非販売）は nil ＝金額不明とし、
        // 通貨のみ表示・手入力用に端末言語から推定した既定を持たせる。
        let priceInfo = saleInfo?.resolvedPrice
        let itemPrice = priceInfo?.minorUnits
        let currencyCode = priceInfo?.currency.code ?? AppCurrency.inferred().code

        return RakutenBook(
            title: title,
            author: author,
            publisherName: volumeInfo.publisher ?? "",
            isbn: volumeInfo.isbn13 ?? "",
            itemPrice: itemPrice,
            salesDate: volumeInfo.formattedSalesDate,
            itemCaption: "",
            mediumImageUrl: imageURL,
            largeImageUrl: imageURL,
            size: nil,
            seriesName: nil,
            booksGenreId: nil,
            sourceCurrencyCode: currencyCode
        )
    }
}

/// Google Books API の saleInfo（販売・価格情報）
struct GoogleSaleInfo: Codable {
    let retailPrice: GooglePrice?
    let listPrice: GooglePrice?

    /// 表示に使う価格（retailPrice 優先）を、対応通貨の最小単位に換算して返す
    var resolvedPrice: (minorUnits: Int, currency: AppCurrency)? {
        for price in [retailPrice, listPrice].compactMap({ $0 }) {
            guard let amount = price.amount,
                  let currency = AppCurrency(code: price.currencyCode) else {
                continue
            }
            // メジャー単位（例: 9.99）→ 最小単位（例: 999）
            let scaled = Decimal(amount) * Decimal(currency.minorUnitDivisor)
            var rounded = Decimal()
            var mutable = scaled
            NSDecimalRound(&rounded, &mutable, 0, .plain)
            return (NSDecimalNumber(decimal: rounded).intValue, currency)
        }
        return nil
    }
}

/// Google Books API の価格（amount + currencyCode）
struct GooglePrice: Codable {
    let amount: Double?
    let currencyCode: String?
}

/// Google Books API の volumeInfo
struct GoogleVolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let imageLinks: GoogleImageLinks?
    let industryIdentifiers: [GoogleIndustryIdentifier]?

    /// ISBN-13 を優先して返す（なければ ISBN-10）
    var isbn13: String? {
        guard let identifiers = industryIdentifiers, !identifiers.isEmpty else { return nil }
        if let isbn13 = identifiers.first(where: { $0.type == "ISBN_13" })?.identifier {
            return isbn13
        }
        return identifiers.first(where: { $0.type == "ISBN_10" })?.identifier
    }

    /// "2020-01-15" / "2020-01" / "2020" → "2020年01月15日" 等（RakutenBook.publishedYear が解釈できる形式）
    var formattedSalesDate: String {
        guard let publishedDate, !publishedDate.isEmpty else { return "" }
        let parts = publishedDate.split(separator: "-").map(String.init)
        switch parts.count {
        case 1:
            return "\(parts[0])年"
        case 2:
            return "\(parts[0])年\(parts[1])月"
        default:
            return "\(parts[0])年\(parts[1])月\(parts[2])日"
        }
    }
}

/// Google Books API の imageLinks
struct GoogleImageLinks: Codable {
    let smallThumbnail: String?
    let thumbnail: String?
}

/// Google Books API の industryIdentifiers（ISBN等）
struct GoogleIndustryIdentifier: Codable {
    let type: String?
    let identifier: String?
}
