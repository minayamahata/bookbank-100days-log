import Foundation
import SwiftData

/// 口座（通帳）モデル
/// ユーザーの書籍を分類・管理するための論理的なグループ
@Model
final class Passbook {

    // MARK: - Properties

    /// 口座名（例: "総合口座", "技術書", "漫画"）
    var name: String

    /// 口座種別
    var type: PassbookType

    /// 表示順序（小さいほど上に表示）
    var sortOrder: Int

    /// 有効フラグ（論理削除用）
    var isActive: Bool
    
    /// テーマカラーのインデックス（nilの場合は自動割り当て）
    var colorIndex: Int?

    /// 作成日時
    var createdAt: Date

    /// 更新日時
    var updatedAt: Date

    // MARK: - Relationships

    /// この口座に登録されている書籍（逆参照）
    @Relationship(deleteRule: .cascade, inverse: \UserBook.passbook)
    var userBooks: [UserBook]

    // MARK: - Initialization

    init(
        name: String,
        type: PassbookType = .custom,
        sortOrder: Int = 0,
        isActive: Bool = true
    ) {
        self.name = name
        self.type = type
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        self.userBooks = []
    }

    // MARK: - Factory Methods

    /// 総合口座を作成（アプリ初回起動時に1つだけ作成）
    static func createOverall() -> Passbook {
        Passbook(
            name: "総合口座",
            type: .overall,
            sortOrder: 0,
            isActive: true
        )
    }
}

// MARK: - PassbookType

/// 口座種別
enum PassbookType: String, Codable, CaseIterable {
    /// 総合口座（ユーザーごとに1つ、削除不可）
    case overall
    /// カスタム口座（ユーザーが自由に作成）
    case custom
}

// MARK: - Computed Properties

extension Passbook {
    /// 総合口座かどうか
    var isOverall: Bool {
        type == .overall
    }

    /// 登録書籍数
    var bookCount: Int {
        userBooks.count
    }

    /// 総額（登録時価格の合計）
    var totalValue: Int {
        userBooks.compactMap { $0.priceAtRegistration }.reduce(0, +)
    }
}
