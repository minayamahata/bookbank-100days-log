import Foundation
import SwiftData
import UIKit

/// ユーザーが登録した書籍モデル
/// 書籍マスター情報とユーザー固有情報を統合
@Model
final class UserBook {

    // MARK: - Book Master Properties（書籍マスター情報）

    /// 書籍タイトル
    var title: String

    /// 著者名
    var author: String?

    /// ISBN（APIから取得した場合）
    var isbn: String?

    /// 出版社
    var publisher: String?

    /// 出版年
    var publishedYear: Int?
    
    /// シリーズ・レーベル名
    var seriesName: String?

    /// 定価（書籍の公式価格）
    var price: Int?

    /// 表紙画像URL（大サイズ - リスト表示では縮小表示）
    var imageURL: String?
    
    /// 手動登録時の表紙画像データ（ライブラリ選択またはカメラ撮影）
    @Attribute(.externalStorage)
    var coverImageData: Data?
    
    /// 発行形態（例：単行本、文庫本、電子書籍など）
    var bookFormat: String?
    
    /// ページ数
    var pageCount: Int?

    /// 登録元
    var source: BookSource

    // MARK: - User-specific Properties（ユーザー固有情報）

    /// ユーザーメモ
    var memo: String?

    /// お気に入りフラグ
    var isFavorite: Bool

    /// 登録時点の価格（資産計算用）
    /// 登録時に price からコピーされる
    var priceAtRegistration: Int?

    /// 登録時点の通貨コード（ISO 4217、例: JPY）
    var currencyCode: String?

    /// 書籍登録日時（ユーザーが登録した日、編集可能）
    var registeredAt: Date

    /// 作成日時
    var createdAt: Date

    /// 更新日時
    var updatedAt: Date

    // MARK: - Relationships

    /// 所属口座（nil = 総合口座に自動割当）
    var passbook: Passbook?
    
    /// 所属する読了リスト（逆参照）
    @Relationship(inverse: \ReadingList.books)
    var readingLists: [ReadingList]?

    // MARK: - Initialization

    init(
        title: String,
        author: String? = nil,
        isbn: String? = nil,
        publisher: String? = nil,
        publishedYear: Int? = nil,
        seriesName: String? = nil,
        price: Int? = nil,
        imageURL: String? = nil,
        coverImageData: Data? = nil,
        bookFormat: String? = nil,
        pageCount: Int? = nil,
        source: BookSource = .manual,
        memo: String? = nil,
        isFavorite: Bool = false,
        passbook: Passbook? = nil,
        currencyCode: String? = nil
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.publisher = publisher
        self.publishedYear = publishedYear
        self.seriesName = seriesName
        self.price = price
        self.imageURL = imageURL
        self.coverImageData = coverImageData
        self.bookFormat = bookFormat
        self.pageCount = pageCount
        self.source = source
        self.memo = memo
        self.isFavorite = isFavorite
        self.priceAtRegistration = price
        self.currencyCode = currencyCode
        self.registeredAt = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.passbook = passbook
    }
}

// MARK: - BookSource

/// 書籍の登録元
enum BookSource: String, Codable, CaseIterable {
    /// API検索から登録
    case api
    /// 手動入力で登録
    case manual
}

// MARK: - Computed Properties

extension UserBook {
    /// 表示用の著者名（未設定の場合は空文字）
    var displayAuthor: String {
        author ?? ""
    }

    /// 表示に使える表紙URL（楽天の noimage プレースホルダーは除外）
    var coverImageURL: String? {
        BookCoverImageURL.normalized(imageURL)
    }

    /// 表示用の価格文字列（レガシー・換算表示は FormattedPriceText を使用）
    var displayPrice: String? {
        guard let price = priceAtRegistration else { return nil }
        return "¥\(price.formatted())"
    }

    /// ISBN-13形式かどうか
    var hasISBN13: Bool {
        guard let isbn = isbn else { return false }
        return isbn.count == 13
    }
    
    /// 表紙画像があるかどうか（URL or ローカルデータ）
    var hasCoverImage: Bool {
        if let data = coverImageData, !data.isEmpty { return true }
        return coverImageURL != nil
    }
    
    /// ローカル保存の表紙画像をUIImageとして取得
    var coverUIImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }

    /// 保存されている通貨（未設定は JPY）
    var storedCurrency: AppCurrency {
        AppCurrency(code: currencyCode) ?? .jpy
    }

    /// 表示通貨に換算した金額
    @MainActor
    func displayAmount(in target: AppCurrency, exchangeRates: ExchangeRateService) -> Int? {
        guard let amount = priceAtRegistration else { return nil }
        return exchangeRates.convert(amount, from: storedCurrency, to: target)
    }
}

extension Collection where Element == UserBook {
    /// 表示通貨での合計
    @MainActor
    func totalDisplayAmount(in target: AppCurrency, exchangeRates: ExchangeRateService) -> Int {
        reduce(0) { partial, book in
            partial + (book.displayAmount(in: target, exchangeRates: exchangeRates) ?? 0)
        }
    }
}
