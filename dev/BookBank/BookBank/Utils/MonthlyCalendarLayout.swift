import Foundation

/// 月間カレンダーの配置結果。通常画面と共有画像が同じ計算を使う。
///
/// 週の始まりは渡された `Calendar.firstWeekday` に従う（日曜始まり・月曜始まりの両方）。
/// 共有画像用に別の暦計算を持たない。
struct MonthlyCalendarLayout: Equatable, Sendable {
    /// 1日分。`occurrences` は表示順（日付降順・同日は初回先）。
    struct Day: Equatable, Identifiable, Sendable {
        let day: Int
        let occurrences: [BookReadingOccurrence]

        var id: Int { day }
        var representative: BookDTO? { occurrences.first?.book }
        var extraCount: Int { max(0, occurrences.count - 1) }
        var books: [BookDTO] { occurrences.map(\.book) }
    }

    let year: Int
    let month: Int
    let firstWeekday: Int
    let leadingBlankCount: Int
    let dayCount: Int
    let days: [Day]

    /// 空白セルと日付セルを7列に並べたときの行数（4〜6）
    var rowCount: Int {
        let cells = leadingBlankCount + dayCount
        guard cells > 0 else { return 0 }
        return (cells + 6) / 7
    }

    static func make(
        year: Int,
        month: Int,
        books: [BookDTO],
        calendar: Calendar
    ) -> MonthlyCalendarLayout {
        make(
            year: year,
            month: month,
            occurrences: ReadingTally.displayedOccurrences(from: books, calendar: calendar),
            calendar: calendar
        )
    }

    static func make(
        year: Int,
        month: Int,
        occurrences: [BookReadingOccurrence],
        calendar: Calendar
    ) -> MonthlyCalendarLayout {
        let dayCount = daysInMonth(year: year, month: month, calendar: calendar)
        let leading = leadingBlankCount(year: year, month: month, calendar: calendar)
        let grouped = groupByDay(occurrences, calendar: calendar)
        let days = (1...max(dayCount, 1)).map { day in
            Day(day: day, occurrences: grouped[day] ?? [])
        }
        return MonthlyCalendarLayout(
            year: year,
            month: month,
            firstWeekday: calendar.firstWeekday,
            leadingBlankCount: leading,
            dayCount: dayCount,
            days: days
        )
    }

    /// その月の読書を「日 -> occurrence 配列（表示順）」にまとめる
    static func groupByDay(
        _ occurrences: [BookReadingOccurrence],
        calendar: Calendar
    ) -> [Int: [BookReadingOccurrence]] {
        var result: [Int: [BookReadingOccurrence]] = [:]
        for occurrence in occurrences {
            let day = calendar.component(.day, from: occurrence.date)
            result[day, default: []].append(occurrence)
        }
        for key in result.keys {
            result[key] = ReadingTally.sortedForDisplay(result[key] ?? [], calendar: calendar)
        }
        return result
    }

    /// 月初の曜日に合わせた先頭空白セル数
    static func leadingBlankCount(year: Int, month: Int, calendar: Calendar) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstDay = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay) // 1 = 日曜
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// その月の日数
    static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }
}
