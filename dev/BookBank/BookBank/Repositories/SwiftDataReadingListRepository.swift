import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataReadingListRepository: ReadingListRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    /// `ReadingListDTO.books` の表紙をキャッシュへ同期投入するために借りる（設計メモ 4.6節）
    private let books: SwiftDataBookRepository
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "ReadingListRepository"
    )

    /// 直近に fetch したリスト一覧の同期スナップショット。
    /// 用途と不変条件は `SwiftDataBookRepository.latestSnapshot` と同じ（設計メモ 4.6節）。
    /// **R6で解体が要る暫定配置**である点も同じ。
    private(set) var latestSnapshot: [ReadingListDTO] = []

    init(context: ModelContext, pulse: RepositoryChangePulse, books: SwiftDataBookRepository) {
        self.context = context
        self.pulse = pulse
        self.books = books
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
            // 更新系の not-found は握り潰さない（設計メモ 4.5節・本・口座と同じ契約）
            logger.error("updateReadingList: not found id=\(list.id, privacy: .public)")
            throw RepositoryError.readingListNotFound(list.id)
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
        // リスト系Viewは `observeBooks()` を購読しないため、ここで投入しないと
        // `LocalCoverImage` が同期ヒットできず手動表紙が初回フレームで出ない（設計メモ 4.6節）
        books.primeLocalCoverCache(models.flatMap(\.books))
        let dtos = models.map(ModelDTOMapping.readingListDTO(from:))
        latestSnapshot = dtos
        return dtos
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
        let targets = Set(ids)
        let descriptor = FetchDescriptor<UserBook>(
            predicate: #Predicate { targets.contains($0.uuid) }
        )
        let matched = try context.fetch(descriptor)
        let byUUID = Dictionary(
            matched.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolved = ids.compactMap { byUUID[$0] }
        if resolved.count != ids.count {
            // 解決できなかった id は落とす（削除済み・uuid不整合）。旧 `BookModelLookup` と同じ観測点
            let missing = ids.filter { byUUID[$0] == nil }
            logger.error(
                "resolveBooks: not found requested=\(ids.count, privacy: .public) missing=\(missing.joined(separator: ","), privacy: .public)"
            )
        }
        return resolved
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
