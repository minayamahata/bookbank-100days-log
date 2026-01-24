//
//  RakutenBooksModels.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import Foundation

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
            seriesName: seriesName,
            price: itemPrice,
            imageURL: largeImageUrl ?? mediumImageUrl,
            bookFormat: size,
            pageCount: extractPageCount(),
            source: .api,
            passbook: passbook
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
