import Foundation
import SwiftData

/// `@Model` → DTO 変換（リポジトリ実装内に閉じる・設計メモ 3.4節）
@MainActor
enum ModelDTOMapping {
    static func bookDTO(from model: UserBook) -> BookDTO {
        BookDTO(
            id: model.uuid,
            title: model.title,
            author: model.author,
            isbn: model.isbn,
            publisher: model.publisher,
            publishedYear: model.publishedYear,
            seriesName: model.seriesName,
            price: model.price,
            imageURL: model.imageURL,
            bookFormat: model.bookFormat,
            pageCount: model.pageCount,
            source: model.source,
            memo: model.memo,
            isFavorite: model.isFavorite,
            priceAtRegistration: model.priceAtRegistration,
            currencyCode: model.currencyCode,
            registeredAt: model.registeredAt,
            rereads: model.rereads ?? [],
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            passbookId: model.passbook?.uuid,
            hasCoverImage: {
                if let data = model.coverImageData, !data.isEmpty { return true }
                return false
            }()
        )
    }

    static func apply(_ dto: BookDTO, to model: UserBook, passbook: Passbook?) {
        model.title = dto.title
        model.author = dto.author
        model.isbn = dto.isbn
        model.publisher = dto.publisher
        model.publishedYear = dto.publishedYear
        model.seriesName = dto.seriesName
        model.price = dto.price
        model.imageURL = dto.imageURL
        model.bookFormat = dto.bookFormat
        model.pageCount = dto.pageCount
        model.source = dto.source
        model.memo = dto.memo
        model.isFavorite = dto.isFavorite
        model.priceAtRegistration = dto.priceAtRegistration
        model.currencyCode = dto.currencyCode
        model.registeredAt = dto.registeredAt
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
        model.passbook = passbook
        // coverImageData / uuid / rereads はここでは触らない
        // （uuidは不変・画像は専用API・再読は専用API。古いDTOの updateBook で履歴を消さない）
    }

    static func passbookDTO(from model: Passbook) -> PassbookDTO {
        PassbookDTO(
            id: model.uuid,
            name: model.name,
            type: model.type,
            sortOrder: model.sortOrder,
            isActive: model.isActive,
            colorIndex: model.colorIndex,
            customColorHex: model.customColorHex,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    static func apply(_ dto: PassbookDTO, to model: Passbook) {
        model.name = dto.name
        model.type = dto.type
        model.sortOrder = dto.sortOrder
        model.isActive = dto.isActive
        model.colorIndex = dto.colorIndex
        model.customColorHex = dto.customColorHex
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func readingListDTO(from model: ReadingList) -> ReadingListDTO {
        let orderedModels = ReadingListOrdering.resolve(
            bookIds: model.bookIds,
            books: model.books,
            uuid: { $0.uuid }
        )
        return ReadingListDTO(
            id: model.uuid,
            title: model.title,
            description: model.listDescription,
            colorIndex: model.colorIndex,
            bookIds: model.bookIds,
            books: orderedModels.map { bookDTO(from: $0) },
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    /// `bookIds` は `dto.bookIds` ではなく**確定した所属（`books`）から書く**（レビュー S5-1）。
    /// 呼び出し側（`SwiftDataReadingListRepository.resolveMembership`）が読み側と同じ寛容さで
    /// 所属を確定しているため、ここで両者を一致させておけば「`bookIds` が `books` を網羅しない」
    /// 状態は書き込みのたびに解消される。解決できなかった id（削除済みの本）も同時に落ちる
    static func apply(_ dto: ReadingListDTO, to model: ReadingList, books: [UserBook]) {
        model.title = dto.title
        model.listDescription = dto.description
        model.colorIndex = dto.colorIndex
        model.bookIds = books.map(\.uuid)
        model.books = books
        model.createdAt = dto.createdAt
        model.updatedAt = dto.updatedAt
    }

    static func monthlyMemoDTO(from model: MonthlyMemo) -> MonthlyMemoDTO {
        MonthlyMemoDTO(
            year: model.year,
            month: model.month,
            text: model.text,
            updatedAt: model.updatedAt
        )
    }
}
