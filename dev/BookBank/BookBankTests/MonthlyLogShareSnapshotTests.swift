import Foundation
import Testing
@testable import BookBank

@MainActor
struct MonthlyLogShareSnapshotTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func book(
        id: String,
        year: Int,
        month: Int,
        day: Int,
        price: Int? = 1000,
        currency: String? = "JPY",
        passbookId: String? = "overall-a",
        memo: String? = "user memo"
    ) -> BookDTO {
        let calendar = calendar()
        let registeredAt = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
        return BookDTO(
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
            memo: memo,
            isFavorite: false,
            priceAtRegistration: price,
            currencyCode: currency,
            registeredAt: registeredAt,
            createdAt: registeredAt,
            updatedAt: registeredAt,
            passbookId: passbookId,
            hasCoverImage: false
        )
    }

    private func makeSnapshot(
        year: Int = 2026,
        month: Int = 8,
        books: [BookDTO],
        currency: AppCurrency = .jpy,
        locale: Locale = Locale(identifier: "ja")
    ) -> MonthlyLogShareSnapshot {
        MonthlyLogShareSnapshot.make(
            year: year,
            month: month,
            passbookBooks: books,
            displayCurrency: currency,
            exchangeRates: .shared,
            calendar: calendar(),
            locale: locale
        )
    }

    @Test func overallAccountKeepsEveryPassbookInTheMonth() {
        let books = [
            book(id: "a", year: 2026, month: 8, day: 1, passbookId: "p1"),
            book(id: "b", year: 2026, month: 8, day: 10, passbookId: "p2"),
        ]
        let snapshot = makeSnapshot(books: books)
        #expect(snapshot.books.map(\.id) == ["a", "b"])
        #expect(snapshot.bookCount == 2)
    }

    @Test func customAccountUsesAlreadyScopedBooks() {
        let all = [
            book(id: "a", year: 2026, month: 8, day: 1, passbookId: "p1"),
            book(id: "b", year: 2026, month: 8, day: 10, passbookId: "p2"),
        ]
        let custom = all.filter { $0.passbookId == "p1" }
        let snapshot = makeSnapshot(books: custom)
        #expect(snapshot.books.map(\.id) == ["a"])
        #expect(snapshot.bookCount == 1)
    }

    @Test func excludesBooksOutsideTheTargetMonth() {
        let books = [
            book(id: "jul", year: 2026, month: 7, day: 31),
            book(id: "aug1", year: 2026, month: 8, day: 1),
            book(id: "aug31", year: 2026, month: 8, day: 31),
            book(id: "sep", year: 2026, month: 9, day: 1),
        ]
        let snapshot = makeSnapshot(books: books)
        #expect(snapshot.books.map(\.id) == ["aug1", "aug31"])
        #expect(snapshot.layout.days.first { $0.day == 1 }?.books.map(\.id) == ["aug1"])
        #expect(snapshot.layout.days.first { $0.day == 31 }?.books.map(\.id) == ["aug31"])
    }

    @Test func zeroAndOneBook() {
        let empty = makeSnapshot(books: [])
        #expect(empty.bookCount == 0)
        #expect(empty.totalDisplayAmount == 0)
        #expect(empty.books.isEmpty)

        let one = makeSnapshot(books: [book(id: "only", year: 2026, month: 8, day: 8)])
        #expect(one.bookCount == 1)
        #expect(one.totalDisplayAmount == 1000)
    }

    @Test func sameDayBooksAreAllCounted() {
        let books = [
            book(id: "a", year: 2026, month: 8, day: 16, price: 500),
            book(id: "b", year: 2026, month: 8, day: 16, price: 700),
        ]
        let snapshot = makeSnapshot(books: books)
        #expect(snapshot.bookCount == 2)
        #expect(snapshot.totalDisplayAmount == 1200)
        #expect(snapshot.layout.days.first { $0.day == 16 }?.extraCount == 1)
    }

    @Test func missingPriceContributesZero() {
        let books = [
            book(id: "priced", year: 2026, month: 8, day: 2, price: 800),
            book(id: "free", year: 2026, month: 8, day: 3, price: nil),
        ]
        let snapshot = makeSnapshot(books: books)
        #expect(snapshot.bookCount == 2)
        #expect(snapshot.totalDisplayAmount == 800)
    }

    @Test func totalUsesExistingDisplayCurrencyConversion() {
        let books = [book(id: "jpy", year: 2026, month: 8, day: 4, price: 1500, currency: "JPY")]
        let snapshot = makeSnapshot(books: books, currency: .usd)
        let expected = books.totalDisplayAmount(in: .usd, exchangeRates: .shared)
        #expect(snapshot.totalDisplayAmount == expected)
        #expect(snapshot.displayCurrency == .usd)
    }

    @Test func rereadInTargetMonthIsIncludedEvenIfInitialIsOutside() {
        var item = book(id: "july-book", year: 2026, month: 7, day: 20, price: 500)
        item.rereads = [RereadRecord(id: "aug-reread", date: calendar().date(
            from: DateComponents(year: 2026, month: 8, day: 8, hour: 12)
        )!)]
        let snapshot = makeSnapshot(books: [item])
        #expect(snapshot.bookCount == 1)
        #expect(snapshot.totalDisplayAmount == 500)
        #expect(snapshot.books.map(\.id) == ["july-book"])
        #expect(snapshot.occurrences.map(\.id) == ["aug-reread"])
        #expect(snapshot.layout.days.first { $0.day == 8 }?.representative?.id == "july-book")
    }

    @Test func sameBookMultipleReadsInMonthCountEachTime() {
        var item = book(id: "repeat", year: 2026, month: 8, day: 1, price: 400)
        item.rereads = [
            RereadRecord(id: "r2", date: calendar().date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 10))!),
            RereadRecord(id: "r3", date: calendar().date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 18))!)
        ]
        let snapshot = makeSnapshot(books: [item])
        #expect(snapshot.bookCount == 3)
        #expect(snapshot.totalDisplayAmount == 1200)
        #expect(snapshot.books.map(\.id) == ["repeat"])
        #expect(snapshot.layout.days.first { $0.day == 16 }?.extraCount == 1)
        #expect(snapshot.layout.days.first { $0.day == 16 }?.occurrences.map(\.id) == ["r2", "r3"])
    }

    @Test func doesNotKeepMonthlyMemoText() {
        let snapshot = makeSnapshot(books: [book(id: "m", year: 2026, month: 8, day: 5, memo: "user memo")])
        let labels = Mirror(reflecting: snapshot).children.compactMap(\.label)
        #expect(!labels.contains("monthlyMemoText"))
        #expect(!labels.contains("monthlyMemo"))
        #expect(!labels.contains("text"))
        #expect(snapshot.books.first?.memo == "user memo", "書籍メモはDTOのまま残ってよい")
    }
}
