import CoreGraphics
import Foundation

/// マンスリーログ共有テンプレートのキャンバス形式。表示順の index には依存しない。
/// 2026-08-21 に一度 3:4／8:9／1:1 へ変更したが、同日中に 9:16／4:5／1:1 へ差し戻した。
enum MonthlyLogShareCanvasFormat: Equatable, Sendable {
    case portrait
    case portraitFourFive
    case square

    var logicalSize: CGSize {
        switch self {
        case .portrait:
            return CGSize(width: 360, height: 640)
        case .portraitFourFive:
            return CGSize(width: 360, height: 450)
        case .square:
            return CGSize(width: 360, height: 360)
        }
    }

    var masterPixelSize: CGSize {
        switch self {
        case .portrait:
            return CGSize(width: 1080, height: 1920)
        case .portraitFourFive:
            return CGSize(width: 1080, height: 1350)
        case .square:
            return CGSize(width: 1080, height: 1080)
        }
    }

    var shouldTrimTransparentMargins: Bool {
        switch self {
        case .portrait:
            return true
        case .portraitFourFive, .square:
            return false
        }
    }
}

/// 共有画面を開いた時点で固定する月次ログ。開いたあとの書籍・為替の変化は反映しない。
///
/// 月別メモ（`MonthlyMemo`）の本文は持たない。新しい DTO / リポジトリは追加しない。
struct MonthlyLogShareSnapshot: Equatable, Sendable {
    let year: Int
    let month: Int
    /// 対象月の読書（初回が月外でも、再読が月内なら含む）
    let occurrences: [BookReadingOccurrence]
    /// 表紙読み込み用のユニーク本（出現順）
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
        let occurrences = ReadingTally.displayedOccurrences(
            from: passbookBooks,
            calendar: calendar
        ).filter { occurrence in
            let components = calendar.dateComponents([.year, .month], from: occurrence.date)
            return components.year == year && components.month == month
        }
        let monthBookIDs = Set(occurrences.map(\.book.id))
        let books = passbookBooks.filter { monthBookIDs.contains($0.id) }
        let layout = MonthlyCalendarLayout.make(
            year: year,
            month: month,
            occurrences: occurrences,
            calendar: calendar
        )
        return MonthlyLogShareSnapshot(
            year: year,
            month: month,
            occurrences: occurrences,
            books: books,
            bookCount: occurrences.count,
            totalDisplayAmount: ReadingTally.totalDisplayAmount(
                of: occurrences,
                in: displayCurrency,
                exchangeRates: exchangeRates
            ),
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
    /// 6枚目（2026-08-21 追加）: 左揃えの「My month in books」＋冊数＋ワードマーク。1:1
    case monthInBooks
    /// 4枚目（2026-08-21 追加）: 書影を使わず、読書日を丸で示す数字カレンダー＋冊数。4:5
    case circledCalendar

    var id: Int { rawValue }

    var canvasFormat: MonthlyLogShareCanvasFormat {
        switch self {
        case .calendarSummary, .largeMonth:
            return .portrait
        case .verticalMonth, .circledCalendar:
            return .portraitFourFive
        case .minimalSummary, .monthInBooks:
            return .square
        }
    }

    var showsAmount: Bool {
        self == .calendarSummary || self == .minimalSummary
    }

    var showsCalendar: Bool {
        self == .calendarSummary || self == .verticalMonth || self == .largeMonth
            || self == .circledCalendar
    }

    /// 書影を描画しないテンプレートだけ Instagram Stories へ直接共有できる。
    /// 表示順の index では決めない。カルーセル順を変えても書影入りは対象外のまま。
    var supportsInstagramStoriesShare: Bool {
        switch self {
        case .circledCalendar, .minimalSummary, .monthInBooks:
            return true
        case .calendarSummary, .largeMonth, .verticalMonth:
            return false
        }
    }

    func monthHeadline(month: Int) -> String {
        switch self {
        case .calendarSummary:
            return String(month)
        case .verticalMonth, .monthInBooks, .circledCalendar:
            return MonthlyLogShareEnglishLabels.fullMonthName(month)
        case .largeMonth:
            return MonthlyLogShareEnglishLabels.abbreviatedMonthName(month)
        case .minimalSummary:
            return String(format: "%02d", month)
        }
    }
}
