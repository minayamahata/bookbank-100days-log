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
    let bgColor: String?
    let books: [ShareBookItem]
    /// 表示通貨に換算した合計（最小通貨単位）
    let totalValue: Int
    /// 合計値の通貨コード（ISO 4217）
    let totalCurrencyCode: String
}

/// シェアする本の情報
struct ShareBookItem: Encodable {
    let title: String
    let author: String
    let imageURL: String?
    /// 登録時点の価格（その本の通貨の最小単位）
    let priceAtRegistration: Int?
    /// 価格の通貨コード（ISO 4217）。未設定は JPY 相当
    let currencyCode: String?
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
    /// - Parameters:
    ///   - readingList: シェアする読了リスト
    ///   - displayCurrency: 合計値の換算先（アプリの表示通貨）
    ///   - totalValue: 表示通貨に換算済みの合計（最小通貨単位）。呼び出し元で `totalDisplayAmount` により算出する
    /// - Returns: シェアページのURL
    func shareReadingList(
        _ readingList: ReadingList,
        displayCurrency: AppCurrency,
        totalValue: Int
    ) async throws -> URL {
        // APIエンドポイントのURL作成
        guard let url = URL(string: ShareAPIConfig.baseURL + ShareAPIConfig.listsEndpoint) else {
            throw ShareError.invalidURL
        }
        
        // ReadingListをAPIリクエスト形式に変換
        let bookItems = readingList.orderedBooks.map { book in
            ShareBookItem(
                title: book.title,
                author: book.author ?? "",
                imageURL: book.coverImageURL,
                priceAtRegistration: book.priceAtRegistration,
                currencyCode: book.storedCurrency.code
            )
        }
        
        // persistentModelIDを文字列に変換
        let readingListId = "\(readingList.persistentModelID)"
        
        // colorIndexをHEXカラー文字列に変換
        let bgColorHex = PassbookColor.hexString(for: readingList.colorIndex ?? 0)
        
        let requestBody = ShareListRequest(
            readingListId: readingListId,
            title: readingList.title,
            description: readingList.listDescription,
            ownerName: nil,  // 将来的にユーザー名を設定可能に
            bgColor: bgColorHex,
            books: bookItems,
            totalValue: totalValue,
            totalCurrencyCode: displayCurrency.code
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
