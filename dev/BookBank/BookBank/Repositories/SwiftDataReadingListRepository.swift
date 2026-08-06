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
        let books = try resolveMembership(of: list)
        let model = ReadingList(title: list.title, listDescription: list.description)
        model.uuid = list.id
        model.colorIndex = list.colorIndex
        model.bookIds = books.map(\.uuid)
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
        let books = try resolveMembership(of: list)
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
        do {
            return try context.fetch(descriptor).first
        } catch {
            // 呼び出し元Viewは `try?` / `catch { return }` で握り潰すため、
            // ここで記録しないとストア異常が一切観測できない（設計メモ 4.5節）
            logger.error(
                "find: fetch failed id=\(id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// DTO が主張する所属本を、**読み側と同じ寛容さ**で確定する（レビュー S5-1）。
    ///
    /// 読み（`ModelDTOMapping.readingListDTO` → `ReadingListOrdering.resolve`）は
    /// `bookIds` に載っていない `books` のメンバーを末尾へ足す。書きが `bookIds` だけを見ると、
    /// その寛容さで拾われた本が保存のたびに刈られる（`bookIds` が空なら所属が丸ごと消える）。
    /// 旧実装はリレーションが所属の正で `bookIds` は並び順にすぎなかったため、この経路が無かった。
    ///
    /// 和を取る相手が **DTO の `books` であって永続化済みの `model.books` ではない**のが要点。
    /// 除去操作は `ReadingListDTO.replacingBooks` が `bookIds` と `books` を同時に更新するので、
    /// 永続側と和を取ると外したはずの本が毎回戻り、本の除去が永久に効かなくなる。
    private func resolveMembership(of list: ReadingListDTO) throws -> [UserBook] {
        var requested = list.bookIds
        var seen = Set(requested)
        for book in list.books where !seen.contains(book.id) {
            requested.append(book.id)
            seen.insert(book.id)
        }
        if requested.count != list.bookIds.count {
            logger.notice(
                "resolveMembership: bookIds が books を網羅していない list=\(list.id, privacy: .public) bookIds=\(list.bookIds.count, privacy: .public) books=\(list.books.count, privacy: .public) 追補=\(requested.count - list.bookIds.count, privacy: .public)"
            )
        }
        return try resolveBooks(ids: requested)
    }

    private func resolveBooks(ids: [String]) throws -> [UserBook] {
        guard !ids.isEmpty else { return [] }
        let targets = Set(ids)
        let descriptor = FetchDescriptor<UserBook>(
            predicate: #Predicate { targets.contains($0.uuid) }
        )
        let matched: [UserBook]
        do {
            matched = try context.fetch(descriptor)
        } catch {
            // fetch失敗はストア側の異常であり、該当なしとは原因が異なるため別メッセージで記録する
            // （旧 `BookModelLookup` と同じ区別）。ただし旧は `[]` を返して保存を続けていたのに対し、
            // ここは throw して保存自体を止める（4.5節「失敗を成功に見せない」）
            logger.error(
                "resolveBooks: fetch failed requested=\(ids.count, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
        let byUUID = Dictionary(
            matched.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolved = ids.compactMap { byUUID[$0] }
        if resolved.count != ids.count {
            // 該当なし: fetch自体は成功している（削除済み・uuid不整合が疑わしい）。解決できない id は落とす
            let missing = ids.filter { byUUID[$0] == nil }
            logger.error(
                "resolveBooks: not found requested=\(ids.count, privacy: .public) missing=\(missing.count, privacy: .public) ids=\(missing.joined(separator: ","), privacy: .public)"
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
