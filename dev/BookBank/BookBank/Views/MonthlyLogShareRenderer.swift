import SwiftUI
import UIKit

enum MonthlyLogShareRenderer {
    static let logicalSize = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3
    /// 内部マスターの画素数。最終 PNG はクロップ後の可変サイズ。
    static let masterPixelSize = CGSize(width: 1080, height: 1920)

    /// コピー・保存・共有へ渡す、トリミング済み PNG。
    @MainActor
    static func pngData(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate
    ) -> Data? {
        guard let image = exportImage(snapshot: snapshot, covers: covers, template: template) else {
            return nil
        }
        return image.pngData()
    }

    /// アルファ境界＋24px を切り出したエクスポート画像。
    @MainActor
    static func exportImage(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate
    ) -> UIImage? {
        guard let master = masterImage(snapshot: snapshot, covers: covers, template: template) else {
            return nil
        }
        return MonthlyLogShareImageTrimmer.cropToOpaqueContent(master)
    }

    /// 1080×1920 の透明マスター。テンプレート配置はここでは変えない。
    @MainActor
    static func masterImage(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: MonthlyLogShareCanvas(
                snapshot: snapshot,
                covers: covers,
                template: template
            )
            .frame(width: logicalSize.width, height: logicalSize.height)
        )
        renderer.proposedSize = ProposedViewSize(width: logicalSize.width, height: logicalSize.height)
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

/// プレビューと保存出力で共用するテンプレート。背景は透明（市松は含めない）。
struct MonthlyLogShareCanvas: View {
    private static let shareCellScale: CGFloat = 0.86
    private static let verticalMonthCellScale: CGFloat = 0.92

    let snapshot: MonthlyLogShareSnapshot
    let covers: [String: UIImage]
    let template: MonthlyLogShareTemplate

    private var layout: MonthlyLogShareTemplateLayout {
        MonthlyLogShareTemplateLayout.make(template: template, rowCount: snapshot.layout.rowCount)
    }

    var body: some View {
        ZStack {
            Color.clear
            switch template {
            case .calendarSummary:
                calendarSummary
            case .verticalMonth:
                verticalMonth
            case .largeMonth:
                largeMonth
            case .minimalSummary:
                minimalSummary
            }
        }
        .frame(width: MonthlyLogShareRenderer.logicalSize.width, height: MonthlyLogShareRenderer.logicalSize.height)
        .foregroundStyle(.white)
        .lineSpacing(AppTypography.shareImageLineSpacing)
    }

    // MARK: - Template 1

