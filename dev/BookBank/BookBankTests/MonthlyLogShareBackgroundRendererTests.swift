import Foundation
import Testing
import UIKit
@testable import BookBank

/// 背景モード（白・黒）の出力検証。透明 PNG は既存の
/// `MonthlyLogShareRendererTests` が現行仕様のまま担保する。
@MainActor
struct MonthlyLogShareBackgroundRendererTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func book(id: String, day: Int, price: Int?) -> BookDTO {
        let calendar = calendar()
        let registeredAt = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day, hour: 12)
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

    private func snapshot() -> MonthlyLogShareSnapshot {
        MonthlyLogShareSnapshot.make(
            year: 2026,
            month: 8,
            passbookBooks: [book(id: "a", day: 16, price: 1200)],
            displayCurrency: .jpy,
            exchangeRates: .shared,
            calendar: calendar(),
            locale: Locale(identifier: "ja")
        )
    }

    /// 向き適用後のピクセルサイズ（テスト内の寸法確認専用）。
    private func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    @Test func whiteAndBlackExportsAreOpaqueJPEGsAtMasterPixelSize() throws {
        let snapshot = snapshot()
        for (mode, corner): (MonthlyLogShareBackgroundMode, CGFloat) in [(.white, 1), (.black, 0)] {
            for template in MonthlyLogShareTemplate.allCases {
                let asset = try #require(
                    MonthlyLogShareRenderer.exportAsset(
                        snapshot: snapshot,
                        covers: [:],
                        template: template,
                        mode: mode
                    )
                )
                #expect(asset.format == .jpeg)
                let image = try #require(UIImage(data: asset.data))
                #expect(pixelSize(of: image) == template.canvasFormat.masterPixelSize)
                let cgImage = try #require(image.cgImage)
                #expect(
                    cgImage.alphaInfo == .none
                        || cgImage.alphaInfo == .noneSkipFirst
                        || cgImage.alphaInfo == .noneSkipLast,
                    "白/黒 JPEG はアルファを持たない"
                )
                // 四隅は背景色（テンプレート描画は端まで届かない）
                let sample = try #require(pixel(in: cgImage, x: 2, y: 2))
                #expect(abs(sample.red - corner) < 0.06)
                #expect(abs(sample.green - corner) < 0.06)
                #expect(abs(sample.blue - corner) < 0.06)
            }
        }
    }

    @Test func whiteModeRendersDarkContent() throws {
        let snapshot = snapshot()
        let asset = try #require(
            MonthlyLogShareRenderer.exportAsset(
                snapshot: snapshot,
                covers: [:],
                template: .calendarSummary,
                mode: .white
            )
        )
        let cgImage = try #require(UIImage(data: asset.data)?.cgImage)
        // 黒文字系パレットで描かれた画素（暗い画素）が存在する
        #expect(containsPixel(in: cgImage) { $0.red < 0.5 && $0.green < 0.5 && $0.blue < 0.5 })
    }

    @Test func paletteChangesMasterRendering() throws {
        let snapshot = snapshot()
        let light = try #require(
            MonthlyLogShareRenderer.masterImage(
                snapshot: snapshot,
                covers: [:],
                template: .minimalSummary,
                palette: .light
            )
        )
        let dark = try #require(
            MonthlyLogShareRenderer.masterImage(
                snapshot: snapshot,
                covers: [:],
                template: .minimalSummary,
                palette: .dark
            )
        )
        #expect(light.pngData() != dark.pngData())
    }

    @Test func transparentModeStaysPNG() throws {
        let snapshot = snapshot()
        let asset = try #require(
            MonthlyLogShareRenderer.exportAsset(
                snapshot: snapshot,
                covers: [:],
                template: .verticalMonth,
                mode: .transparent
            )
        )
        #expect(asset.format == .png)
        let image = try #require(UIImage(data: asset.data))
        // 3枚目はトリミングせず 1080×1350 のまま（現行仕様の維持）
        #expect(pixelSize(of: image) == CGSize(width: 1080, height: 1350))
    }

    // MARK: - 画素の取得

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private func rgbaBuffer(in image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let created = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { return nil }
        return (pixels, width, height)
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> RGBA? {
        guard let buffer = rgbaBuffer(in: image) else { return nil }
        guard x < buffer.width, y < buffer.height else { return nil }
        let index = (y * buffer.width + x) * 4
        return RGBA(
            red: CGFloat(buffer.bytes[index]) / 255,
            green: CGFloat(buffer.bytes[index + 1]) / 255,
            blue: CGFloat(buffer.bytes[index + 2]) / 255
        )
    }

    private func containsPixel(
        in image: CGImage,
        where predicate: (RGBA) -> Bool
    ) -> Bool {
        guard let buffer = rgbaBuffer(in: image) else { return false }
        for y in 0..<buffer.height {
            let row = y * buffer.width * 4
            for x in 0..<buffer.width {
                let index = row + x * 4
                let rgba = RGBA(
                    red: CGFloat(buffer.bytes[index]) / 255,
                    green: CGFloat(buffer.bytes[index + 1]) / 255,
                    blue: CGFloat(buffer.bytes[index + 2]) / 255
                )
                if predicate(rgba) {
                    return true
                }
            }
        }
        return false
    }
}
