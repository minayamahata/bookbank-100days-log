import CoreGraphics
import Foundation
import UIKit

/// 共有画像カレンダーのセル寸法。画面と同じ 2:3 を保ち、4〜6行でも枠内に収める。
enum MonthlyLogShareCalendarMetrics {
    static let cellAspectRatio: CGFloat = 2.0 / 3.0
    static let columnCount = 7
    /// 本が登録されていない日付セル。表紙なし登録済みセルの 0.14 とは別。
    static let emptyShareCellOpacity: CGFloat = 0.20

    static func cellSize(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        rowCount: Int,
        spacing: CGFloat
    ) -> CGSize {
        let rows = max(rowCount, 1)
        let columns = CGFloat(columnCount)
        let rowCountValue = CGFloat(rows)
        let maxCellWidth = max(0, (availableWidth - spacing * (columns - 1)) / columns)
        let maxCellHeight = max(0, (availableHeight - spacing * (rowCountValue - 1)) / rowCountValue)

        let heightIfWidthLimited = maxCellWidth / cellAspectRatio
        if heightIfWidthLimited <= maxCellHeight {
            return CGSize(width: maxCellWidth, height: heightIfWidthLimited)
        }
        return CGSize(width: maxCellHeight * cellAspectRatio, height: maxCellHeight)
    }

    static func gridSize(cell: CGSize, rowCount: Int, spacing: CGFloat) -> CGSize {
        let rows = max(rowCount, 1)
        let width = cell.width * CGFloat(columnCount) + spacing * CGFloat(columnCount - 1)
        let height = cell.height * CGFloat(rows) + spacing * CGFloat(rows - 1)
        return CGSize(width: width, height: height)
    }
}

struct MonthlyLogShareTemplateLayout: Equatable, Sendable {
    var monthFont: CGFloat
    var yearFont: CGFloat
    var amountFont: CGFloat
    var weekdayFont: CGFloat
    var dateFont: CGFloat
    var badgeFont: CGFloat
    var gridSpacing: CGFloat
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var wordmarkSize: CGFloat
    var cellScale: CGFloat

    static func make(template: MonthlyLogShareTemplate, rowCount: Int) -> MonthlyLogShareTemplateLayout {
        let compact = rowCount >= 6
        switch template {
        case .calendarSummary:
            return MonthlyLogShareTemplateLayout(
                monthFont: compact ? 62 : 84,
                yearFont: compact ? 15 : 19,
                amountFont: compact ? 28 : 36,
                weekdayFont: compact ? 10 : 11,
                dateFont: compact ? 9 : 11,
                badgeFont: compact ? 6 : 7,
                gridSpacing: compact ? 2 : 3,
                horizontalPadding: compact ? 18 : 24,
                topPadding: compact ? 14 : 28,
                wordmarkSize: 12,
                cellScale: 0.86
            )
        case .verticalMonth:
            return MonthlyLogShareTemplateLayout(
                monthFont: 34,
                yearFont: 12,
                amountFont: 28,
                weekdayFont: compact ? 8 : 10,
                dateFont: compact ? 7 : 9,
                badgeFont: compact ? 5 : 6,
                gridSpacing: compact ? 2 : 3,
                horizontalPadding: compact ? 12 : 16,
                topPadding: compact ? 18 : 22,
                wordmarkSize: 12,
                cellScale: compact ? 0.88 : 0.90
            )
        case .largeMonth:
            return MonthlyLogShareTemplateLayout(
                monthFont: 52,
                yearFont: compact ? 15 : 19,
                amountFont: 28,
                weekdayFont: compact ? 10 : 11,
                dateFont: compact ? 9 : 11,
                badgeFont: compact ? 6 : 7,
                gridSpacing: compact ? 2 : 3,
                horizontalPadding: compact ? 18 : 24,
                topPadding: compact ? 16 : 36,
                wordmarkSize: 12,
                cellScale: 0.86
            )
        case .circledCalendar:
            return MonthlyLogShareTemplateLayout(
                monthFont: 28,
                yearFont: 12,
                amountFont: 24,
                weekdayFont: 11,
                dateFont: 14,
                badgeFont: 7,
                gridSpacing: 0,
                horizontalPadding: 28,
                topPadding: 0,
                wordmarkSize: 12,
                cellScale: 1
            )
        case .monthInBooks:
            return MonthlyLogShareTemplateLayout(
                monthFont: 32,
                yearFont: 12,
                amountFont: 24,
                weekdayFont: 11,
                dateFont: 11,
                badgeFont: 7,
                gridSpacing: 3,
                horizontalPadding: 36,
                topPadding: 0,
                wordmarkSize: 12,
                cellScale: 0.86
            )
        case .minimalSummary:
            return MonthlyLogShareTemplateLayout(
                monthFont: 36,
                yearFont: compact ? 15 : 19,
                amountFont: 32,
                weekdayFont: 11,
                dateFont: 11,
                badgeFont: 7,
                gridSpacing: 3,
                horizontalPadding: 24,
                topPadding: 28,
                wordmarkSize: 12,
                cellScale: 0.86
            )
        }
    }
}

/// 縦倒し月名が、カレンダー列の高さに収まるようフォントを決める。
enum MonthlyLogShareVerticalMonthMetrics {
    static let minimumMonthFont: CGFloat = 22
    static let minimumYearFont: CGFloat = 10

    static func textLength(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = AppTypography.fixedUIFont(
            size: size,
            weight: AppTypography.Weight(weight),
            language: .english
        )
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func fittedFontSize(
        text: String,
        preferredSize: CGFloat,
        weight: UIFont.Weight,
        availableLength: CGFloat,
        minimumSize: CGFloat = minimumMonthFont
    ) -> CGFloat {
        let preferredLength = textLength(text, size: preferredSize, weight: weight)
        guard preferredLength > availableLength, preferredLength > 0 else {
            return preferredSize
        }
        let scaled = floor(preferredSize * max(availableLength, 1) / preferredLength)
        return max(minimumSize, scaled)
    }
}
