import Foundation

/// 再読日の日単位検証。クランプせず、範囲外は呼び出し側が throw する。
enum RereadDatePolicy {
    /// 初回登録日の日〜今日の日に収まるか。同日は許可する。
    static func isValid(
        _ date: Date,
        registeredAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: registeredAt)
        let end = calendar.startOfDay(for: now)
        return day >= start && day <= end
    }

    /// 初回登録日の編集上限。`min(最初の再読日, 今日)`。再読がなければ今日。
    static func registeredAtUpperBound(
        firstRereadDate: Date?,
        now: Date = Date()
    ) -> Date {
        guard let firstRereadDate else { return now }
        return min(firstRereadDate, now)
    }
}
