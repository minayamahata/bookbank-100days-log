import Foundation
import OSLog
import SwiftData

/// DTO の口座 id（uuid）から SwiftData の `Passbook` @Model を解決する（R4ステップ3ハイブリッド用）
@MainActor
enum PassbookModelLookup {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "PassbookModelLookup"
    )

    static func fetch(id: String, context: ModelContext) -> Passbook? {
        let target = id
        let descriptor = FetchDescriptor<Passbook>(predicate: #Predicate { $0.uuid == target })
        do {
            let results = try context.fetch(descriptor)
            if let match = results.first {
                return match
            }
            logger.error("PassbookModelLookup: not found id=\(id, privacy: .public)")
            return nil
        } catch {
            logger.error(
                "PassbookModelLookup: fetch failed id=\(id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