    private var calendarSummary: some View {
        VStack(spacing: 0) {
            alignedCalendarBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            wordmark
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 月・金額・曜日・カレンダーを縮小後の実グリッド幅で揃え、下端を BookBank に固定する。
    private var alignedCalendarBlock: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let amountTop: CGFloat = snapshot.layout.rowCount >= 6 ? 28 : 44
            let weekdayTop: CGFloat = snapshot.layout.rowCount >= 6 ? 14 : 24
            let monthHeight = layout.topPadding + layout.monthFont + 2 + layout.yearFont
            let amountHeight = 11 + 4 + layout.amountFont + 2
            let weekdayHeight = layout.weekdayFont + 2
            let reserved = monthHeight + amountTop + amountHeight + weekdayTop + weekdayHeight + 8
            let metrics = scaledGridMetrics(
                availableWidth: geo.size.width,
                availableHeight: max(1, geo.size.height - reserved),
                spacing: spacing
            )

            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Text(verbatim: template.monthHeadline(month: snapshot.month))
                        .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                    Text(verbatim: String(snapshot.year))
                        .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                        .padding(.top, -10)
                }
                .padding(.top, layout.topPadding)
                calendarSummaryAmountRow
                    .padding(.top, amountTop)
                weekdayHeader
                    .padding(.top, weekdayTop)
                calendarGrid(cell: metrics.cell, spacing: spacing)
                    .frame(width: metrics.grid.width, height: metrics.grid.height)
                    .padding(.top, 8)
            }
            .frame(width: metrics.grid.width, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Template 2

    private var verticalMonth: some View {
        VStack(spacing: 0) {
            alignedVerticalMonthBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 8)
                .padding(.trailing, layout.horizontalPadding)
            wordmark
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
    }

    /// 曜日幅を実セル幅に合わせ、カレンダー下端を BookBank に固定する。
    private var alignedVerticalMonthBlock: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let monthName = MonthlyLogShareEnglishLabels.fullMonthName(snapshot.month)
            let year = String(snapshot.year)
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
            let metrics = scaledGridMetrics(
                availableWidth: max(1, geo.size.width - labelWidth - 10),
                availableHeight: max(1, geo.size.height - reserved),
                spacing: spacing
            )
            let columnHeight = reserved + metrics.grid.height
            let monthSize = MonthlyLogShareVerticalMonthMetrics.fittedFontSize(
                text: monthName,
                preferredSize: layout.monthFont,
                weight: .bold,
                availableLength: columnHeight
            )
            let scale = layout.monthFont > 0 ? monthSize / layout.monthFont : 1
            let yearSize = max(
                MonthlyLogShareVerticalMonthMetrics.minimumYearFont,
                floor(layout.yearFont * scale)
            )

            HStack(alignment: .top, spacing: 10) {
                verticalMonthLabel(month: monthName, year: year, monthSize: monthSize, yearSize: yearSize)
                VStack(alignment: .leading, spacing: 8) {
                    weekdayHeader(cellWidth: metrics.cell.width, spacing: spacing)
                    calendarGrid(cell: metrics.cell, spacing: spacing)
                        .frame(width: metrics.grid.width, height: metrics.grid.height)
                }
                .frame(width: metrics.grid.width, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private func verticalMonthLabel(
        month: String,
        year: String,
        monthSize: CGFloat,
        yearSize: CGFloat
    ) -> some View {
        let monthFont = AppTypography.fixedUIFont(size: monthSize, weight: .bold, language: .english)
        let yearFont = AppTypography.fixedUIFont(size: yearSize, weight: .bold, language: .english)
        return HStack(alignment: .top, spacing: -4) {
            rotatedShareLabel(month, font: monthFont)
            rotatedShareLabel(year, font: yearFont)
        }
    }

    private func rotatedShareLabel(_ text: String, font: UIFont) -> some View {
        let length = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return Text(verbatim: text)
            .font(Font(font))
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: font.lineHeight, height: length)
    }

    // MARK: - Template 3

    private var largeMonth: some View {
        VStack(spacing: 0) {
            alignedLargeMonthBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            wordmark
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    /// 月・曜日・カレンダーを実グリッド幅で中央に置き、下端を BookBank に固定する。
    private var alignedLargeMonthBlock: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let weekdayTop: CGFloat = snapshot.layout.rowCount >= 6 ? 24 : 36
            let monthHeight = layout.topPadding + layout.monthFont
            let weekdayHeight = layout.weekdayFont + 2
            let reserved = monthHeight + weekdayTop + weekdayHeight + 8
            let metrics = scaledGridMetrics(
                availableWidth: geo.size.width,
                availableHeight: max(1, geo.size.height - reserved),
                spacing: spacing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(verbatim: template.monthHeadline(month: snapshot.month))
                        .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                    Spacer(minLength: 8)
                    Text(verbatim: String(snapshot.year))
                        .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                }
                .frame(width: metrics.grid.width)
                .padding(.top, layout.topPadding)
                weekdayHeader(cellWidth: metrics.cell.width, spacing: spacing)
                    .padding(.top, weekdayTop)
                calendarGrid(cell: metrics.cell, spacing: spacing)
                    .frame(width: metrics.grid.width, height: metrics.grid.height)
                    .padding(.top, 8)
            }
            .frame(width: metrics.grid.width, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Template 4

    private var minimalSummary: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)
            Text(verbatim: template.monthHeadline(month: snapshot.month))
                .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
            Text(verbatim: String(snapshot.year))
                .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                .padding(.top, -10)
            minimalSummaryAmountRow
                .padding(.top, 36)
            Spacer(minLength: 24)
            wordmark
            Spacer(minLength: 80)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    // MARK: - Shared pieces

    private var calendarSummaryAmountRow: some View {
        HStack(alignment: .top, spacing: 12) {
            amountBlock(
                label: L10n.string("statistics.yearly_amount", locale: snapshot.locale),
                value: amountParts,
                alignment: .center
            )
            Spacer(minLength: 8)
            amountBlock(
                label: L10n.string("statistics.book_count", locale: snapshot.locale),
                value: bookCountParts,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var minimalSummaryAmountRow: some View {
        HStack(alignment: .top, spacing: 36) {
            amountBlock(
                label: L10n.string("statistics.yearly_amount", locale: snapshot.locale),
                value: amountParts,
                alignment: .center
            )
            amountBlock(
                label: L10n.string("statistics.book_count", locale: snapshot.locale),
                value: bookCountParts,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func amountBlock(
        label: String,
        value: (prefix: String, amount: String, suffix: String),
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        let language = AppTypography.language(from: snapshot.locale)
        return VStack(alignment: alignment, spacing: 4) {
            Text(verbatim: label)
                .font(.appFixed(size: 11, weight: .regular, language: language))
                .opacity(0.7)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if !value.prefix.isEmpty {
                    Text(verbatim: value.prefix)
                        .font(.appFixed(size: 20, weight: .bold, language: language))
                }
                Text(verbatim: value.amount)
                    .font(.appFixed(size: layout.amountFont, weight: .bold, language: language))
                if !value.suffix.isEmpty {
                    Text(verbatim: value.suffix)
                        .font(.appFixed(size: 20, weight: .bold, language: language))
                }
            }
        }
    }

    private var amountParts: (prefix: String, amount: String, suffix: String) {
        MoneyDisplay.formatParts(
            amount: snapshot.totalDisplayAmount,
            currency: snapshot.displayCurrency,
            locale: snapshot.locale
        )
    }

    private var bookCountParts: (prefix: String, amount: String, suffix: String) {
        (
            prefix: "",
            amount: snapshot.bookCount.decimalString(locale: snapshot.locale),
            suffix: L10n.string("common.books_count.unit", locale: snapshot.locale)
        )
    }

    private var weekdayHeader: some View {
        weekdayHeader(cellWidth: nil, spacing: layout.gridSpacing)
    }

    private func weekdayHeader(cellWidth: CGFloat?, spacing: CGFloat) -> some View {
        let symbols = MonthlyLogShareEnglishLabels.weekdayAbbreviations(firstWeekday: snapshot.firstWeekday)
        return HStack(spacing: spacing) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.appFixed(size: layout.weekdayFont, weight: .bold, language: .english))
                    .opacity(0.85)
                    .frame(width: cellWidth, alignment: .center)
                    .frame(maxWidth: cellWidth == nil ? .infinity : nil)
            }
        }
    }

    private var shareCalendarGrid: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let metrics = scaledGridMetrics(
                availableWidth: geo.size.width,
                availableHeight: geo.size.height,
                spacing: spacing
            )
            calendarGrid(cell: metrics.cell, spacing: spacing)
                .frame(width: metrics.grid.width, height: metrics.grid.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func scaledGridMetrics(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        spacing: CGFloat
    ) -> (cell: CGSize, grid: CGSize) {
        let cellScale = template == .verticalMonth
            ? Self.verticalMonthCellScale
            : Self.shareCellScale
        let raw = MonthlyLogShareCalendarMetrics.cellSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            rowCount: snapshot.layout.rowCount,
            spacing: spacing
        )
        let cell = CGSize(
            width: raw.width * cellScale,
            height: raw.height * cellScale
        )
        let grid = MonthlyLogShareCalendarMetrics.gridSize(
            cell: cell,
            rowCount: snapshot.layout.rowCount,
            spacing: spacing
        )
        return (cell, grid)
    }

    private func calendarGrid(cell: CGSize, spacing: CGFloat) -> some View {
        let columns = Array(
            repeating: GridItem(.fixed(cell.width), spacing: spacing),
            count: MonthlyLogShareCalendarMetrics.columnCount
        )
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<snapshot.layout.leadingBlankCount, id: \.self) { index in
                blankShareCell(size: cell)
                    .id("share-blank-\(index)")
            }
            ForEach(snapshot.layout.days) { day in
                shareDayCell(day, size: cell)
            }
        }
    }

    @ViewBuilder
    private func shareDayCell(_ day: MonthlyCalendarLayout.Day, size: CGSize) -> some View {
        if let book = day.representative {
            filledShareCell(day: day.day, book: book, extraCount: day.extraCount, size: size)
        } else {
            emptyShareCell(day: day.day, size: size)
        }
    }

    private func filledShareCell(day: Int, book: BookDTO, extraCount: Int, size: CGSize) -> some View {
        ZStack {
            if let cover = covers[book.id] {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.14))
            }
            Color.black.opacity(covers[book.id] == nil ? 0 : 0.22)
            Text(verbatim: "\(day)")
                .font(.appFixed(size: layout.dateFont, weight: .regular, language: .english))
        }
        .frame(width: size.width, height: size.height)
        .aspectRatio(MonthlyLogShareCalendarMetrics.cellAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(alignment: .topTrailing) {
            if extraCount > 0 {
                Text(verbatim: "+\(extraCount)")
                    .font(.appFixed(size: layout.badgeFont, weight: .bold, language: .english))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(2)
            }
        }
    }

    private func blankShareCell(size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .aspectRatio(MonthlyLogShareCalendarMetrics.cellAspectRatio, contentMode: .fit)
    }

    private func emptyShareCell(day: Int, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.14))
            .frame(width: size.width, height: size.height)
            .aspectRatio(MonthlyLogShareCalendarMetrics.cellAspectRatio, contentMode: .fit)
            .overlay {
                Text(verbatim: "\(day)")
                    .font(.appFixed(size: layout.dateFont, weight: .regular, language: .english))
            }
    }

    private var wordmark: some View {
        Image("img_bookbank_logo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: layout.wordmarkSize)
            .accessibilityLabel(L10n.string("brand.bookbank", locale: snapshot.locale))
    }
}

private extension Int {
    func decimalString(locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
