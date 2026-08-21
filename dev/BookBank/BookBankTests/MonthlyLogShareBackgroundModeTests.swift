import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import BookBank

struct MonthlyLogShareBackgroundModeTests {
    @Test func displayOrderAndDefault() {
        // 写真モードは 2026-08-21 に撤去。白・黒・透明の3種のみ
        #expect(MonthlyLogShareBackgroundMode.allCases == [.white, .black, .transparent])
        #expect(MonthlyLogShareBackgroundMode.defaultMode == .white)
    }

    @Test func paletteMapping() {
        #expect(MonthlyLogShareBackgroundMode.white.palette == .dark)
        #expect(MonthlyLogShareBackgroundMode.black.palette == .light)
        #expect(MonthlyLogShareBackgroundMode.transparent.palette == .light)
    }

    @Test func exportFormatMapping() {
        #expect(MonthlyLogShareBackgroundMode.white.exportFormat == .jpeg)
        #expect(MonthlyLogShareBackgroundMode.black.exportFormat == .jpeg)
        #expect(MonthlyLogShareBackgroundMode.transparent.exportFormat == .png)
    }

    @Test func paletteColors() {
        #expect(MonthlyLogSharePalette.light.foreground == Color.white)
        #expect(MonthlyLogSharePalette.dark.foreground == Color.black)
        #expect(
            MonthlyLogSharePalette.light.emptyCellFill
                == Color.white.opacity(MonthlyLogShareCalendarMetrics.emptyShareCellOpacity)
        )
        #expect(
            MonthlyLogSharePalette.dark.emptyCellFill
                == Color.black.opacity(MonthlyLogShareCalendarMetrics.emptyShareCellOpacity)
        )
        #expect(
            MonthlyLogSharePalette.dark.coverPlaceholderFill
                == Color.black.opacity(MonthlyLogSharePalette.coverPlaceholderOpacity)
        )
        // 表紙上の日付と +N はパレットに依存せず白
        #expect(MonthlyLogSharePalette.coverOverlayText == Color.white)
    }

    @Test func exportAssetTypeAndExtension() {
        let png = MonthlyLogShareExportAsset(data: Data([0x01]), format: .png)
        #expect(png.utType == .png)
        #expect(png.fileExtension == "png")

        let jpeg = MonthlyLogShareExportAsset(data: Data([0x02]), format: .jpeg)
        #expect(jpeg.utType == .jpeg)
        #expect(jpeg.fileExtension == "jpg")
    }
}
