import Foundation

/// 共有画像専用の英語月名・曜日。DateFormatter のロケール結果に依存しない。
///
/// どのアプリ言語でも同じ文字列を返す。並び順だけ `firstWeekday` に追従する。
enum MonthlyLogShareEnglishLabels {
    static let weekdayAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static let fullMonthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    static let abbreviatedMonthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    static func fullMonthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "" }
        return fullMonthNames[month - 1]
    }

    static func abbreviatedMonthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "" }
        return abbreviatedMonthNames[month - 1]
    }

    /// `firstWeekday` は Calendar と同じ 1 = 日曜 … 7 = 土曜
    static func weekdayAbbreviations(firstWeekday: Int) -> [String] {
        let start = ((firstWeekday - 1) % 7 + 7) % 7
        return (0..<7).map { weekdayAbbreviations[(start + $0) % 7] }
    }
}
