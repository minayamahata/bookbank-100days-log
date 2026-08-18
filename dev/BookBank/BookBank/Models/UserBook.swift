import Foundation
import SwiftData

/// ユーザーが登録した書籍モデル
/// 書籍マスター情報とユーザー固有情報を統合
@Model
final class UserBook {

    // MARK: - Identity

    /// 安定ID（UUID文字列）。R3で追加したFirestore docID用の「眠った土台」。
    /// R6では bookId＝uuid・表紙画像のStorageパス users/{uid}/covers/{bookId}.jpg にも使う（設計メモ 3.2）。
    /// R3ではどのViewからも参照されない。既存行の一意性は UUIDBackfillMigration が保証する（設計メモ 4.2）。
    var uuid: String = UUID().uuidString

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

    /// 再読履歴。nil = 履歴なし（旧ストアの軽量移行後も nil）。バックフィルしない。
    var rereads: [RereadRecord]? = nil

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
        self.uuid = UUID().uuidString
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

// MARK: - RereadRecord

/// 再読1件。別 `@Model` にはせず、`UserBook.rereads` の Codable 配列要素として持つ。
struct RereadRecord: Codable, Hashable, Sendable {
    /// UUID文字列。occurrence の安定IDにも使う
    var id: String
    /// 再読日
    var date: Date

    init(id: String = UUID().uuidString, date: Date) {
        self.id = id
        self.date = date
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
}
