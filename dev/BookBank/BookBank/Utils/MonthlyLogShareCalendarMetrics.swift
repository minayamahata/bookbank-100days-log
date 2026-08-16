import CoreGraphics
import Foundation
import UIKit

/// 共有画像カレンダーのセル寸法。画面と同じ 2:3 を保ち、4〜6行でも枠内に収める。
enum MonthlyLogShareCalendarMetrics {
    static let cellAspectRatio: CGFloat = 2.0 / 3.0
    static let columnCount = 7

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
                wordmarkSize: compact ? 18 : 22
            )
        case .verticalMonth:
            return MonthlyLogShareTemplateLayout(
                monthFont: compact ? 40 : 54,
                yearFont: compact ? 15 : 19,
                amountFont: 28,
                weekdayFont: compact ? 10 : 11,
                dateFont: compact ? 8 : 10,
                badgeFont: compact ? 6 : 7,
                gridSpacing: compact ? 2 : 3,
                horizontalPadding: compact ? 14 : 20,
                topPadding: compact ? 24 : 48,
                wordmarkSize: compact ? 18 : 22
            )
        case .largeMonth:
            return MonthlyLogShareTemplateLayout(
                monthFont: 70,
                yearFont: compact ? 15 : 19,
                amountFont: 28,
                weekdayFont: compact ? 10 : 11,
                dateFont: compact ? 9 : 11,
                badgeFont: compact ? 6 : 7,
                gridSpacing: compact ? 2 : 3,
                horizontalPadding: compact ? 18 : 24,
                topPadding: compact ? 16 : 36,
                wordmarkSize: compact ? 18 : 22
            )
        case .minimalSummary:
            return MonthlyLogShareTemplateLayout(
                monthFont: 96,
                yearFont: 22,
                amountFont: 36,
                weekdayFont: 11,
                dateFont: 11,
                badgeFont: 7,
                gridSpacing: 3,
                horizontalPadding: 24,
                topPadding: 80,
                wordmarkSize: 22
            )
        }
    }
}

/// 2枚目の縦倒し月名が、カレンダー列の高さに収まるようフォントを決める。
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
