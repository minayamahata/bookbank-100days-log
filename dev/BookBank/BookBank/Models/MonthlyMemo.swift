import Foundation
import SwiftData

/// 月別メモモデル
/// 口座を横断するポートフォリオレベルで、年月ごとにメモを記録する
@Model
final class MonthlyMemo {

    /// 安定ID（UUID文字列）。R3で追加したが、FirestoreのドキュメントIDには使わない
    /// （docIDは yyyy-MM・突合キーは (year, month)。設計メモ 前提2）。一貫性のためフィールドとして持つだけ。
    /// 既存行の一意性は UUIDBackfillMigration が保証する（設計メモ 4.2）。
    var uuid: String = UUID().uuidString

    /// 対象年（例: 2026）
    var year: Int

    /// 対象月（1〜12）
    var month: Int

    /// メモ本文
    var text: String

    /// 更新日時
    var updatedAt: Date

    init(year: Int, month: Int, text: String = "") {
        self.uuid = UUID().uuidString
        self.year = year
        self.month = month
        self.text = text
        self.updatedAt = Date()
    }
}

// R4ステップ2（2026-07-23）: 旧 `MonthlyMemoRepository` enum（→一時 `LegacyMonthlyMemoRepository`）は
// `SwiftDataMonthlyMemoRepository`（Repositories/）へ置換し廃止。
// 空文字＝削除・rollback・OSLog（category: "MonthlyMemo"）の挙動は実装へ移設済み。
