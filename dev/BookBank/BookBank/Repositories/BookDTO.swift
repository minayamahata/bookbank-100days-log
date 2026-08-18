import Foundation

/// 書籍のView向けDTO（設計メモ 3.3節）。`coverImageData` は含めない（前提4）。
struct BookDTO: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var title: String
    var author: String?
    var isbn: String?
    var publisher: String?
    var publishedYear: Int?
    var seriesName: String?
    var price: Int?
    var imageURL: String?
    var bookFormat: String?
    var pageCount: Int?
    var source: BookSource
    var memo: String?
    var isFavorite: Bool
    var priceAtRegistration: Int?
    var currencyCode: String?
    var registeredAt: Date
    var rereads: [RereadRecord] = []
    var createdAt: Date
    var updatedAt: Date
    /// 所属口座の uuid（リレーションの片方向参照）
    var passbookId: String?
    /// ローカル表紙画像の有無（`coverImageData` の nil/空判定。URLは見ない）
    var hasCoverImage: Bool
}

extension BookDTO {
    var displayAuthor: String {
        author ?? ""
    }

    var coverImageURL: String? {
        BookCoverImageURL.normalized(imageURL)
    }

    var storedCurrency: AppCurrency {
        AppCurrency(code: currencyCode) ?? .jpy
    }

    @MainActor
    func displayAmount(in target: AppCurrency, exchangeRates: ExchangeRateService) -> Int? {
        guard let amount = priceAtRegistration else { return nil }
        return exchangeRates.convert(amount, from: storedCurrency, to: target)
    }

    /// 初回登録日＋各再読日
    var allReadingDates: [Date] {
        [registeredAt] + rereads.map(\.date)
    }

    /// 総読書回数（初回1 + 再読件数）
    var readCount: Int {
        1 + rereads.count
    }

    /// 最も新しい読書日
    var latestReadDate: Date {
        rereads.map(\.date).max().map { max($0, registeredAt) } ?? registeredAt
    }
}

extension Collection where Element == BookDTO {
    @MainActor
    func totalDisplayAmount(in target: AppCurrency, exchangeRates: ExchangeRateService) -> Int {
        reduce(0) { partial, book in
            partial + (book.displayAmount(in: target, exchangeRates: exchangeRates) ?? 0)
        }
    }
}
