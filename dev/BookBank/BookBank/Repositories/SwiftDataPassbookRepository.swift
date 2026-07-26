import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataPassbookRepository: PassbookRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    /// 所属本の削除を `BookRepository` の削除セマンティクスへ委譲するための参照（設計メモ 4.4節）
    private let books: SwiftDataBookRepository
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "PassbookRepository"
    )

    /// 直近に fetch した口座一覧の同期スナップショット。
    ///
    /// `.task` でのストリーム購読は最初の body 評価より後に走るため、口座色を解決する画面は
    /// 初回フレームだけ色が出ない（ステップ3で `@Model` フォールバックにより回避していた挙動）。
    /// ステップ4で `@Model` を View から外すにあたり、その役目をこのスナップショットへ移す。
    /// - Important: `LocalCoverDataCache` と同じく **R4（SwiftData期）限定の暫定配置**であり、
    ///   R6のスナップショットリスナー実装では同期読みできないため解体が要る（設計メモ 4.6節）。
    private(set) var latestSnapshot: [PassbookDTO] = []

    init(context: ModelContext, pulse: RepositoryChangePulse, books: SwiftDataBookRepository) {
        self.context = context
        self.pulse = pulse
        self.books = books
    }

    func observePassbooks() -> AsyncStream<[PassbookDTO]> {
        makeEquatingStream(pulse: pulse) { [weak self] in
            self?.fetchSorted() ?? []
        }
    }

    func addPassbook(_ passbook: PassbookDTO) async throws {
        let model = Passbook(
            name: passbook.name,
            type: passbook.type,
            sortOrder: passbook.sortOrder,
            isActive: passbook.isActive
        )
        model.uuid = passbook.id
        model.colorIndex = passbook.colorIndex
        model.customColorHex = passbook.customColorHex
        model.createdAt = passbook.createdAt
        model.updatedAt = passbook.updatedAt
        context.insert(model)
        try saveAndNotify()
    }

    func updatePassbook(_ passbook: PassbookDTO) async throws {
        guard let model = try find(id: passbook.id) else {
            logger.error("updatePassbook: not found id=\(passbook.id, privacy: .public)")
            return
        }
        ModelDTOMapping.apply(passbook, to: model)
        try saveAndNotify()
    }

    func deletePassbook(id: String) async throws {
        guard let model = try find(id: id) else { return }
        // 所属本を明示削除してから口座を削除（設計メモ 4.4節）。
        // 削除手順は `deleteBook` と同一のものを再利用し、所属リストの bookIds も掃除する
        // （ステップ3時点の非対称の解消・設計メモ 4.4節の申し送り）。
        let deletedBookIds = try books.deleteBooks(model.userBooks)
        context.delete(model)
        try saveAndNotify()
        // 表紙キャッシュは永続化成功後にのみ捨てる（レビュー S4-1）
        books.invalidateCoverCache(ids: deletedBookIds)
    }

    // MARK: - Private

    private func fetchSorted() -> [PassbookDTO] {
        let descriptor = FetchDescriptor<Passbook>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        let dtos = models.map(ModelDTOMapping.passbookDTO(from:))
        latestSnapshot = dtos
        return dtos
    }

    private func find(id: String) throws -> Passbook? {
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
            logger.error("PassbookRepository save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            throw error
        }
    }
}
