import Foundation
import SwiftData

/// サブスクリプションモデル
/// 課金状態を管理（StoreKit 2連携予定）
@Model
final class Subscription {

    // MARK: - Properties

    /// プラン種別
    var plan: SubscriptionPlan

    /// 課金状態
    var status: SubscriptionStatus

    /// 利用開始日時
    var startedAt: Date

    /// 利用終了日時
    var endedAt: Date?

    /// 作成日時
    var createdAt: Date

    /// 更新日時
    var updatedAt: Date

    // MARK: - Initialization

    init(
        plan: SubscriptionPlan = .free,
        status: SubscriptionStatus = .active
    ) {
        self.plan = plan
        self.status = status
        self.startedAt = Date()
        self.endedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SubscriptionPlan

/// サブスクリプションプラン
enum SubscriptionPlan: String, Codable, CaseIterable {
    /// 無料プラン
    case free
    /// Proプラン
    case pro
}

// MARK: - SubscriptionStatus

/// サブスクリプション状態
enum SubscriptionStatus: String, Codable, CaseIterable {
    /// 有効
    case active
    /// 無効（期限切れ）
    case inactive
    /// キャンセル済み
    case cancelled
}

// MARK: - Computed Properties

extension Subscription {
    /// Pro機能が利用可能かどうか
    var isProActive: Bool {
        plan == .pro && status == .active
    }

    /// 無料プランかどうか
    var isFree: Bool {
        plan == .free
    }
}
