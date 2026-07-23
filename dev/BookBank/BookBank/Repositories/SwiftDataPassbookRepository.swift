import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataPassbookRepository: PassbookRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "PassbookRepository"
    )

    init(context: ModelContext, pulse: RepositoryChangePulse) {
        self.context = context
        self.pulse = pulse
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
        // 所属本を明示削除してから口座を削除（設計メモ 4.4節）
        let books = model.userBooks
        for book in books {
            context.delete(book)
        }
        context.delete(model)
        try saveAndNotify()
    }

    // MARK: - Private

    private func fetchSorted() -> [PassbookDTO] {
        let descriptor = FetchDescriptor<Passbook>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(ModelDTOMapping.passbookDTO(from:))
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
