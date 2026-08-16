import Foundation
import Testing
@testable import BookBank

@MainActor
struct MonthlyCalendarLayoutTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func book(
        id: String,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        calendar: Calendar
    ) -> BookDTO {
        let registeredAt = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
        return BookDTO(
            id: id,
            title: id,
            author: nil,
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: 1000,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: 1000,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            createdAt: registeredAt,
            updatedAt: registeredAt,
            passbookId: "pb",
            hasCoverImage: false
        )
    }

    @Test func sundayStartUsesFirstWeekday1() {
        let calendar = calendar(firstWeekday: 1)
        let layout = MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: calendar)
        #expect(layout.firstWeekday == 1)
        #expect(layout.leadingBlankCount == 6, "2026-08-01 は土曜。日曜始まりなら空白6")
        #expect(layout.dayCount == 31)
        #expect(layout.rowCount == 6)
    }

    @Test func mondayStartUsesFirstWeekday2() {
        let calendar = calendar(firstWeekday: 2)
        let layout = MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: calendar)
        #expect(layout.firstWeekday == 2)
        #expect(layout.leadingBlankCount == 5, "2026-08-01 は土曜。月曜始まりなら空白5")
        #expect(layout.dayCount == 31)
        #expect(layout.rowCount == 6)
    }

    @Test func leadingBlanksForEachWeekdayOnSundayStart() {
        let calendar = calendar(firstWeekday: 1)
        let cases: [(Int, Int, Int)] = [
            (2026, 2, 0), // Sun
            (2026, 6, 1), // Mon
            (2026, 9, 2), // Tue
            (2026, 4, 3), // Wed
            (2026, 1, 4), // Thu
            (2026, 5, 5), // Fri
            (2026, 8, 6), // Sat
        ]
        for (year, month, expected) in cases {
            let layout = MonthlyCalendarLayout.make(year: year, month: month, books: [], calendar: calendar)
            #expect(layout.leadingBlankCount == expected, "\(year)-\(month) の空白")
        }
    }

    @Test func leadingBlanksForEachWeekdayOnMondayStart() {
        let calendar = calendar(firstWeekday: 2)
        let cases: [(Int, Int, Int)] = [
            (2026, 2, 6), // Sun
            (2026, 6, 0), // Mon
            (2026, 9, 1), // Tue
            (2026, 4, 2), // Wed
            (2026, 1, 3), // Thu
            (2026, 5, 4), // Fri
            (2026, 8, 5), // Sat
        ]
        for (year, month, expected) in cases {
            let layout = MonthlyCalendarLayout.make(year: year, month: month, books: [], calendar: calendar)
            #expect(layout.leadingBlankCount == expected, "\(year)-\(month) の空白")
        }
    }

    @Test func rowCountCoversFourToSix() {
        let sunday = calendar(firstWeekday: 1)
        #expect(MonthlyCalendarLayout.make(year: 2026, month: 2, books: [], calendar: sunday).rowCount == 4)
        #expect(MonthlyCalendarLayout.make(year: 2026, month: 4, books: [], calendar: sunday).rowCount == 5)
        #expect(MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: sunday).rowCount == 6)
    }

    @Test func leapYearFebruaryHas29Days() {
        let calendar = calendar(firstWeekday: 1)
        let leap = MonthlyCalendarLayout.make(year: 2024, month: 2, books: [], calendar: calendar)
        let common = MonthlyCalendarLayout.make(year: 2026, month: 2, books: [], calendar: calendar)
        #expect(leap.dayCount == 29)
        #expect(common.dayCount == 28)
    }

    @Test func sameDayBooksPickLatestCoverAndPlusN() {
        let calendar = calendar(firstWeekday: 1)
        let older = book(id: "old", year: 2026, month: 8, day: 16, hour: 10, calendar: calendar)
        let newer = book(id: "new", year: 2026, month: 8, day: 16, hour: 18, calendar: calendar)
        let other = book(id: "other", year: 2026, month: 8, day: 17, hour: 12, calendar: calendar)
        let layout = MonthlyCalendarLayout.make(
            year: 2026,
            month: 8,
            books: [older, newer, other],
            calendar: calendar
        )
        let day16 = layout.days.first { $0.day == 16 }
        #expect(day16?.books.map(\.id) == ["new", "old"])
        #expect(day16?.representative?.id == "new")
        #expect(day16?.extraCount == 1)
        #expect(layout.days.first { $0.day == 17 }?.extraCount == 0)
    }

    @Test func screenAndShareUseTheSameLayoutResult() {
        let calendar = calendar(firstWeekday: 2)
        let books = [
            book(id: "a", year: 2026, month: 8, day: 6, calendar: calendar),
            book(id: "b", year: 2026, month: 8, day: 6, hour: 20, calendar: calendar),
        ]
        let forScreen = MonthlyCalendarLayout.make(year: 2026, month: 8, books: books, calendar: calendar)
        let forShare = MonthlyCalendarLayout.make(year: 2026, month: 8, books: books, calendar: calendar)
        let layoutsMatch = forScreen == forShare
        #expect(layoutsMatch)
        #expect(forScreen.leadingBlankCount == forShare.leadingBlankCount)
        #expect(forScreen.rowCount == forShare.rowCount)
        #expect(forScreen.days.map(\.representative?.id) == forShare.days.map(\.representative?.id))
        #expect(forScreen.days.map(\.extraCount) == forShare.days.map(\.extraCount))
    }
}
