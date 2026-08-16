import Foundation
import Testing
import UIKit
@testable import BookBank

@MainActor
struct MonthlyLogShareRendererTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func book(id: String, day: Int, price: Int?) -> BookDTO {
        let calendar = calendar()
        let registeredAt = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day, hour: 12)
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
            memo: nil,
            isFavorite: false,
            priceAtRegistration: price,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            createdAt: registeredAt,
            updatedAt: registeredAt,
            passbookId: "pb",
            hasCoverImage: false
        )
    }

    private func snapshot(
        books: [BookDTO],
        locale: Locale = Locale(identifier: "ja")
    ) -> MonthlyLogShareSnapshot {
        MonthlyLogShareSnapshot.make(
            year: 2026,
            month: 8,
            passbookBooks: books,
            displayCurrency: .jpy,
            exchangeRates: .shared,
            calendar: calendar(),
            locale: locale
        )
    }

    private func png(
        _ snapshot: MonthlyLogShareSnapshot,
        _ template: MonthlyLogShareTemplate,
        covers: [String: UIImage] = [:]
    ) -> Data {
        let data = MonthlyLogShareRenderer.pngData(
            snapshot: snapshot,
            covers: covers,
            template: template
        )
        return try! #require(data)
    }

    @Test func templatesHaveExpectedFlags() {
        #expect(MonthlyLogShareTemplate.calendarSummary.showsAmount)
        #expect(MonthlyLogShareTemplate.minimalSummary.showsAmount)
        #expect(!MonthlyLogShareTemplate.verticalMonth.showsAmount)
        #expect(!MonthlyLogShareTemplate.largeMonth.showsAmount)

        #expect(MonthlyLogShareTemplate.calendarSummary.showsCalendar)
        #expect(MonthlyLogShareTemplate.verticalMonth.showsCalendar)
        #expect(MonthlyLogShareTemplate.largeMonth.showsCalendar)
        #expect(!MonthlyLogShareTemplate.minimalSummary.showsCalendar)
    }

    @Test func fourRowMonthAlsoRendersTransparent1080x1920() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        let registeredAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 12))!
        let februaryBook = BookDTO(
            id: "feb",
            title: "feb",
            author: nil,
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: 800,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: 800,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            createdAt: registeredAt,
            updatedAt: registeredAt,
            passbookId: "pb",
            hasCoverImage: false
        )
        let february = MonthlyLogShareSnapshot.make(
            year: 2026,
            month: 2,
            passbookBooks: [februaryBook],
            displayCurrency: .jpy,
            exchangeRates: .shared,
            calendar: calendar,
            locale: Locale(identifier: "ja")
        )
        #expect(february.layout.rowCount == 4)
        let data = png(february, .calendarSummary)
        let image = try #require(UIImage(data: data))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 1080)
        #expect(cgImage.height == 1920)
    }

    @Test func allTemplatesRender1080x1920PNGWithAlpha() throws {
        let snapshot = snapshot(books: [book(id: "a", day: 16, price: 1200)])
        #expect(snapshot.layout.rowCount == 6)
        for template in MonthlyLogShareTemplate.allCases {
            let data = png(snapshot, template)
            let image = try #require(UIImage(data: data))
            #expect(Int(image.size.width * image.scale) == 1080 || Int(image.size.width) == 1080)
            #expect(Int(image.size.height * image.scale) == 1920 || Int(image.size.height) == 1920)
            let cgImage = try #require(image.cgImage)
            #expect(cgImage.width == 1080)
            #expect(cgImage.height == 1920)
            let alpha = cgImage.alphaInfo
            #expect(
                alpha == .premultipliedLast
                    || alpha == .premultipliedFirst
                    || alpha == .last
                    || alpha == .first
            )
            #expect(hasTransparentCorner(cgImage), "\(template) の角は透明")
        }
    }

    @Test func amountAppearsOnlyOnTemplatesOneAndFour() {
        let cheap = snapshot(books: [book(id: "a", day: 6, price: 100)])
        let expensive = snapshot(books: [book(id: "a", day: 6, price: 99999)])
        #expect(png(cheap, .verticalMonth) == png(expensive, .verticalMonth))
        #expect(png(cheap, .largeMonth) == png(expensive, .largeMonth))
        #expect(png(cheap, .calendarSummary) != png(expensive, .calendarSummary))
        #expect(png(cheap, .minimalSummary) != png(expensive, .minimalSummary))
    }

    @Test func calendarAppearsOnlyOnTemplatesOneToThree() {
        let empty = snapshot(books: [])
        let placed = snapshot(books: [book(id: "coverless", day: 19, price: nil)])
        #expect(png(empty, .calendarSummary) != png(placed, .calendarSummary))
        #expect(png(empty, .verticalMonth) != png(placed, .verticalMonth))
        #expect(png(empty, .largeMonth) != png(placed, .largeMonth))
        #expect(png(empty, .minimalSummary) != png(placed, .minimalSummary), "冊数が違うので金額テンプレも変わる")
    }

    @Test func rendersWithoutCoversAndWithZeroBooks() {
        let empty = snapshot(books: [])
        let coverless = snapshot(books: [book(id: "none", day: 11, price: 0)])
        #expect(png(empty, .calendarSummary).isEmpty == false)
        #expect(png(coverless, .largeMonth).isEmpty == false)
        #expect(MonthlyLogShareTemplate.calendarSummary.monthHeadline(month: 8) == "8")
        #expect(MonthlyLogShareTemplate.minimalSummary.monthHeadline(month: 8) == "08")
    }

    @Test func shareCellsStayTwoByThreeForFourToSixRows() {
        for rows in 4...6 {
            let cell = MonthlyLogShareCalendarMetrics.cellSize(
                availableWidth: 312,
                availableHeight: 280,
                rowCount: rows,
                spacing: 3
            )
            #expect(abs(cell.width / cell.height - MonthlyLogShareCalendarMetrics.cellAspectRatio) < 0.001)
            let grid = MonthlyLogShareCalendarMetrics.gridSize(cell: cell, rowCount: rows, spacing: 3)
            #expect(grid.width <= 312 + 0.01)
            #expect(grid.height <= 280 + 0.01)
        }
        #expect(abs(MonthlyLogShareCalendarMetrics.cellAspectRatio - CGFloat(2) / CGFloat(3)) < 0.0001)
    }

    @Test func verticalMonthNameShrinksToFitShortCalendar() {
        let preferred: CGFloat = 54
        let available: CGFloat = 180
        let size = MonthlyLogShareVerticalMonthMetrics.fittedFontSize(
            text: "February",
            preferredSize: preferred,
            weight: .bold,
            availableLength: available
        )
        #expect(size < preferred)
        #expect(size >= MonthlyLogShareVerticalMonthMetrics.minimumMonthFont)
        let length = MonthlyLogShareVerticalMonthMetrics.textLength(
            "February",
            size: size,
            weight: .bold
        )
        #expect(length <= available + 0.01)
    }

    @Test func verticalMonthNameKeepsPreferredSizeWhenItFits() {
        let preferred: CGFloat = 54
        let size = MonthlyLogShareVerticalMonthMetrics.fittedFontSize(
            text: "May",
            preferredSize: preferred,
            weight: .bold,
            availableLength: 400
        )
        #expect(size == preferred)
    }

    @Test func monthAndWeekdayDoNotDependOnAppLanguage() {
        let books = [book(id: "a", day: 6, price: 500)]
        let ja = snapshot(books: books, locale: Locale(identifier: "ja"))
        let ko = snapshot(books: books, locale: Locale(identifier: "ko"))
        #expect(MonthlyLogShareTemplate.verticalMonth.monthHeadline(month: 8) == "August")
        #expect(MonthlyLogShareTemplate.largeMonth.monthHeadline(month: 8) == "Aug")
        #expect(png(ja, .verticalMonth) == png(ko, .verticalMonth))
        #expect(png(ja, .largeMonth) == png(ko, .largeMonth))
    }

    private func hasTransparentCorner(_ image: CGImage) -> Bool {
        guard let provider = image.dataProvider, let data = provider.data else { return false }
        let pointer = CFDataGetBytePtr(data)
        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else { return false }
        let alphaIndex: Int
        switch image.alphaInfo {
        case .premultipliedFirst, .first:
            alphaIndex = 0
        default:
            alphaIndex = bytesPerPixel - 1
        }
        return pointer?[alphaIndex] == 0
    }
}
