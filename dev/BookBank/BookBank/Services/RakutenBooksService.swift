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
    
    /// 楽天APIプロキシのベースURL（Vercelにデプロイ済み）
    /// applicationId / accessKey の認証はプロキシ側で付与されるため、Swift側では渡さない
    private let proxyURL = "https://bookbank-share.vercel.app/api/rakuten"

    /// ISBN → 発行形態のセッションキャッシュ
    private var formatCache: [String: String] = [:]
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// キーワードで書籍を検索
    /// - Parameters:
    ///   - keyword: 検索キーワード（タイトルまたは著者名）
    ///   - page: ページ番号（1から開始）
    /// - Returns: 検索結果の書籍リスト
    func search(_ keyword: String, page: Int = 1) async throws -> BookSearchPage {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            return BookSearchPage(books: [], totalCount: 0, hasMorePages: false)
        }
        
        var components = URLComponents(string: proxyURL)
        components?.queryItems = [
            URLQueryItem(name: "endpoint", value: "total"),    // 総合検索APIを指定
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
        
        #if DEBUG
        print("🔍 キーワード検索: \(keyword)")
        #endif
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
        
        var components = URLComponents(string: proxyURL)
        components?.queryItems = [
            URLQueryItem(name: "endpoint", value: "total"),    // 総合検索APIを指定
            URLQueryItem(name: "isbnjan", value: cleanISBN),   // 総合検索APIではisbnjanを使用
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatVersion", value: "2"),   // シンプルなJSON形式
            URLQueryItem(name: "outOfStockFlag", value: "1")   // 品切れも含める
        ]
        
        guard let url = components?.url else {
            throw RakutenBooksError.invalidURL
        }
        
        #if DEBUG
        print("🔍 ISBN検索: \(cleanISBN)")
        #endif
        return try await performRequest(url: url, filterKeyword: nil).books
    }
    
    // MARK: - Private Methods
    
    /// APIリクエストを実行
    /// - Parameters:
    ///   - url: リクエストURL
    ///   - filterKeyword: タイトルまたは著者名に含まれるべきキーワード（nilの場合はフィルタリングしない）
    private func performRequest(url: URL, filterKeyword: String?) async throws -> BookSearchPage {
        #if DEBUG
        print("📡 API Request: \(url.absoluteString)")
        #endif
        
        // 楽天APIは約1リクエスト/秒のレート制限があり、発行形態補完などと重なると
        // 429 が返ることがある。一時的失敗はバックオフで再試行してページングを止めない。
        let data = try await fetchDataWithRetry(from: url)
        
        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 API Response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        #endif
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(RakutenBooksTotalSearchResponse.self, from: data)
        
        #if DEBUG
        print("✅ API Response: \(searchResponse.Items.count)件の書籍を取得")
        #endif
        
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
        
        let filteredBooks: [RakutenBook]
        if let keyword = filterKeyword, !keyword.isEmpty {
            // スペースを除去して比較用の文字列を作成
            let normalizedKeyword = keyword
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "　", with: "")

            filteredBooks = books.filter { book in
                let normalizedTitle = book.title
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "　", with: "")
                let normalizedAuthor = book.author
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "　", with: "")

                return normalizedTitle.contains(normalizedKeyword) || normalizedAuthor.contains(normalizedKeyword)
            }
        } else {
            filteredBooks = books
        }

        // 総合検索APIは size を返さない。発行形態はここで待たず、
        // 呼び出し側が enrichWithFormat で後追い取得する（初期表示を速くするため）。
        // 次ページの有無は、絞り込み後の件数ではなくAPIのページ情報（page < pageCount）で判定する。
        return BookSearchPage(
            books: filteredBooks,
            totalCount: searchResponse.count,
            hasMorePages: searchResponse.page < searchResponse.pageCount
        )
    }

    /// レート制限（429）やサーバー側の一時的エラー（5xx）を指数バックオフで再試行しつつ取得する。
    /// - Note: 成功時は本文データを返し、恒久的な失敗はそのまま throw する。
    private func fetchDataWithRetry(from url: URL, maxAttempts: Int = 4) async throws -> Data {
        var lastStatusCode = 0
        for attempt in 0..<maxAttempts {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RakutenBooksError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return data
            }

            lastStatusCode = httpResponse.statusCode
            let isTransient = httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode)
            guard isTransient, attempt < maxAttempts - 1 else {
                throw RakutenBooksError.httpError(statusCode: httpResponse.statusCode)
            }

            // 楽天は約1req/秒のため、0.8秒から段階的に待って再試行する
            let delayNanos = UInt64(800_000_000) * UInt64(attempt + 1)
            #if DEBUG
            print("⏳ レート制限のため再試行 (attempt \(attempt + 1), status \(httpResponse.statusCode))")
            #endif
            try? await Task.sleep(nanoseconds: delayNanos)
        }
        throw RakutenBooksError.httpError(statusCode: lastStatusCode)
    }

    /// 書籍検索APIで発行形態（文庫・単行本・コミック等）を補完
    func enrichWithFormat(_ books: [RakutenBook]) async -> [RakutenBook] {
        let indicesNeedingFormat = books.enumerated().compactMap { index, book -> Int? in
            if let size = book.size, !size.isEmpty { return nil }
            guard !book.isbn.isEmpty else { return nil }
            return index
        }

        guard !indicesNeedingFormat.isEmpty else { return books }

        var enriched = books
        // 楽天は約1req/秒のレート制限があるため、同時実行数を抑えて
        // 検索（ページング）リクエストを 429 で妨げないようにする。
        let maxConcurrent = 4

        for chunkStart in stride(from: 0, to: indicesNeedingFormat.count, by: maxConcurrent) {
            // 先頭チャンク以外は少し間隔をあけてバーストを避ける
            if chunkStart > 0 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            let chunk = Array(indicesNeedingFormat[chunkStart..<min(chunkStart + maxConcurrent, indicesNeedingFormat.count)])
            await withTaskGroup(of: (Int, String?).self) { group in
                for index in chunk {
                    let isbn = books[index].isbn
                    group.addTask {
                        let format = await self.fetchFormatByISBN(isbn)
                        return (index, format)
                    }
                }

                for await (index, format) in group {
                    if let format, !format.isEmpty {
                        enriched[index] = enriched[index].withSize(format)
                    }
                }
            }
        }

        #if DEBUG
        let resolvedCount = enriched.filter { $0.displayFormat != nil }.count
        print("📚 発行形態補完: \(resolvedCount)/\(enriched.count)件")
        #endif

        return enriched
    }

    /// ISBNで書籍検索APIから発行形態を取得
    private func fetchFormatByISBN(_ isbn: String) async -> String? {
        if let cached = formatCache[isbn] {
            return cached
        }

        var components = URLComponents(string: proxyURL)
        components?.queryItems = [
            URLQueryItem(name: "endpoint", value: "book"),     // 書籍検索APIを指定
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hits", value: "1")
        ]

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let searchResponse = try JSONDecoder().decode(RakutenBooksBookSearchResponse.self, from: data)
            guard let size = searchResponse.Items.first?.Item.size, !size.isEmpty else {
                return nil
            }

            formatCache[isbn] = size
            return size
        } catch {
            #if DEBUG
            print("⚠️ 発行形態取得失敗 ISBN=\(isbn): \(error.localizedDescription)")
            #endif
            return nil
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
