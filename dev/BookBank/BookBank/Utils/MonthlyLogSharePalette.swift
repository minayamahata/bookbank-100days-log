import SwiftUI

/// 共有テンプレートの文字色系。プレビューと書き出しで同じ値を使う。
enum MonthlyLogSharePalette: Int, CaseIterable, Hashable, Sendable {
    /// 白文字（黒背景・透明・写真の白文字。現行デザイン）
    case light
    /// 黒文字（白背景・写真の黒文字）
    case dark

    /// 表紙なしプレースホルダーセルの不透明度。空セルの 0.20 とは別。
    static let coverPlaceholderOpacity: CGFloat = 0.14

    /// 見出し・年・曜日・金額・冊数・空セル上の日付・ワードマーク
    var foreground: Color {
        self == .light ? .white : .black
    }

    /// 本が登録されていない日付セルの背景
    var emptyCellFill: Color {
        foreground.opacity(MonthlyLogShareCalendarMetrics.emptyShareCellOpacity)
    }

    /// 表紙なしプレースホルダーセルの背景
    var coverPlaceholderFill: Color {
        foreground.opacity(Self.coverPlaceholderOpacity)
    }

    /// 表紙画像の上の日付と +N は可読性のため常に白（パレットに依存しない）
    static let coverOverlayText: Color = .white
}
