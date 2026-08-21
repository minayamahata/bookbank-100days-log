import SwiftUI
import UIKit

enum MonthlyLogShareRenderer {
    static let scale: CGFloat = 3
    static let jpegQuality: CGFloat = 0.95

    /// 背景モードに応じた出力。透明は PNG、白・黒は JPEG。
    @MainActor
    static func exportAsset(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate,
        mode: MonthlyLogShareBackgroundMode
    ) -> MonthlyLogShareExportAsset? {
        switch mode {
        case .transparent:
            guard let data = pngData(snapshot: snapshot, covers: covers, template: template) else {
                return nil
            }
            return MonthlyLogShareExportAsset(data: data, format: .png)
        case .white, .black:
            guard let master = masterImage(
                snapshot: snapshot,
                covers: covers,
                template: template,
                palette: mode.palette
            ) else {
                return nil
            }
            let background: UIColor = mode == .white ? .white : .black
            guard let data = flattenedJPEGData(master: master, background: background) else {
                return nil
            }
            return MonthlyLogShareExportAsset(data: data, format: .jpeg)
        }
    }

    /// コピー・保存・共有へ渡す透明 PNG。portrait はトリミング済み、ほかはマスター全体。
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

    /// portrait はアルファ境界＋24px。portraitFourFive / square はマスターをそのまま返す。
    @MainActor
    static func exportImage(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate
    ) -> UIImage? {
        guard let master = masterImage(snapshot: snapshot, covers: covers, template: template) else {
            return nil
        }
        if template.canvasFormat.shouldTrimTransparentMargins {
            return MonthlyLogShareImageTrimmer.cropToOpaqueContent(master)
        }
        return master
    }

    /// テンプレート形式の論理サイズで描画した透明マスター。
    @MainActor
    static func masterImage(
        snapshot: MonthlyLogShareSnapshot,
        covers: [String: UIImage],
        template: MonthlyLogShareTemplate,
        palette: MonthlyLogSharePalette = .light
    ) -> UIImage? {
        let logicalSize = template.canvasFormat.logicalSize
        let renderer = ImageRenderer(
            content: MonthlyLogShareCanvas(
                snapshot: snapshot,
                covers: covers,
                template: template,
                palette: palette
            )
            .frame(width: logicalSize.width, height: logicalSize.height)
        )
        renderer.proposedSize = ProposedViewSize(width: logicalSize.width, height: logicalSize.height)
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// 白／黒 JPEG 用。透明マスターを背景色の上へ焼き込み、マスター画素のまま不透明で返す。
    static func flattenedJPEGData(master: UIImage, background: UIColor) -> Data? {
        let pixelSize = CGSize(
            width: master.size.width * master.scale,
            height: master.size.height * master.scale
        )
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let flattened = renderer.image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            master.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        return flattened.jpegData(compressionQuality: jpegQuality)
    }
}

/// プレビューと保存出力で共用するテンプレート。背景は透明（市松は含めない）。
struct MonthlyLogShareCanvas: View {
    /// 1枚目の月数字と年の間隔。行箱を相殺したうえで 4pt 空ける。
    private static let calendarSummaryMonthYearSpacing: CGFloat = 4
    private static let calendarSummaryMonthYearOpticalOverlap: CGFloat = 18
    /// 3枚目だけ、細い月名＋重いカレンダーを視覚的に中央へ寄せる。
    private static let verticalMonthOpticalShift: CGFloat = 6

    let snapshot: MonthlyLogShareSnapshot
    let covers: [String: UIImage]
    let template: MonthlyLogShareTemplate
    var palette: MonthlyLogSharePalette = .light

    private var layout: MonthlyLogShareTemplateLayout {
        MonthlyLogShareTemplateLayout.make(template: template, rowCount: snapshot.layout.rowCount)
    }

    private var canvasSize: CGSize {
        template.canvasFormat.logicalSize
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
            case .monthInBooks:
                monthInBooks
            case .circledCalendar:
                circledCalendar
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .foregroundStyle(palette.foreground)
        .lineSpacing(AppTypography.shareImageLineSpacing)
    }

