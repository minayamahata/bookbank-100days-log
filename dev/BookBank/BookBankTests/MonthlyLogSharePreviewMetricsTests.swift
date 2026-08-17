import CoreGraphics
import Testing
@testable import BookBank

struct MonthlyLogSharePreviewMetricsTests {
    @Test func cardSizesFollowCanvasAspectRatios() {
        let width: CGFloat = 180
        let portrait = MonthlyLogSharePreviewMetrics.cardSize(format: .portrait, referenceWidth: width)
        let fourFive = MonthlyLogSharePreviewMetrics.cardSize(format: .portraitFourFive, referenceWidth: width)
        let square = MonthlyLogSharePreviewMetrics.cardSize(format: .square, referenceWidth: width)

        #expect(portrait.width == width)
        #expect(fourFive.width == width)
        #expect(square.width == width)
        #expect(abs(portrait.height / portrait.width - 16 / 9) < 0.0001)
        #expect(abs(fourFive.height / fourFive.width - 5 / 4) < 0.0001)
        #expect(fourFive.height == width * 5 / 4)
        #expect(abs(square.height / square.width - 1) < 0.0001)
        #expect(portrait.width == fourFive.width)
        #expect(portrait.width == square.width)
    }

    @Test func referenceCardFitsAvailableBounds() {
        let bounds = CGSize(width: 300, height: 400)
        let reference = MonthlyLogSharePreviewMetrics.referenceCardSize(in: bounds)
        #expect(reference.width <= bounds.width + 0.01)
        #expect(reference.height <= bounds.height + 0.01)
        #expect(abs(reference.height / reference.width - 16 / 9) < 0.0001)

        let scaledWidth = reference.width * MonthlyLogSharePreviewMetrics.displayScale
        let portrait = MonthlyLogSharePreviewMetrics.cardSize(format: .portrait, referenceWidth: scaledWidth)
        let fourFive = MonthlyLogSharePreviewMetrics.cardSize(format: .portraitFourFive, referenceWidth: scaledWidth)
        let square = MonthlyLogSharePreviewMetrics.cardSize(format: .square, referenceWidth: scaledWidth)
        #expect(portrait.width <= bounds.width + 0.01)
        #expect(portrait.height <= bounds.height + 0.01)
        #expect(fourFive.width <= bounds.width + 0.01)
        #expect(fourFive.height <= bounds.height + 0.01)
        #expect(square.width <= bounds.width + 0.01)
        #expect(square.height <= bounds.height + 0.01)
    }

    @Test func nonPositiveInputsDoNotCrash() {
        #expect(MonthlyLogSharePreviewMetrics.referenceCardSize(in: .zero) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.referenceCardSize(in: CGSize(width: -10, height: 100)) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.referenceCardSize(in: CGSize(width: 100, height: 0)) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.cardSize(format: .portrait, referenceWidth: 0) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.cardSize(format: .portraitFourFive, referenceWidth: 0) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.cardSize(format: .square, referenceWidth: -4) == .zero)
        #expect(MonthlyLogSharePreviewMetrics.cardSize(format: .portrait, referenceWidth: .nan) == .zero)
    }
}
