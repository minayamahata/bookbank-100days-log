import Foundation

/// 口座のView向けDTO（設計メモ 3.3節）
struct PassbookDTO: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var type: PassbookType
    var sortOrder: Int
    var isActive: Bool
    var colorIndex: Int?
    var customColorHex: String?
    var createdAt: Date
    var updatedAt: Date
}

extension PassbookDTO {
    var isOverall: Bool {
        type == .overall
    }
}