    // MARK: - Template 1

    /// 月・金額・曜日・カレンダー・ロゴを一体のコンテンツとして、カード縦方向の中央へ置く。
    private var calendarSummary: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let amountTop: CGFloat = snapshot.layout.rowCount >= 6 ? 28 : 44
            let weekdayTop: CGFloat = snapshot.layout.rowCount >= 6 ? 14 : 24
            let monthHeight = layout.monthFont + Self.calendarSummaryMonthYearSpacing + layout.yearFont
            let amountHeight = layout.amountFont + 2
            let weekdayHeight = layout.weekdayFont + 2
            let wordmarkBlock = 16 + layout.wordmarkSize
            let reserved = monthHeight + amountTop + amountHeight + weekdayTop + weekdayHeight + 8 + wordmarkBlock
            let metrics = scaledGridMetrics(
                availableWidth: geo.size.width,
                availableHeight: max(1, geo.size.height - reserved),
                spacing: spacing
            )

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: Self.calendarSummaryMonthYearSpacing) {
                        Text(verbatim: template.monthHeadline(month: snapshot.month))
                            .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                        Text(verbatim: String(snapshot.year))
                            .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                            .padding(.top, -Self.calendarSummaryMonthYearOpticalOverlap)
                    }
                    calendarSummaryAmountRow
                        .padding(.top, amountTop)
                    weekdayHeader
                        .padding(.top, weekdayTop)
                    calendarGrid(cell: metrics.cell, spacing: spacing)
                        .frame(width: metrics.grid.width, height: metrics.grid.height)
                        .padding(.top, 8)
                }
                .frame(width: metrics.grid.width, alignment: .leading)
                wordmark
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    // MARK: - Template 2

    /// 4:5 内で回転月名とカレンダーを並べ、ロゴまで含めたコンテンツをカード縦方向の中央へ置く。
    /// カレンダーとロゴの距離は1・2枚目と同じ 16pt。
    private var verticalMonth: some View {
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
            let wordmarkBlock = 16 + layout.wordmarkSize
            let reserved = weekdayLine + 8
            let metrics = scaledGridMetrics(
                availableWidth: max(1, geo.size.width - labelWidth - 10),
                availableHeight: max(1, geo.size.height - reserved - wordmarkBlock),
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

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    verticalMonthLabel(month: monthName, year: year, monthSize: monthSize, yearSize: yearSize)
                    VStack(alignment: .leading, spacing: 8) {
                        weekdayHeader(cellWidth: metrics.cell.width, spacing: spacing)
                        calendarGrid(cell: metrics.cell, spacing: spacing)
                            .frame(width: metrics.grid.width, height: metrics.grid.height)
                    }
                    .frame(width: metrics.grid.width, alignment: .leading)
                }
                // コンテンツ幅（回転月名＋カレンダー）に合わせ、カレンダーの右端へ揃える
                wordmark
                    .frame(width: labelWidth + 10 + metrics.grid.width, alignment: .trailing)
                    .padding(.top, 16)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .padding(.leading, layout.horizontalPadding - Self.verticalMonthOpticalShift)
        .padding(.trailing, layout.horizontalPadding + Self.verticalMonthOpticalShift)
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

    /// 月・曜日・カレンダー・ロゴを一体のコンテンツとして、カード縦方向の中央へ置く。ロゴは右揃え。
    private var largeMonth: some View {
        GeometryReader { geo in
            let spacing = layout.gridSpacing
            let weekdayTop: CGFloat = snapshot.layout.rowCount >= 6 ? 24 : 36
            let weekdayHeight = layout.weekdayFont + 2
            let wordmarkBlock = 16 + layout.wordmarkSize
            let reserved = layout.monthFont + weekdayTop + weekdayHeight + 8 + wordmarkBlock
            let metrics = scaledGridMetrics(
                availableWidth: geo.size.width,
                availableHeight: max(1, geo.size.height - reserved),
                spacing: spacing
            )

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text(verbatim: template.monthHeadline(month: snapshot.month))
                            .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                        Spacer(minLength: 8)
                        Text(verbatim: String(snapshot.year))
                            .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                    }
                    .frame(width: metrics.grid.width)
                    weekdayHeader(cellWidth: metrics.cell.width, spacing: spacing)
                        .padding(.top, weekdayTop)
                    calendarGrid(cell: metrics.cell, spacing: spacing)
                        .frame(width: metrics.grid.width, height: metrics.grid.height)
                        .padding(.top, 8)
                }
                .frame(width: metrics.grid.width, alignment: .leading)
                wordmark
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .padding(.horizontal, layout.horizontalPadding)
    }

    // MARK: - Template 4

    private var minimalSummary: some View {
        GeometryReader { geo in
            let inset = layout.horizontalPadding
            VStack(spacing: 0) {
                Spacer(minLength: 16)
                VStack(spacing: 0) {
                    Text(verbatim: template.monthHeadline(month: snapshot.month))
                        .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                    Text(verbatim: String(snapshot.year))
                        .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
                        .padding(.top, -8)
                }
                Spacer(minLength: 16)
                minimalSummaryAmountRow
                Spacer(minLength: 16)
                wordmark
                Spacer(minLength: 16)
            }
            .frame(width: max(1, geo.size.width - inset * 2), height: max(1, geo.size.height - 8))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 0)
    }

    // MARK: - Template: circledCalendar（書影なしの数字カレンダー）

    /// 読書日でない日付の数字の不透明度
    private static let circledCalendarIdleOpacity: CGFloat = 0.38

    /// 書影を使わず、読書日を丸い輪郭で示す 4:5 テンプレート。
    /// 中央揃えの月名＋年、数字カレンダー、ワードマーク。冊数・金額は載せない。
    private var circledCalendar: some View {
        let compact = snapshot.layout.rowCount >= 6
        let columnWidth = (canvasSize.width - layout.horizontalPadding * 2)
            / CGFloat(MonthlyLogShareCalendarMetrics.columnCount)
        let rowHeight: CGFloat = compact ? 38 : 44
        let circleDiameter: CGFloat = compact ? 32 : 36

        return VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(verbatim: MonthlyLogShareEnglishLabels.fullMonthName(snapshot.month))
                    .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
                Text(verbatim: String(snapshot.year))
                    .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
            }
            .frame(maxWidth: .infinity)
            weekdayHeader(cellWidth: columnWidth, spacing: 0)
                .padding(.top, compact ? 14 : 18)
            circledCalendarGrid(
                columnWidth: columnWidth,
                rowHeight: rowHeight,
                circleDiameter: circleDiameter
            )
            .padding(.top, compact ? 4 : 6)
            wordmark
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, layout.horizontalPadding)
    }

    private func circledCalendarGrid(
        columnWidth: CGFloat,
        rowHeight: CGFloat,
        circleDiameter: CGFloat
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.fixed(columnWidth), spacing: 0),
            count: MonthlyLogShareCalendarMetrics.columnCount
        )
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<snapshot.layout.leadingBlankCount, id: \.self) { index in
                Color.clear
                    .frame(width: columnWidth, height: rowHeight)
                    .id("circled-blank-\(index)")
            }
            ForEach(snapshot.layout.days) { day in
                ZStack {
                    if day.representative != nil {
                        Circle()
                            .stroke(palette.foreground, lineWidth: 1)
                            .frame(width: circleDiameter, height: circleDiameter)
                        Text(verbatim: "\(day.day)")
                            .font(.appFixed(size: layout.dateFont, weight: .bold, language: .english))
                    } else {
                        Text(verbatim: "\(day.day)")
                            .font(.appFixed(size: layout.dateFont, weight: .bold, language: .english))
                            .opacity(Self.circledCalendarIdleOpacity)
                    }
                }
                .frame(width: columnWidth, height: rowHeight)
            }
        }
    }

    // MARK: - Template 6

    /// 「My month in books」の2行タイトル。共有画像専用の英語固定文字列。
    /// `lineSpacing` は負値が 0 へクランプされるため、2つの Text を
    /// 負のパディングで重ねて行間を詰める（1枚目の月数字＋年と同じ方式）。
    private static let monthInBooksTitleLine1 = "My month"
    private static let monthInBooksTitleLine2 = " in books"
    private static let monthInBooksTitleLineOverlap: CGFloat = 8

    /// 左揃えの月名・年、タイトル、冊数、ワードマークを縦中央へ置く 1:1 テンプレート。
    private var monthInBooks: some View {
        let language = AppTypography.language(from: snapshot.locale)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: MonthlyLogShareEnglishLabels.fullMonthName(snapshot.month))
                Text(verbatim: String(snapshot.year))
            }
            .font(.appFixed(size: layout.yearFont, weight: .bold, language: .english))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: Self.monthInBooksTitleLine1)
                Text(verbatim: Self.monthInBooksTitleLine2)
                    .padding(.top, -Self.monthInBooksTitleLineOverlap)
            }
            .font(.appFixed(size: layout.monthFont, weight: .bold, language: .english))
            .padding(.top, 18)
            HStack(alignment: .top, spacing: 3) {
                Text(verbatim: snapshot.bookCount.decimalString(locale: snapshot.locale))
                    .font(.appFixed(size: layout.amountFont, weight: .bold, language: language))
                Text(verbatim: L10n.string("common.books_count.unit", locale: snapshot.locale))
                    .font(.appFixed(size: 11, weight: .regular, language: language))
                    .padding(.top, 2)
            }
            .padding(.top, 20)
            wordmark
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, layout.horizontalPadding)
    }

    // MARK: - Shared pieces

    private var calendarSummaryAmountRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            amountBlock(value: amountParts)
            Spacer(minLength: 8)
            amountBlock(value: bookCountParts)
        }
        .frame(maxWidth: .infinity)
    }

    private var minimalSummaryAmountRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 48) {
            amountBlock(value: amountParts, scalesToFit: true)
            amountBlock(value: bookCountParts, scalesToFit: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// 数値＋通貨記号・単位のみ。「合計金額」「冊数」の補足ラベルは付けない（2026-08-21）。
    private func amountBlock(
        value: (prefix: String, amount: String, suffix: String),
        scalesToFit: Bool = false
    ) -> some View {
        let language = AppTypography.language(from: snapshot.locale)
        return HStack(alignment: .lastTextBaseline, spacing: 2) {
            if !value.prefix.isEmpty {
                Text(verbatim: value.prefix)
                    .font(.appFixed(size: 14, weight: .bold, language: language))
            }
            Text(verbatim: value.amount)
                .font(.appFixed(size: layout.amountFont, weight: .bold, language: language))
            if !value.suffix.isEmpty {
                Text(verbatim: value.suffix)
                    .font(.appFixed(size: 14, weight: .bold, language: language))
            }
        }
        .lineLimit(scalesToFit ? 1 : nil)
        .minimumScaleFactor(scalesToFit ? 0.7 : 1)
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
        let cellScale = layout.cellScale
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
                    .fill(palette.coverPlaceholderFill)
            }
            Color.black.opacity(covers[book.id] == nil ? 0 : 0.22)
            Text(verbatim: "\(day)")
                .font(.appFixed(size: layout.dateFont, weight: .regular, language: .english))
                .foregroundStyle(
                    covers[book.id] == nil
                        ? palette.foreground
                        : MonthlyLogSharePalette.coverOverlayText
                )
        }
        .frame(width: size.width, height: size.height)
        .aspectRatio(MonthlyLogShareCalendarMetrics.cellAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(alignment: .topTrailing) {
            if extraCount > 0 {
                Text(verbatim: "+\(extraCount)")
                    .font(.appFixed(size: layout.badgeFont, weight: .bold, language: .english))
                    .foregroundStyle(MonthlyLogSharePalette.coverOverlayText)
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
            .fill(palette.emptyCellFill)
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
