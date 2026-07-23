import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataReadingListRepository: ReadingListRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "ReadingListRepository"
    )

    init(context: ModelContext, pulse: RepositoryChangePulse) {
        self.context = context
        self.pulse = pulse
    }

    func observeReadingLists() -> AsyncStream<[ReadingListDTO]> {
        makeEquatingStream(pulse: pulse) { [weak self] in
            self?.fetchSorted() ?? []
        }
    }

    func addReadingList(_ list: ReadingListDTO) async throws {
        let books = try resolveBooks(ids: list.bookIds)
        let model = ReadingList(title: list.title, listDescription: list.description)
        model.uuid = list.id
        model.colorIndex = list.colorIndex
        model.bookIds = list.bookIds
        model.books = books
        model.createdAt = list.createdAt
        model.updatedAt = list.updatedAt
        context.insert(model)
        try saveAndNotify()
    }

    func updateReadingList(_ list: ReadingListDTO) async throws {
        guard let model = try find(id: list.id) else {
            logger.error("updateReadingList: not found id=\(list.id, privacy: .public)")
            return
        }
        let books = try resolveBooks(ids: list.bookIds)
        ModelDTOMapping.apply(list, to: model, books: books)
        try saveAndNotify()
    }

    func deleteReadingList(id: String) async throws {
        guard let model = try find(id: id) else { return }
        context.delete(model)
        try saveAndNotify()
    }

    // MARK: - Private

    private func fetchSorted() -> [ReadingListDTO] {
        var descriptor = FetchDescriptor<ReadingList>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.books]
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(ModelDTOMapping.readingListDTO(from:))
    }

    private func find(id: String) throws -> ReadingList? {
        let target = id
        let descriptor = FetchDescriptor<ReadingList>(
            predicate: #Predicate { $0.uuid == target }
        )
        return try context.fetch(descriptor).first
    }

    private func resolveBooks(ids: [String]) throws -> [UserBook] {
        guard !ids.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<UserBook>())
        let byUUID = Dictionary(
            all.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { byUUID[$0] }
    }

    private func saveAndNotify() throws {
        do {
            try context.save()
            pulse.notify()
        } catch {
            logger.error("ReadingListRepository save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            throw error
        }
    }
}
