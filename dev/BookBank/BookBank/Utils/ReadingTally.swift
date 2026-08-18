import Foundation

/// 1回の読書（初回または再読）。通帳・カレンダー・統計・共有の回数集計の単位。
struct BookReadingOccurrence: Identifiable, Equatable, Hashable, Sendable {
    /// 初回は `bookId:initial`、再読は `rereadId`
    let id: String
    let book: BookDTO
    let date: Date
    let isReread: Bool
}

/// 読書回数への展開と、回数ベースの並び・振り分け。
enum ReadingTally {
    static func initialOccurrenceID(bookId: String) -> String {
        "\(bookId):initial"
    }

    /// 入力順（正準ソート）を保ったまま、各本を初回＋再読へ展開する。
    static func occurrences(from books: [BookDTO]) -> [BookReadingOccurrence] {
        books.flatMap { book in
            let initial = BookReadingOccurrence(
                id: initialOccurrenceID(bookId: book.id),
                book: book,
                date: book.registeredAt,
                isReread: false
            )
            let rereads = book.rereads.map { record in
                BookReadingOccurrence(
                    id: record.id,
                    book: book,
                    date: record.date,
                    isReread: true
                )
            }
            return [initial] + rereads
        }
    }

    /// 日付降順。同じ暦日は初回を先。初回同士は正準順（registeredAt 降順 → createdAt 降順）。再読同士は ID 昇順。
    static func sortedForDisplay(
        _ occurrences: [BookReadingOccurrence],
        calendar: Calendar = .current
    ) -> [BookReadingOccurrence] {
        occurrences.enumerated().sorted { lhs, rhs in
            let leftDay = calendar.startOfDay(for: lhs.element.date)
            let rightDay = calendar.startOfDay(for: rhs.element.date)
            if leftDay != rightDay {
                return leftDay > rightDay
            }
            if lhs.element.isReread != rhs.element.isReread {
                return !lhs.element.isReread
            }
            if lhs.element.isReread {
                return lhs.element.id < rhs.element.id
            }
            // 初回同士は fetchSorted と同じ正準順（registeredAt 降順 → createdAt 降順）
            if lhs.element.book.registeredAt != rhs.element.book.registeredAt {
                return lhs.element.book.registeredAt > rhs.element.book.registeredAt
            }
            if lhs.element.book.createdAt != rhs.element.book.createdAt {
                return lhs.element.book.createdAt > rhs.element.book.createdAt
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func displayedOccurrences(
        from books: [BookDTO],
        calendar: Calendar = .current
    ) -> [BookReadingOccurrence] {
        sortedForDisplay(occurrences(from: books), calendar: calendar)
    }

    /// 本棚用。`latestReadDate` 降順。同値は入力順を維持する。
    static func sortedByLatestReadDate(_ books: [BookDTO]) -> [BookDTO] {
        books.enumerated().sorted { lhs, rhs in
            if lhs.element.latestReadDate != rhs.element.latestReadDate {
                return lhs.element.latestReadDate > rhs.element.latestReadDate
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func occurrences(
        from books: [BookDTO],
        inYear year: Int,
        calendar: Calendar = .current
    ) -> [BookReadingOccurrence] {
        occurrences(from: books).filter { calendar.component(.year, from: $0.date) == year }
    }

    static func occurrences(
        from books: [BookDTO],
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> [BookReadingOccurrence] {
        occurrences(from: books).filter { occurrence in
            let components = calendar.dateComponents([.year, .month], from: occurrence.date)
            return components.year == year && components.month == month
        }
    }

    /// その年に1回以上読んだユニーク本。
    static func uniqueBooksRead(
        from books: [BookDTO],
        inYear year: Int,
        calendar: Calendar = .current
    ) -> [BookDTO] {
        var seen = Set<String>()
        var result: [BookDTO] = []
        for occurrence in occurrences(from: books, inYear: year, calendar: calendar) {
            if seen.insert(occurrence.book.id).inserted {
                result.append(occurrence.book)
            }
        }
        return result
    }

    static func readingYears(
        from books: [BookDTO],
        calendar: Calendar = .current
    ) -> [Int] {
        var years = Set(occurrences(from: books).map { calendar.component(.year, from: $0.date) })
        years.insert(calendar.component(.year, from: Date()))
        return years.sorted()
    }

    static func titleOnlyLine(for book: BookDTO) -> String {
        let title: String
        if book.readCount > 1 {
            title = "\(book.title) ×\(book.readCount)"
        } else {
            title = book.title
        }
        if let author = book.author, !author.isEmpty {
            return "\(title) / \(author)"
        }
        return title
    }

    @MainActor
    static func totalDisplayAmount(
        of occurrences: [BookReadingOccurrence],
        in target: AppCurrency,
        exchangeRates: ExchangeRateService
    ) -> Int {
        occurrences.reduce(0) { partial, occurrence in
            partial + (occurrence.book.displayAmount(in: target, exchangeRates: exchangeRates) ?? 0)
        }
    }
}
