//
//  NaverBooksService.swift
//  BookBank
//
//  NAVER 書籍検索API（Vercelプロキシ経由）と通信するサービスクラス
//

import Foundation

/// NAVER Books API と通信するサービスクラス
///
/// 認証（Client ID / Secret）はプロキシ側で付与されるため、Swift側では渡さない。
/// プロキシは `query` パラメータのみ受け付け、`display=20` 固定・ページング未対応。
@MainActor
final class NaverBooksService {

    /// NAVER APIプロキシのURL（Vercelにデプロイ済み）
    private let proxyURL = "https://bookbank-share.vercel.app/api/naver"

    /// キーワードで書籍を検索
    /// - Note: プロキシがページング未対応のため、2ページ目以降は空配列を返す。
    func search(_ keyword: String, page: Int = 1) async throws -> BookSearchPage {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, page == 1 else {
            return BookSearchPage(books: [], rawItemCount: 0, totalCount: 0, hasMorePages: false)
        }

        var components = URLComponents(string: proxyURL)
        components?.queryItems = [
            URLQueryItem(name: "query", value: trimmed)
        ]

        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }

        #if DEBUG
        print("🔍 NAVERキーワード検索: \(trimmed)")
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
        return try await search(cleanISBN).books
    }

    // MARK: - Private

    private func performRequest(url: URL) async throws -> BookSearchPage {
        #if DEBUG
        print("📡 NAVER API Request: \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RakutenBooksError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RakutenBooksError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(NaverBookSearchResponse.self, from: data)

        #if DEBUG
        print("✅ NAVER API Response: \(decoded.items.count)件の書籍を取得")
        #endif

        // NAVER プロキシは display=20 固定・ページング未対応のため、次ページは常になし。
        let books = decoded.items.compactMap { $0.toRakutenBook() }
        return BookSearchPage(
            books: books,
            rawItemCount: decoded.items.count,
            totalCount: decoded.total,
            hasMorePages: false
        )
    }
}

// MARK: - NAVER レスポンス構造

/// NAVER Books Search API のレスポンス
struct NaverBookSearchResponse: Codable {
    /// 検索にヒットした総件数
    let total: Int?
    let items: [NaverBookItem]
}

/// NAVER Books Search API の1件のアイテム
struct NaverBookItem: Codable {
    let title: String?
    let author: String?
    let publisher: String?
    let pubdate: String?     // "YYYYMMDD"
    let isbn: String?        // "isbn10 isbn13"（スペース区切り）
    let image: String?
    let discount: String?    // 販売価格（KRW・文字列）
    let description: String?

    /// アプリ内共通モデル RakutenBook へ変換（価格通貨は KRW）
    func toRakutenBook() -> RakutenBook? {
        let cleanTitle = Self.sanitize(title ?? "")
        guard !cleanTitle.isEmpty else { return nil }

        let cleanAuthor = Self.sanitize(author ?? "")
            .replacingOccurrences(of: "^", with: ", ")
        let imageURL = (image?.isEmpty == false) ? image : nil

        return RakutenBook(
            title: cleanTitle,
            author: cleanAuthor,
            publisherName: Self.sanitize(publisher ?? ""),
            isbn: Self.isbn13(from: isbn),
            itemPrice: Self.price(from: discount),
            salesDate: Self.salesDate(from: pubdate),
            itemCaption: Self.sanitize(description ?? ""),
            mediumImageUrl: imageURL,
            largeImageUrl: imageURL,
            size: nil,
            seriesName: nil,
            booksGenreId: nil,
            sourceCurrencyCode: AppCurrency.krw.code
        )
    }

    /// 販売価格（KRW・文字列）を Int へ。空文字や 0 以下（NAVER は未販売・輸入書で "0" を返す）は
    /// 「価格不明」として nil を返し、他プロバイダと挙動を揃える（"-" 表示＋登録時に手入力）。
    private static func price(from discount: String?) -> Int? {
        guard let value = Int(discount ?? ""), value > 0 else { return nil }
        return value
    }

    /// "8983920777 9788983920775" → 13桁を優先して返す
    private static func isbn13(from raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let tokens = raw.split(separator: " ").map(String.init)
        return tokens.first(where: { $0.count == 13 }) ?? tokens.last ?? ""
    }

    /// "20200115" → "2020年01月15日"（RakutenBook.publishedYear が解釈できる形式）
    private static func salesDate(from pubdate: String?) -> String {
        guard let pubdate, pubdate.count >= 8 else { return "" }
        let chars = Array(pubdate)
        let year = String(chars[0..<4])
        let month = String(chars[4..<6])
        let day = String(chars[6..<8])
        return "\(year)年\(month)月\(day)日"
    }

    /// HTMLタグ（<b>等）とエンティティを除去
    private static func sanitize(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
