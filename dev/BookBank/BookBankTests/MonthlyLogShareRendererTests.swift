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
        locale: Locale = Locale(identifier: "ja"),
        firstWeekday: Int = 1
    ) -> MonthlyLogShareSnapshot {
        var calendar = calendar()
        calendar.firstWeekday = firstWeekday
        return MonthlyLogShareSnapshot.make(
            year: year,
            month: month,
            passbookBooks: books,
            displayCurrency: .jpy,
            exchangeRates: .shared,
            calendar: calendar,
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

    @Test func shareCanvasKeepsZeroLineSpacing() {
        #expect(AppTypography.shareImageLineSpacing == 0)
        #expect(AppTypography.interfaceLineSpacing(for: .japanese) == 1)
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

    @Test func canvasFormatsAreBoundToTemplatesNotDisplayOrder() {
        #expect(MonthlyLogShareTemplate.calendarSummary.canvasFormat == .portrait)
        #expect(MonthlyLogShareTemplate.largeMonth.canvasFormat == .portrait)
        #expect(MonthlyLogShareTemplate.verticalMonth.canvasFormat == .portraitFourFive)
        #expect(MonthlyLogShareTemplate.minimalSummary.canvasFormat == .square)

        #expect(MonthlyLogShareCanvasFormat.portrait.logicalSize == CGSize(width: 360, height: 640))
        #expect(MonthlyLogShareCanvasFormat.portraitFourFive.logicalSize == CGSize(width: 360, height: 450))
        #expect(MonthlyLogShareCanvasFormat.square.logicalSize == CGSize(width: 360, height: 360))
        #expect(MonthlyLogShareCanvasFormat.portrait.masterPixelSize == CGSize(width: 1080, height: 1920))
        #expect(MonthlyLogShareCanvasFormat.portraitFourFive.masterPixelSize == CGSize(width: 1080, height: 1350))
        #expect(MonthlyLogShareCanvasFormat.square.masterPixelSize == CGSize(width: 1080, height: 1080))
        #expect(MonthlyLogShareCanvasFormat.portrait.shouldTrimTransparentMargins)
        #expect(!MonthlyLogShareCanvasFormat.portraitFourFive.shouldTrimTransparentMargins)
        #expect(!MonthlyLogShareCanvasFormat.square.shouldTrimTransparentMargins)

        let reordered: [MonthlyLogShareTemplate] = [
            .minimalSummary, .verticalMonth, .largeMonth, .calendarSummary
        ]
        #expect(reordered[0].canvasFormat == .square)
        #expect(reordered[1].canvasFormat == .portraitFourFive)
        #expect(reordered[2].canvasFormat == .portrait)
        #expect(reordered[3].canvasFormat == .portrait)
        #expect(MonthlyLogShareTemplate.verticalMonth.canvasFormat == .portraitFourFive)
        #expect(MonthlyLogShareTemplate.minimalSummary.canvasFormat == .square)
    }

    @Test func fourToSixRowMonthsRenderExpectedExport() throws {
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
            try assertPortraitMasterAndCroppedExport(monthSnapshot, .calendarSummary)
            try assertPreservedCanvasExport(monthSnapshot, .verticalMonth)
        }
    }

    @Test func allTemplatesRenderExpectedExport() throws {
        let snapshot = snapshot(books: [book(id: "a", day: 16, price: 1200)])
        #expect(snapshot.layout.rowCount == 6)
        for template in MonthlyLogShareTemplate.allCases {
            if template.canvasFormat.shouldTrimTransparentMargins {
                try assertPortraitMasterAndCroppedExport(snapshot, template)
            } else {
                try assertPreservedCanvasExport(snapshot, template)
            }
            let data = png(snapshot, template)
            let export = try #require(
                MonthlyLogShareRenderer.exportImage(
                    snapshot: snapshot,
                    covers: [:],
                    template: template
                )
            )
            #expect(data == export.pngData(), "コピー・保存・共有は同じPNG")
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
        #expect(MonthlyLogShareCalendarMetrics.emptyShareCellOpacity == 0.20)
        for rows in 4...6 {
            let layout = MonthlyLogShareTemplateLayout.make(template: .verticalMonth, rowCount: rows)
            let cell = MonthlyLogShareCalendarMetrics.cellSize(
                availableWidth: 260,
                availableHeight: 220,
                rowCount: rows,
                spacing: layout.gridSpacing
            )
            #expect(abs(cell.width / cell.height - MonthlyLogShareCalendarMetrics.cellAspectRatio) < 0.001)
            let grid = MonthlyLogShareCalendarMetrics.gridSize(
                cell: cell,
                rowCount: rows,
                spacing: layout.gridSpacing
            )
            #expect(grid.width <= 260 + 0.01)
            #expect(grid.height <= 220 + 0.01)
        }
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

    @Test func verticalMonthUsesConsistentAugustLabelSizeForFourToSixRows() {
        for rows in 4...6 {
            let layout = MonthlyLogShareTemplateLayout.make(template: .verticalMonth, rowCount: rows)
            #expect(layout.monthFont == 34)
            #expect(layout.yearFont == 12)
        }
        let february = snapshot(
            year: 2026,
            month: 2,
            books: [book(id: "feb", year: 2026, month: 2, day: 10, price: 800)]
        )
        let august = snapshot(
            year: 2026,
            month: 8,
            books: [book(id: "aug", year: 2026, month: 8, day: 16, price: 800)]
        )
        #expect(february.layout.rowCount == 4)
        #expect(august.layout.rowCount == 6)
        let februaryLayout = MonthlyLogShareTemplateLayout.make(
            template: .verticalMonth,
            rowCount: february.layout.rowCount
        )
        let augustLayout = MonthlyLogShareTemplateLayout.make(
            template: .verticalMonth,
            rowCount: august.layout.rowCount
        )
        #expect(februaryLayout.monthFont == augustLayout.monthFont)
        #expect(februaryLayout.yearFont == augustLayout.yearFont)
    }

    @Test func verticalMonthKeepsThirtyFourPointNamesWhenProductionColumnFits() {
        let preferred: CGFloat = 34
        for rows in 4...6 {
            let available = verticalMonthProductionColumnHeight(rowCount: rows)
            for month in 1...12 {
                let name = MonthlyLogShareEnglishLabels.fullMonthName(month)
                let size = MonthlyLogShareVerticalMonthMetrics.fittedFontSize(
                    text: name,
                    preferredSize: preferred,
                    weight: .bold,
                    availableLength: available
                )
                #expect(size == preferred, "\(name) rows=\(rows) available=\(available)")
            }
        }
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

    @Test func japaneseAmountTemplatesKeepContentInsetFromEdges() throws {
        let snapshot = snapshot(
            books: [book(id: "yen", day: 16, price: 472_511)],
            locale: Locale(identifier: "ja")
        )
        try assertPortraitMasterAndCroppedExport(snapshot, .calendarSummary)
        try assertPreservedCanvasExport(snapshot, .minimalSummary)
        for template in [MonthlyLogShareTemplate.calendarSummary, .minimalSummary] {
            let data = png(snapshot, template)
            let image = try #require(UIImage(data: data))
            let cgImage = try #require(image.cgImage)
            let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
            #expect(opaque.minX >= 1, "\(template) 左端に文字が接しない")
            #expect(opaque.minY >= 1, "\(template) 上端に文字が接しない")
            #expect(opaque.maxX <= CGFloat(cgImage.width) - 1, "\(template) 右端に文字が接しない")
            #expect(opaque.maxY <= CGFloat(cgImage.height) - 1, "\(template) 下端に文字が接しない")
        }
    }

    @Test func localizedAmountsStayInsideSquareMinimalSummary() throws {
        let locales = ["ja", "en", "ko", "zh-Hans", "zh-Hant"]
        for identifier in locales {
            let monthSnapshot = snapshot(
                books: [book(id: "long-\(identifier)", day: 16, price: 1_234_567)],
                locale: Locale(identifier: identifier)
            )
            try assertPreservedCanvasExport(monthSnapshot, .minimalSummary)
            let data = png(monthSnapshot, .minimalSummary)
            let image = try #require(UIImage(data: data))
            let cgImage = try #require(image.cgImage)
            let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
            #expect(opaque.minX >= 8, "\(identifier) 左端に接しない")
            #expect(opaque.maxX <= CGFloat(cgImage.width) - 8, "\(identifier) 右端に接しない")
        }
    }

    @Test func verticalMonthKeepsLongMonthNamesAndWeekStart() throws {
        for month in [1, 2, 9] {
            let monthSnapshot = snapshot(
                year: 2026,
                month: month,
                books: [book(id: "long-\(month)", year: 2026, month: month, day: 10, price: 800)]
            )
            try assertPreservedCanvasExport(monthSnapshot, .verticalMonth)
            let image = try #require(
                MonthlyLogShareRenderer.exportImage(
                    snapshot: monthSnapshot,
                    covers: [:],
                    template: .verticalMonth
                )
            )
            let cgImage = try #require(image.cgImage)
            let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
            #expect(opaque.minX >= 1)
            #expect(opaque.maxX <= CGFloat(cgImage.width) - 1)
            #expect(opaque.minY >= 1)
            #expect(opaque.maxY <= CGFloat(cgImage.height) - 1)
        }

        let sunday = snapshot(
            books: [book(id: "week", day: 16, price: 500)],
            firstWeekday: 1
        )
        let monday = snapshot(
            books: [book(id: "week", day: 16, price: 500)],
            firstWeekday: 2
        )
        #expect(png(sunday, .verticalMonth) != png(monday, .verticalMonth))
    }

    @Test func verticalMonthExportsFourFiveForEveryMonth() throws {
        for month in 1...12 {
            let monthSnapshot = snapshot(
                year: 2026,
                month: month,
                books: [book(id: "all-\(month)", year: 2026, month: month, day: 10, price: 800)]
            )
            try assertPreservedCanvasExport(monthSnapshot, .verticalMonth)
            #expect(monthSnapshot.layout.rowCount >= 4)
            #expect(monthSnapshot.layout.rowCount <= 6)
        }
    }

    @Test func preservedCanvasTemplatesIncludeWordmarkAndKeepAlphaWithoutCheckerboard() throws {
        let empty = snapshot(books: [])
        let extras = snapshot(books: [
            book(id: "first", day: 16, price: 800),
            book(id: "second", day: 16, price: 400)
        ])
        #expect(extras.layout.days.contains { $0.extraCount > 0 })

        for template in [MonthlyLogShareTemplate.verticalMonth, .minimalSummary] {
            try assertPreservedCanvasExport(empty, template)
            let image = try #require(
                MonthlyLogShareRenderer.exportImage(
                    snapshot: extras,
                    covers: [:],
                    template: template
                )
            )
            let cgImage = try #require(image.cgImage)
            let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
            #expect(opaque.minX > 0 && opaque.minY > 0, "市松を含めない")
            #expect(opaque.maxX < CGFloat(cgImage.width) && opaque.maxY < CGFloat(cgImage.height))
            #expect(opaque.maxY > CGFloat(cgImage.height) * 0.55, "下部にワードマークがある")
        }
        #expect(png(empty, .verticalMonth) != png(extras, .verticalMonth))
        #expect(png(empty, .minimalSummary) != png(extras, .minimalSummary))
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

    private func assertPortraitMasterAndCroppedExport(
        _ snapshot: MonthlyLogShareSnapshot,
        _ template: MonthlyLogShareTemplate
    ) throws {
        #expect(template.canvasFormat == .portrait)
        let master = try #require(
            MonthlyLogShareRenderer.masterImage(
                snapshot: snapshot,
                covers: [:],
                template: template
            )
        )
        let masterCG = try #require(master.cgImage)
        #expect(masterCG.width == 1080)
        #expect(masterCG.height == 1920)

        let data = png(snapshot, template)
        let image = try #require(UIImage(data: data))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width <= masterCG.width)
        #expect(cgImage.height <= masterCG.height)
        #expect(cgImage.width < masterCG.width || cgImage.height < masterCG.height)
        try assertHasAlpha(cgImage)

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

    private func assertPreservedCanvasExport(
        _ snapshot: MonthlyLogShareSnapshot,
        _ template: MonthlyLogShareTemplate
    ) throws {
        #expect(!template.canvasFormat.shouldTrimTransparentMargins)
        let expected = template.canvasFormat.masterPixelSize
        let expectedWidth = Int(expected.width)
        let expectedHeight = Int(expected.height)
        let master = try #require(
            MonthlyLogShareRenderer.masterImage(
                snapshot: snapshot,
                covers: [:],
                template: template
            )
        )
        let masterCG = try #require(master.cgImage)
        #expect(masterCG.width == expectedWidth)
        #expect(masterCG.height == expectedHeight)

        let export = try #require(
            MonthlyLogShareRenderer.exportImage(
                snapshot: snapshot,
                covers: [:],
                template: template
            )
        )
        let exportCG = try #require(export.cgImage)
        #expect(exportCG.width == expectedWidth)
        #expect(exportCG.height == expectedHeight)
        try assertHasAlpha(exportCG)
        let opaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: exportCG))
        #expect(opaque.width > 0 && opaque.height > 0, "完全透明ではない")
    }

    /// 4:5 verticalMonth の本番配置と同じ列の長さ（回転月名が使える高さ）。
    private func verticalMonthProductionColumnHeight(rowCount: Int) -> CGFloat {
        let layout = MonthlyLogShareTemplateLayout.make(template: .verticalMonth, rowCount: rowCount)
        let canvas = MonthlyLogShareCanvasFormat.portraitFourFive.logicalSize
        let wordmarkBlock = layout.wordmarkSize + 16 + 20
        let availableHeight = max(1, canvas.height - layout.topPadding - wordmarkBlock)
        let availableWidth = max(1, canvas.width - layout.horizontalPadding * 2)
        let monthLine = AppTypography.fixedUIFont(
            size: layout.monthFont, weight: .bold, language: .english
        ).lineHeight
        let yearLine = AppTypography.fixedUIFont(
            size: layout.yearFont, weight: .bold, language: .english
        ).lineHeight
        let labelWidth = monthLine + yearLine - 4
        let weekdayLine = AppTypography.fixedUIFont(
            size: layout.weekdayFont, weight: .bold, language: .english
        ).lineHeight
        let reserved = weekdayLine + 8
        let raw = MonthlyLogShareCalendarMetrics.cellSize(
            availableWidth: max(1, availableWidth - labelWidth - 10),
            availableHeight: max(1, availableHeight - reserved),
            rowCount: rowCount,
            spacing: layout.gridSpacing
        )
        let cell = CGSize(
            width: raw.width * layout.cellScale,
            height: raw.height * layout.cellScale
        )
        let grid = MonthlyLogShareCalendarMetrics.gridSize(
            cell: cell,
            rowCount: rowCount,
            spacing: layout.gridSpacing
        )
        return reserved + grid.height
    }

    private func assertHasAlpha(_ image: CGImage) throws {
        let alpha = image.alphaInfo
        #expect(
            alpha == .premultipliedLast
                || alpha == .premultipliedFirst
                || alpha == .last
                || alpha == .first
        )
    }

}
