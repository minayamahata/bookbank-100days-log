import Foundation

/// 読了リストのView向けDTO（設計メモ 3.3節・前提5・前提6）
struct ReadingListDTO: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var description: String?
    var colorIndex: Int?
    var bookIds: [String]
    /// 並び順解決済みの本（`orderedBooks` 相当）
    var books: [BookDTO]
    var createdAt: Date
    var updatedAt: Date
    /// 共有URL同一性のための `persistentModelID` 文字列（前提6）
    var legacyShareId: String
}
