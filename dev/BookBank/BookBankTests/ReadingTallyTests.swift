import Foundation
import Testing
@testable import BookBank

@MainActor
struct ReadingTallyTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func book(
        id: String,
        registeredAt: Date,
        rereads: [RereadRecord] = [],
        price: Int? = 1000,
        createdAt: Date? = nil
    ) -> BookDTO {
        BookDTO(
            id: id,
            title: id,
            author: nil,
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: price,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: price,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            rereads: rereads,
            createdAt: createdAt ?? registeredAt,
            updatedAt: registeredAt,
            passbookId: "pb",
            hasCoverImage: false
        )
    }

    @Test func stableIDsAndReadCount() {
        let initial = date(2026, 8, 1)
        let reread = RereadRecord(id: "r-2", date: date(2026, 8, 10))
        let item = book(id: "b1", registeredAt: initial, rereads: [reread])
        #expect(item.readCount == 2)
        #expect(item.latestReadDate == reread.date)
        #expect(item.allReadingDates == [initial, reread.date])

        let occurrences = ReadingTally.occurrences(from: [item])
        #expect(occurrences.map(\.id) == ["b1:initial", "r-2"])
        #expect(occurrences.map(\.isReread) == [false, true])
    }

    @Test func displayOrderDateDescInitialFirstRereadIdAsc() {
        let older = book(id: "older", registeredAt: date(2026, 8, 10, hour: 10))
        let newer = book(
            id: "newer",
            registeredAt: date(2026, 8, 10, hour: 18),
            rereads: [
                RereadRecord(id: "r-b", date: date(2026, 8, 10, hour: 20)),
                RereadRecord(id: "r-a", date: date(2026, 8, 10, hour: 21))
            ]
        )
        let later = book(id: "later", registeredAt: date(2026, 8, 11))
        let displayed = ReadingTally.displayedOccurrences(
            from: [newer, older, later],
            calendar: calendar()
        )
        #expect(displayed.map(\.id) == ["later:initial", "newer:initial", "older:initial", "r-a", "r-b"])
    }

    @Test func latestReadDateSortKeepsInputOrderOnTie() {
        let first = book(id: "a", registeredAt: date(2026, 7, 1), rereads: [
            RereadRecord(id: "r", date: date(2026, 8, 1))
        ])
        let second = book(id: "b", registeredAt: date(2026, 8, 1))
        let third = book(id: "c", registeredAt: date(2026, 6, 1))
        #expect(ReadingTally.sortedByLatestReadDate([first, second, third]).map(\.id) == ["a", "b", "c"])
    }

    @Test func yearMonthGroupingAndMissingPrice() {
        let item = book(
            id: "m",
            registeredAt: date(2026, 7, 31),
            rereads: [RereadRecord(id: "aug", date: date(2026, 8, 2))],
            price: nil
        )
        #expect(ReadingTally.occurrences(from: [item], inYear: 2026, calendar: calendar()).count == 2)
        #expect(ReadingTally.occurrences(from: [item], year: 2026, month: 8, calendar: calendar()).map(\.id) == ["aug"])
        #expect(ReadingTally.uniqueBooksRead(from: [item], inYear: 2026, calendar: calendar()).map(\.id) == ["m"])
        #expect(ReadingTally.readingYears(from: [item], calendar: calendar()).contains(2026))
        #expect(ReadingTally.titleOnlyLine(for: item) == "m ×2")
    }

    @Test func amountCountsEachOccurrence() {
        let item = book(
            id: "priced",
            registeredAt: date(2026, 8, 1),
            rereads: [RereadRecord(id: "r", date: date(2026, 8, 2))],
            price: 800
        )
        let amount = ReadingTally.totalDisplayAmount(
            of: ReadingTally.occurrences(from: [item]),
            in: .jpy,
            exchangeRates: .shared
        )
        #expect(amount == 1600)
        let missing = book(id: "free", registeredAt: date(2026, 8, 1), price: nil)
        #expect(
            ReadingTally.totalDisplayAmount(
                of: ReadingTally.occurrences(from: [missing]),
                in: .jpy,
                exchangeRates: .shared
            ) == 0
        )
    }
}
