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
    
    /// 楽天アプリケーションID
    private let applicationId: String
    
    /// APIのベースURL（総合検索API - 書籍・コミック・雑誌すべて対応）
    private let baseURL = "https://app.rakuten.co.jp/services/api/BooksTotal/Search/20170404"
    
    // MARK: - Initialization
    
    init(applicationId: String = "1011909627413951348") {
        self.applicationId = applicationId
    }
    
    // MARK: - Public Methods
    
    /// キーワードで書籍を検索
    /// - Parameters:
    ///   - keyword: 検索キーワード（タイトルまたは著者名）
    ///   - page: ページ番号（1から開始）
    /// - Returns: 検索結果の書籍リスト
    func search(_ keyword: String, page: Int = 1) async throws -> [RakutenBook] {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "applicationId", value: applicationId),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "booksGenreId", value: "001"),  // 本カテゴリ（コミック含む）
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatVersion", value: "2"),   // シンプルなJSON形式
            URLQueryItem(name: "field", value: "1"),           // 狭い検索（関連度が高い結果のみ）
            URLQueryItem(name: "hits", value: "30"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "sort", value: "standard"),     // 関連度順
            URLQueryItem(name: "outOfStockFlag", value: "1")   // 品切れも含める
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        print("🔍 キーワード検索: \(keyword)")
        return try await performRequest(url: url, filterKeyword: keyword)
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
            URLQueryItem(name: "isbnjan", value: cleanISBN),   // 総合検索APIではisbnjanを使用
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatVersion", value: "2"),   // シンプルなJSON形式
            URLQueryItem(name: "outOfStockFlag", value: "1")   // 品切れも含める
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        print("🔍 ISBN検索: \(cleanISBN)")
        return try await performRequest(url: url, filterKeyword: nil)
    }
    
    // MARK: - Private Methods
    
    /// APIリクエストを実行
    /// - Parameters:
    ///   - url: リクエストURL
    ///   - filterKeyword: タイトルまたは著者名に含まれるべきキーワード（nilの場合はフィルタリングしない）
    private func performRequest(url: URL, filterKeyword: String?) async throws -> [RakutenBook] {
        print("📡 API Request: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // HTTPステータスコードの確認
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RakutenBooksError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RakutenBooksError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // デバッグ用：レスポンスを出力
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 API Response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        // JSONデコード（formatVersion=2形式）
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(RakutenBooksTotalSearchResponse.self, from: data)
        
        print("✅ API Response: \(searchResponse.Items.count)件の書籍を取得")
        
        // 書籍データを抽出してRakutenBookに変換（本・コミックのみ）
        let books = searchResponse.Items.compactMap { item -> RakutenBook? in
            // CD/DVD/ゲーム/ソフトウェアを除外
            
            // 1. artistNameがある = CD/DVD
            if let artistName = item.artistName, !artistName.isEmpty {
                return nil
            }
            
            // 2. labelがある = CD/DVD
            if let label = item.label, !label.isEmpty {
                return nil
            }
            
            // 3. hardwareがある = ゲーム
            if let hardware = item.hardware, !hardware.isEmpty {
                return nil
            }
            
            // 4. osがある = ソフトウェア
            if let os = item.os, !os.isEmpty {
                return nil
            }
            
            // 5. booksGenreIdが001以外 = 本以外
            if let genreId = item.booksGenreId {
                // 001=本、002=CD、003=DVD、004=ゲーム、005=ソフト、006=洋書、007=雑誌
                // 001と006と007は許可（本、洋書、雑誌）
                let prefix = String(genreId.prefix(3))
                if !["001", "006", "007"].contains(prefix) {
                    return nil
                }
            }
            
            return item.toRakutenBook()
        }
        
        // キーワードフィルタリング（タイトルまたは著者名に含まれるもののみ）
        guard let keyword = filterKeyword, !keyword.isEmpty else {
            return books
        }
        
        // スペースを除去して比較用の文字列を作成
        let normalizedKeyword = keyword
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")  // 全角スペースも除去
        
        return books.filter { book in
            // タイトルと著者名からもスペースを除去して比較
            let normalizedTitle = book.title
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "　", with: "")
            let normalizedAuthor = book.author
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "　", with: "")
            
            // キーワードがタイトルまたは著者名に含まれているかチェック
            return normalizedTitle.contains(normalizedKeyword) || normalizedAuthor.contains(normalizedKeyword)
        }
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
