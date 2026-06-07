import Foundation
import SwiftData

/// 月別メモモデル
/// 口座を横断するポートフォリオレベルで、年月ごとにメモを記録する
@Model
final class MonthlyMemo {

    /// 対象年（例: 2026）
    var year: Int

    /// 対象月（1〜12）
    var month: Int

    /// メモ本文
    var text: String

    /// 更新日時
    var updatedAt: Date

    init(year: Int, month: Int, text: String = "") {
        self.year = year
        self.month = month
        self.text = text
        self.updatedAt = Date()
    }
}

// MARK: - Repository

enum MonthlyMemoRepository {

    /// 指定年月のメモを取得（なければ nil）
    static func fetch(year: Int, month: Int, context: ModelContext) -> MonthlyMemo? {
        let descriptor = FetchDescriptor<MonthlyMemo>(
            predicate: #Predicate { $0.year == year && $0.month == month }
        )
        return try? context.fetch(descriptor).first
    }

    /// 指定年月のメモを取得、なければ新規作成して返す
    static func fetchOrCreate(year: Int, month: Int, context: ModelContext) -> MonthlyMemo {
        if let existing = fetch(year: year, month: month, context: context) {
            return existing
        }
        let memo = MonthlyMemo(year: year, month: month)
        context.insert(memo)
        return memo
    }

    /// メモを保存（空文字の場合はレコードを削除してストレージを節約）
    static func save(year: Int, month: Int, text: String, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let existing = fetch(year: year, month: month, context: context) {
                context.delete(existing)
            }
        } else {
            let memo = fetchOrCreate(year: year, month: month, context: context)
            memo.text = trimmed
            memo.updatedAt = Date()
        }

        try? context.save()
    }
}
