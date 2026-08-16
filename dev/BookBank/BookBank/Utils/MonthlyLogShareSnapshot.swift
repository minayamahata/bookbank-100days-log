import Foundation

/// 共有画面を開いた時点で固定する月次ログ。開いたあとの書籍・為替の変化は反映しない。
///
/// 月別メモ（`MonthlyMemo`）の本文は持たない。新しい DTO / リポジトリは追加しない。
struct MonthlyLogShareSnapshot: Equatable, Sendable {
    let year: Int
    let month: Int
    /// 対象月の書籍（渡された口座スコープ済み配列を月で絞ったもの）
    let books: [BookDTO]
    let bookCount: Int
    /// `Collection.totalDisplayAmount(in:exchangeRates:)` の結果
    let totalDisplayAmount: Int
    let displayCurrency: AppCurrency
    /// 金額・冊数・通貨単位の表示に使うアプリ言語
    let localeIdentifier: String
    let firstWeekday: Int
    let timeZoneIdentifier: String
    let layout: MonthlyCalendarLayout

    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// - Parameter passbookBooks: `BookshelfView.passbookBooks`（総合=全書籍、カスタム=その口座）。一時フィルターは掛けない
    @MainActor
    static func make(
        year: Int,
        month: Int,
        passbookBooks: [BookDTO],
        displayCurrency: AppCurrency,
        exchangeRates: ExchangeRateService,
        calendar: Calendar,
        locale: Locale
    ) -> MonthlyLogShareSnapshot {
        let books = passbookBooks.filter { book in
            let components = calendar.dateComponents([.year, .month], from: book.registeredAt)
            return components.year == year && components.month == month
        }
        let layout = MonthlyCalendarLayout.make(
            year: year,
            month: month,
            books: books,
            calendar: calendar
        )
        return MonthlyLogShareSnapshot(
            year: year,
            month: month,
            books: books,
            bookCount: books.count,
            totalDisplayAmount: books.totalDisplayAmount(in: displayCurrency, exchangeRates: exchangeRates),
            displayCurrency: displayCurrency,
            localeIdentifier: locale.identifier,
            firstWeekday: calendar.firstWeekday,
            timeZoneIdentifier: calendar.timeZone.identifier,
            layout: layout
        )
    }
}

enum MonthlyLogShareTemplate: Int, CaseIterable, Identifiable, Sendable {
    case calendarSummary
    case verticalMonth
    case largeMonth
    case minimalSummary

    var id: Int { rawValue }

    var showsAmount: Bool {
        self == .calendarSummary || self == .minimalSummary
    }

    var showsCalendar: Bool {
        self != .minimalSummary
    }

    func monthHeadline(month: Int) -> String {
        switch self {
        case .calendarSummary:
            return String(month)
        case .verticalMonth:
            return MonthlyLogShareEnglishLabels.fullMonthName(month)
        case .largeMonth:
            return MonthlyLogShareEnglishLabels.abbreviatedMonthName(month)
        case .minimalSummary:
            return String(format: "%02d", month)
        }
    }
}
