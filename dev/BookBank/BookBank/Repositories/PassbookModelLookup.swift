import Foundation
import SwiftData

/// DTO の口座 id（uuid）から SwiftData の `Passbook` @Model を解決する（R4ステップ3ハイブリッド用）
@MainActor
enum PassbookModelLookup {
    static func fetch(id: String, context: ModelContext) -> Passbook? {
        let target = id
        let descriptor = FetchDescriptor<Passbook>(predicate: #Predicate { $0.uuid == target })
        return try? context.fetch(descriptor).first
    }
}
