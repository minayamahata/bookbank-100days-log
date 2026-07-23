import Foundation

/// 月別メモのView向けDTO（設計メモ 3.3節）
struct MonthlyMemoDTO: Equatable, Sendable {
    var year: Int
    var month: Int
    var text: String
    var updatedAt: Date
}
