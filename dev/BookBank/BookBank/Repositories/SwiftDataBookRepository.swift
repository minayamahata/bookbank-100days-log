import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataBookRepository: BookRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "BookRepository"
    )

    init(context: ModelContext, pulse: RepositoryChangePulse) {
        self.context = context
        self.pulse = pulse
    }

    func observeBooks() -> AsyncStream<[BookDTO]> {
        makeEquatingStream(pulse: pulse) { [weak self] in
            self?.fetchSorted() ?? []
        }
    }

    func addBook(_ book: BookDTO, coverImageData: Data?) async throws {
        let passbook = try findPassbook(id: book.passbookId)
        let model = UserBook(
            title: book.title,
            author: book.author,
            isbn: book.isbn,
            publisher: book.publisher,
            publishedYear: book.publishedYear,
            seriesName: book.seriesName,
            price: book.price,
            imageURL: book.imageURL,
            coverImageData: coverImageData,
            bookFormat: book.bookFormat,
            pageCount: book.pageCount,
            source: book.source,
            memo: book.memo,
            isFavorite: book.isFavorite,
            passbook: passbook,
            currencyCode: book.currencyCode
        )
        // init が採番した uuid をDTOの id で上書き（呼び出し側が採番済みの場合）
        model.uuid = book.id
        model.priceAtRegistration = book.priceAtRegistration ?? book.price
        model.registeredAt = book.registeredAt
        model.createdAt = book.createdAt
        model.updatedAt = book.updatedAt
        context.insert(model)
        try saveAndNotify()
    }

    func updateBook(_ book: BookDTO) async throws {
        guard let model = try findBook(id: book.id) else {
            logger.error("updateBook: book not found id=\(book.id, privacy: .public)")
            return
        }
        let passbook = try findPassbook(id: book.passbookId)
        ModelDTOMapping.apply(book, to: model, passbook: passbook)
        try saveAndNotify()
    }

    func deleteBook(id: String) async throws {
        guard let model = try findBook(id: id) else { return }
        // 所属リストの bookIds から除去（設計メモ 4.4節）
        let lists = try context.fetch(FetchDescriptor<ReadingList>())
        for list in lists where list.bookIds.contains(id) {
            list.bookIds.removeAll { $0 == id }
        }
        context.delete(model)
        try saveAndNotify()
    }

    func loadCoverImage(bookId: String) async -> Data? {
        guard let model = try? findBook(id: bookId) else { return nil }
        return model.coverImageData
    }

    func updateCoverImage(bookId: String, data: Data?) async throws {
        guard let model = try findBook(id: bookId) else {
            logger.error("updateCoverImage: book not found id=\(bookId, privacy: .public)")
            return
        }
        model.coverImageData = data
        try saveAndNotify()
    }

    // MARK: - Private

    private func fetchSorted() -> [BookDTO] {
        var descriptor = FetchDescriptor<UserBook>(
            sortBy: [
                SortDescriptor(\.registeredAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.passbook]
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(ModelDTOMapping.bookDTO(from:))
    }

    private func findBook(id: String) throws -> UserBook? {
        let target = id
        let descriptor = FetchDescriptor<UserBook>(
            predicate: #Predicate { $0.uuid == target }
        )
        return try context.fetch(descriptor).first
    }

    private func findPassbook(id: String?) throws -> Passbook? {
        guard let id else { return nil }
        let target = id
        let descriptor = FetchDescriptor<Passbook>(
            predicate: #Predicate { $0.uuid == target }
        )
        return try context.fetch(descriptor).first
    }

    private func saveAndNotify() throws {
        do {
            try context.save()
            pulse.notify()
        } catch {
            logger.error("BookRepository save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            throw error
        }
    }
}
