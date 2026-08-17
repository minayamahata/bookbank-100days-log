import CoreGraphics
import Foundation

/// 共有プレビューのカード寸法。カルーセルは全ページ同じ幅を使い、高さだけ比率で変える。
enum MonthlyLogSharePreviewMetrics {
    static let displayScale: CGFloat = 0.85
    static let desiredPeek: CGFloat = 28
    static let pageSpacing: CGFloat = 12

    /// 9:16 カードが収まる基準サイズ。幅は全テンプレートで共有する。
    static func referenceCardSize(in bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else {
            return .zero
        }
        let aspect = MonthlyLogShareCanvasFormat.portrait.logicalSize.width
            / MonthlyLogShareCanvasFormat.portrait.logicalSize.height
        let height = min(bounds.height, bounds.width / aspect)
        let width = height * aspect
        return CGSize(width: width, height: height)
    }

    static func cardSize(
        format: MonthlyLogShareCanvasFormat,
        referenceWidth: CGFloat
    ) -> CGSize {
        guard referenceWidth > 0, referenceWidth.isFinite else {
            return .zero
        }
        switch format {
        case .portrait:
            return CGSize(width: referenceWidth, height: referenceWidth * 16 / 9)
        case .portraitFourFive:
            return CGSize(width: referenceWidth, height: referenceWidth * 5 / 4)
        case .square:
            return CGSize(width: referenceWidth, height: referenceWidth)
        }
    }
}
