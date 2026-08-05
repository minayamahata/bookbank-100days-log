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

    /// 直近に fetch した書籍一覧の同期スナップショット。
    ///
    /// `.task` によるストリーム購読は最初の body 評価より後に走るため、これが無いと
    /// 一覧・空状態UI・件数が初回フレームだけ「0件」で描かれる（設計メモ 5.1節の穴）。
    /// View は `loaded ?? latestSnapshot` の形で初回フレームを埋める。
    /// - Important: `LocalCoverDataCache` と同じく **R4（SwiftData期）限定の暫定配置**であり、
    ///   R6のスナップショットリスナー実装では同期読みできないため解体が要る（設計メモ 4.6節）。
    private(set) var latestSnapshot: [BookDTO] = []

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
        // 口座が引けないまま passbook: nil で保存すると「別の口座に入る」失敗モードになる。
        // 旧実装（@Model 直参照）は保存しなかったので、無保存へ戻す（レビュー S4-11）
        let passbook = try requirePassbook(id: book.passbookId, operation: "addBook")
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
        // 規約: LocalCoverDataCache は永続化成功後にのみ触る（レビュー S4-1 / S4-16）
        applyCoverCache(bookId: book.id, data: coverImageData)
    }

    func updateBook(_ book: BookDTO, cover: CoverImageUpdate) async throws {
        guard let model = try findBook(id: book.id) else {
            // not-found は並行削除を保証しないため握り潰さない（2026-07-26 オーナー判断）。
            // 「閉じてよいか」の判断は View の catch が持つ（設計メモ 4.5節）
            logger.error("updateBook: book not found id=\(book.id, privacy: .public)")
            throw RepositoryError.bookNotFound(book.id)
        }
        // 更新でも、指定された口座が引けないなら「意図しない nil 化（総合口座送り）」を許さない
        let passbook = try requirePassbook(id: book.passbookId, operation: "updateBook")
        ModelDTOMapping.apply(book, to: model, passbook: passbook)
        if case .replace(let data) = cover {
            model.coverImageData = data
        }
        // 書誌と表紙を1回の save で書く（レビュー S4-12: 部分永続化の回避）
        try saveAndNotify()
        if case .replace(let data) = cover {
            applyCoverCache(bookId: book.id, data: data)
        }
    }

    func deleteBook(id: String) async throws {
        guard let model = try findBook(id: id) else { return }
        let deletedIds = try deleteBooks([model])
        try saveAndNotify()
        invalidateCoverCache(ids: deletedIds)
    }

    /// 本の削除セマンティクス本体（設計メモ 4.4節）。
    /// 「本の削除＋所属リストの `bookIds` からの除去」を1か所に閉じ込め、
    /// `deletePassbook`（口座ごと削除）からも同じ手順を再利用する（ステップ3申し送り）。
    /// - Note: save / notify と表紙キャッシュの破棄は**呼び出し側が保存成功後に**行う
    ///   （複数本の削除を1トランザクションにまとめるため・レビュー S4-1）。
    /// - Returns: 削除した本の uuid（保存成功後にキャッシュを破棄するために使う）
    @discardableResult
    func deleteBooks(_ models: [UserBook]) throws -> [String] {
        guard !models.isEmpty else { return [] }
        let ids = models.map(\.uuid)
        let idSet = Set(ids)
        let lists = try context.fetch(FetchDescriptor<ReadingList>())
        for list in lists where list.bookIds.contains(where: { idSet.contains($0) }) {
            list.bookIds.removeAll { idSet.contains($0) }
        }
        for model in models {
            context.delete(model)
        }
        return ids
    }

    /// 永続化成功後に表紙キャッシュを捨てる（`deletePassbook` からも使う）
    func invalidateCoverCache(ids: [String]) {
        for id in ids {
            LocalCoverDataCache.shared.invalidate(bookId: id)
        }
    }

    func loadCoverImage(bookId: String) async -> Data? {
        guard let model = try? findBook(id: bookId) else { return nil }
        return model.coverImageData
    }

    func updateCoverImage(bookId: String, data: Data?) async throws {
        guard let model = try findBook(id: bookId) else {
            // updateBook と同じ契約（更新系の not-found は throw）
            logger.error("updateCoverImage: book not found id=\(bookId, privacy: .public)")
            throw RepositoryError.bookNotFound(bookId)
        }
        model.coverImageData = data
        try saveAndNotify()
        // 永続化に成功してから張り替える（失敗時に古い表紙が残るのは正しい＝レビュー S4-1）
        applyCoverCache(bookId: bookId, data: data)
    }

    // MARK: - Private

    /// 表紙キャッシュの投入／破棄。**必ず `saveAndNotify()` の成功後に呼ぶこと**
    private func applyCoverCache(bookId: String, data: Data?) {
        if let data, !data.isEmpty {
            LocalCoverDataCache.shared.setData(data, for: bookId)
        } else {
            LocalCoverDataCache.shared.invalidate(bookId: bookId)
        }
    }

    /// `passbookId` の指定があるのに引けない場合は throw する（レビュー S4-11）。
    /// `passbookId == nil`（総合口座＝未割当）は正常系なので nil を返す
    private func requirePassbook(id: String?, operation: String) throws -> Passbook? {
        guard let id else { return nil }
        guard let passbook = try findPassbook(id: id) else {
            logger.error(
                "\(operation, privacy: .public): passbook not found id=\(id, privacy: .public) — 保存を中止"
            )
            throw RepositoryError.passbookNotFound(id)
        }
        return passbook
    }

    private func fetchSorted() -> [BookDTO] {
        var descriptor = FetchDescriptor<UserBook>(
            sortBy: [
                SortDescriptor(\.registeredAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.passbook]
        let models = (try? context.fetch(descriptor)) ?? []
        primeLocalCoverCache(models)
        let dtos = models.map(ModelDTOMapping.bookDTO(from:))
        latestSnapshot = dtos
        return dtos
    }

    /// 表紙バイナリを `LocalCoverDataCache` へ同期投入する（R4暫定・R6で解体。設計メモ 4.6節）。
    ///
    /// `loadCoverImage` は `async` のため View から呼ぶと初回フレームに画像が出ない。
    /// DTO を組み立てるこのターンでキャッシュを満たしておくことで、View 側は `init` で
    /// 同期ヒットでき、現行（`UserBook.coverUIImage` の同期読み）と同じ見えになる。
    ///
    /// - Note: `SwiftDataReadingListRepository` も `ReadingListDTO.books` を組み立てる際に呼ぶ
    ///   （リスト系Viewが `observeBooks()` を購読しないため・ステップ5）。
    func primeLocalCoverCache(_ models: [UserBook]) {
        for model in models where !LocalCoverDataCache.shared.hasData(for: model.uuid) {
            guard let data = model.coverImageData, !data.isEmpty else { continue }
            LocalCoverDataCache.shared.setData(data, for: model.uuid)
        }
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
