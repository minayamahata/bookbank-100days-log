//
//  RakutenBooksService.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import Foundation

/// 楽天Books APIと通信するサービスクラス
@MainActor
class RakutenBooksService {
    
    // MARK: - Properties
    
    /// 楽天アプリケーションID（後で設定してください）
    private let applicationId: String
    
    /// APIのベースURL
    private let baseURL = "https://app.rakuten.co.jp/services/api/BooksBook/Search/20170404"
    
    // MARK: - Initialization
    
    init(applicationId: String = "1011909627413951348") {
        self.applicationId = applicationId
    }
    
    // MARK: - Public Methods
    
    /// タイトルと著者名で書籍を検索
    /// - Parameters:
    ///   - keyword: 検索キーワード（タイトルまたは著者名）
    ///   - page: ページ番号（1から開始）
    /// - Returns: 検索結果の書籍リスト
    func search(_ keyword: String, page: Int = 1) async throws -> [RakutenBook] {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        
        // タイトル検索と著者検索を並行実行（キーワード検索は広範囲すぎるため除外）
        async let titleResults = searchByTitle(keyword, page: page)
        async let authorResults = searchByAuthor(keyword, page: page)
        
        let (titles, authors) = try await (titleResults, authorResults)
        
        // タイトル検索結果を優先的に配置
        var uniqueBooks: [String: RakutenBook] = [:]
        var orderedISBNs: [String] = []
        
        // タイトル検索結果を優先的に追加（関連度が高い）
        for book in titles {
            if uniqueBooks[book.isbn] == nil {
                uniqueBooks[book.isbn] = book
                orderedISBNs.append(book.isbn)
            }
        }
        
        // 著者検索結果を追加（タイトルに含まれないもののみ）
        for book in authors {
            if uniqueBooks[book.isbn] == nil {
                uniqueBooks[book.isbn] = book
                orderedISBNs.append(book.isbn)
            }
        }
        
        print("🔍 検索結果: タイトル=\(titles.count)件, 著者=\(authors.count)件, 合計=\(uniqueBooks.count)件")
        
        // 順序を保持して返す
        return orderedISBNs.compactMap { uniqueBooks[$0] }
    }
    
    /// タイトルで書籍を検索（内部用）
    private func searchByTitle(_ keyword: String, page: Int) async throws -> [RakutenBook] {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "applicationId", value: applicationId),
            URLQueryItem(name: "title", value: keyword),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hits", value: "30"),  // API上限を考慮して30件に戻す
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "sort", value: "standard")  // 関連度順（検索精度優先）
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        print("🔍 タイトル検索: \(keyword)")
        return try await performRequest(url: url)
    }
    
    /// 著者名で書籍を検索（内部用）
    private func searchByAuthor(_ keyword: String, page: Int) async throws -> [RakutenBook] {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "applicationId", value: applicationId),
            URLQueryItem(name: "author", value: keyword),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hits", value: "30"),  // API上限を考慮して30件に戻す
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "sort", value: "standard")  // 関連度順（検索精度優先）
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        print("🔍 著者検索: \(keyword)")
        return try await performRequest(url: url)
    }
    
    /// ISBNで書籍を検索
    /// - Parameter isbn: ISBN（10桁または13桁）
    /// - Returns: 検索結果の書籍リスト
    func searchByISBN(_ isbn: String) async throws -> [RakutenBook] {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        guard !cleanISBN.isEmpty else {
            return []
        }
        
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "applicationId", value: applicationId),
            URLQueryItem(name: "isbn", value: cleanISBN),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        return try await performRequest(url: url)
    }
    
    // MARK: - Private Methods
    
    /// APIリクエストを実行
    private func performRequest(url: URL) async throws -> [RakutenBook] {
        print("📡 API Request: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // HTTPステータスコードの確認
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RakutenBooksError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RakutenBooksError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // JSONデコード
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(RakutenBooksSearchResponse.self, from: data)
        
        print("✅ API Response: \(searchResponse.Items.count)件の書籍を取得")
        
        // 書籍データを抽出
        return searchResponse.Items.map { $0.Item }
    }
}

// MARK: - Error Types

/// 楽天Books APIのエラー
enum RakutenBooksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .invalidResponse:
            return "サーバーからの応答が無効です"
        case .httpError(let statusCode):
            return "HTTPエラー: \(statusCode)"
        case .decodingError(let error):
            return "データの解析に失敗しました: \(error.localizedDescription)"
        }
    }
}
