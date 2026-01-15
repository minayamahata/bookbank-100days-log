//
//  RakutenBooksModels.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import Foundation

// MARK: - レスポンスのルート構造

/// 楽天Books API検索のレスポンス
struct RakutenBooksSearchResponse: Codable {
    let count: Int
    let page: Int
    let first: Int
    let last: Int
    let hits: Int
    let carrier: Int
    let pageCount: Int
    let Items: [RakutenBookItem]
}

// MARK: - 書籍アイテム

/// 楽天Booksの1件の書籍データ
struct RakutenBookItem: Codable {
    let Item: RakutenBook
}

/// 楽天Booksの書籍詳細
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
    
    /// 商品説明（長い）
    var itemDescription: String? {
        itemCaption.isEmpty ? nil : itemCaption
    }
    
    /// 出版年を取得（salesDateから）
    var publishedYear: Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        if let date = formatter.date(from: salesDate) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        // "yyyy年MM月"形式も試す
        formatter.dateFormat = "yyyy年MM月"
        if let date = formatter.date(from: salesDate) {
            let calendar = Calendar.current
            return calendar.component(.year, from: date)
        }
        
        return nil
    }
}

// MARK: - UserBookへの変換

extension RakutenBook {
    /// RakutenBookからUserBookを生成
    func toUserBook(passbook: Passbook) -> UserBook {
        UserBook(
            title: title,
            author: author.isEmpty ? nil : author,
            isbn: isbn.isEmpty ? nil : isbn,
            publisher: publisherName.isEmpty ? nil : publisherName,
            publishedYear: publishedYear,
            price: itemPrice,
            thumbnailURL: mediumImageUrl,
            source: .api,
            passbook: passbook
        )
    }
}
