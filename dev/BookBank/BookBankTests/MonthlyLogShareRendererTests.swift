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

    private func book(
        id: String,
        year: Int = 2026,
        month: Int = 8,
        day: Int,
        price: Int?
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
        year: Int = 2026,
        month: Int = 8,
        books: [BookDTO],
        locale: Locale = Locale(identifier: "ja")
    ) -> MonthlyLogShareSnapshot {
        MonthlyLogShareSnapshot.make(
            year: year,
            month: month,
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

    @Test func fourToSixRowMonthsRenderCroppedTransparentPNG() throws {
        let cases: [(month: Int, day: Int, rows: Int)] = [
            (2, 10, 4),
            (1, 10, 5),
            (8, 16, 6)
        ]
        for item in cases {
            let monthSnapshot = snapshot(
                year: 2026,
                month: item.month,
                books: [book(id: "m\(item.month)", year: 2026, month: item.month, day: item.day, price: 800)]
            )
            #expect(monthSnapshot.layout.rowCount == item.rows)
            try assertMasterAndCroppedExport(monthSnapshot, .calendarSummary)
        }
    }

    @Test func allTemplatesRenderCroppedTransparentPNG() throws {
        let snapshot = snapshot(books: [book(id: "a", day: 16, price: 1200)])
        #expect(snapshot.layout.rowCount == 6)
        for template in MonthlyLogShareTemplate.allCases {
            try assertMasterAndCroppedExport(snapshot, template)
            let data = png(snapshot, template)
            let export = try #require(
                MonthlyLogShareRenderer.exportImage(
                    snapshot: snapshot,
                    covers: [:],
                    template: template
                )
            )
            #expect(data == export.pngData(), "コピー・保存・共有は同じトリミング済みPNG")
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

    @Test func verticalMonthMeasurementMatchesEnglishDrawingFont() {
        let size: CGFloat = 54
        let drawing = AppTypography.fixedUIFont(size: size, weight: .bold, language: .english)
        let length = MonthlyLogShareVerticalMonthMetrics.textLength(
            "February",
            size: size,
            weight: .bold
        )
        let measured = ceil(("February" as NSString).size(withAttributes: [.font: drawing]).width)
        #expect(length == measured)
        #expect(
            drawing.fontName == AppTypography.enBoldName
                || drawing.fontName.contains("LINESeedSans")
        )
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

    private func assertMasterAndCroppedExport(
        _ snapshot: MonthlyLogShareSnapshot,
        _ template: MonthlyLogShareTemplate
    ) throws {
        let master = try #require(
            MonthlyLogShareRenderer.masterImage(
                snapshot: snapshot,
                covers: [:],
                template: template
            )
        )
        let masterCG = try #require(master.cgImage)
        #expect(masterCG.width == Int(MonthlyLogShareRenderer.masterPixelSize.width))
        #expect(masterCG.height == Int(MonthlyLogShareRenderer.masterPixelSize.height))

        let data = png(snapshot, template)
        let image = try #require(UIImage(data: data))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width <= masterCG.width)
        #expect(cgImage.height <= masterCG.height)
        #expect(cgImage.width < masterCG.width || cgImage.height < masterCG.height)
        let alpha = cgImage.alphaInfo
        #expect(
            alpha == .premultipliedLast
                || alpha == .premultipliedFirst
                || alpha == .last
                || alpha == .first
        )

        let masterOpaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: masterCG))
        let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
        let expectedLeft = min(24, Int(masterOpaque.minX.rounded(.towardZero)))
        let expectedTop = min(24, Int(masterOpaque.minY.rounded(.towardZero)))
        let expectedRight = min(24, masterCG.width - Int(masterOpaque.maxX.rounded(.towardZero)))
        let expectedBottom = min(24, masterCG.height - Int(masterOpaque.maxY.rounded(.towardZero)))
        #expect(Int(opaque.minX.rounded(.towardZero)) == expectedLeft, "\(template) 左余白")
        #expect(Int(opaque.minY.rounded(.towardZero)) == expectedTop, "\(template) 上余白")
        #expect(cgImage.width - Int(opaque.maxX.rounded(.towardZero)) == expectedRight, "\(template) 右余白")
        #expect(cgImage.height - Int(opaque.maxY.rounded(.towardZero)) == expectedBottom, "\(template) 下余白")
        #expect(opaque.minX > 0 || expectedLeft == 0)
        #expect(opaque.maxX < CGFloat(cgImage.width) || expectedRight == 0)
    }
}
