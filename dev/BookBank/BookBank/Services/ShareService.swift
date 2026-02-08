//
//  ShareService.swift
//  BookBank
//
//  Created on 2026/02/02
//

import Foundation
import SwiftData

// MARK: - API Configuration

enum ShareAPIConfig {
    static let baseURL = "https://bookbank-share.vercel.app"
    static let listsEndpoint = "/api/lists"
}

// MARK: - API Request/Response Models

/// シェアAPIへのリクエストボディ
struct ShareListRequest: Encodable {
    let readingListId: String
    let title: String
    let description: String?
    let ownerName: String?
    let books: [ShareBookItem]
}

/// シェアする本の情報
struct ShareBookItem: Encodable {
    let title: String
    let author: String
    let imageURL: String?
    let priceAtRegistration: Int?
}

/// シェアAPIからのレスポンス
struct ShareListResponse: Decodable {
    let id: String
    let url: String
    let expiresAt: String?
}

// MARK: - Share Error

enum ShareError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .invalidResponse:
            return "サーバーからの応答が無効です"
        case .serverError(let code):
            return "サーバーエラー（コード: \(code)）"
        case .decodingError:
            return "データの解析に失敗しました"
        }
    }
}

// MARK: - Share Service

/// 読了リストをWeb共有するためのサービス
class ShareService {
    
    static let shared = ShareService()
    
    private init() {}
    
    /// 読了リストをシェアしてURLを取得
    /// - Parameter readingList: シェアする読了リスト
    /// - Returns: シェアページのURL
    func shareReadingList(_ readingList: ReadingList) async throws -> URL {
        // APIエンドポイントのURL作成
        guard let url = URL(string: ShareAPIConfig.baseURL + ShareAPIConfig.listsEndpoint) else {
            throw ShareError.invalidURL
        }
        
        // ReadingListをAPIリクエスト形式に変換
        let bookItems = readingList.books.map { book in
            ShareBookItem(
                title: book.title,
                author: book.author ?? "",
                imageURL: book.imageURL,
                priceAtRegistration: book.priceAtRegistration
            )
        }
        
        // persistentModelIDを文字列に変換
        let readingListId = "\(readingList.persistentModelID)"
        
        let requestBody = ShareListRequest(
            readingListId: readingListId,
            title: readingList.title,
            description: readingList.listDescription,
            ownerName: nil,  // 将来的にユーザー名を設定可能に
            books: bookItems
        )
        
        // リクエスト作成
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        // APIリクエスト実行
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShareError.networkError(error)
        }
        
        // HTTPレスポンスチェック
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ShareError.serverError(httpResponse.statusCode)
        }
        
        // レスポンスのデコード
        let decoder = JSONDecoder()
        let shareResponse: ShareListResponse
        do {
            shareResponse = try decoder.decode(ShareListResponse.self, from: data)
        } catch {
            throw ShareError.decodingError(error)
        }
        
        // URLに変換して返す
        guard let shareURL = URL(string: shareResponse.url) else {
            throw ShareError.invalidURL
        }
        
        return shareURL
    }
}
