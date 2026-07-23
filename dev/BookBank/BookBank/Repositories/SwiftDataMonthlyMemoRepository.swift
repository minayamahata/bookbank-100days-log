import Foundation
import OSLog
import SwiftData

@MainActor
final class SwiftDataMonthlyMemoRepository: MonthlyMemoRepository {
    private let context: ModelContext
    private let pulse: RepositoryChangePulse
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "MonthlyMemo"
    )

    init(context: ModelContext, pulse: RepositoryChangePulse) {
        self.context = context
        self.pulse = pulse
    }

    func observeMemo(year: Int, month: Int) -> AsyncStream<MonthlyMemoDTO?> {
        makeEquatingStream(pulse: pulse) { [weak self] in
            self?.fetchDTO(year: year, month: month)
        }
    }

    func saveMemo(year: Int, month: Int, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let existing = try fetchModel(year: year, month: month) {
                context.delete(existing)
            }
        } else {
            let memo: MonthlyMemo
            if let existing = try fetchModel(year: year, month: month) {
                memo = existing
            } else {
                memo = MonthlyMemo(year: year, month: month)
                context.insert(memo)
            }
            memo.text = trimmed
            memo.updatedAt = Date()
        }

        do {
            try context.save()
            pulse.notify()
        } catch {
            logger.error("月別メモの保存に失敗: year=\(year) month=\(month) error=\(error.localizedDescription, privacy: .public)")
            context.rollback()
            throw error
        }
    }

    // MARK: - Private

    private func fetchDTO(year: Int, month: Int) -> MonthlyMemoDTO? {
        guard let model = try? fetchModel(year: year, month: month) else { return nil }
        return ModelDTOMapping.monthlyMemoDTO(from: model)
    }

    private func fetchModel(year: Int, month: Int) throws -> MonthlyMemo? {
        let y = year
        let m = month
        let descriptor = FetchDescriptor<MonthlyMemo>(
            predicate: #Predicate { $0.year == y && $0.month == m }
        )
        return try context.fetch(descriptor).first
    }
}
