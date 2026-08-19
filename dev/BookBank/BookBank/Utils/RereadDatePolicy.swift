import Foundation

/// 登録日と再読日の日単位検証。クランプせず、範囲外は呼び出し側が throw する。
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

    /// 登録日が今日以前か。
    static func isValidRegisteredAt(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: date) <= calendar.startOfDay(for: now)
    }

    /// 登録日は今日以前、全再読日は登録日以降。同日は許可する。
    /// `updateBook` と `saveBookEdits` が共用する。
    static func areReadingDatesConsistent(
        registeredAt: Date,
        rereadDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isValidRegisteredAt(registeredAt, now: now, calendar: calendar) else { return false }
        return rereadDates.allSatisfy {
            isValid($0, registeredAt: registeredAt, now: now, calendar: calendar)
        }
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
