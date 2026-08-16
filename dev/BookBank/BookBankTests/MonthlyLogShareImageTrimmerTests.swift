import CoreGraphics
import Testing
import UIKit
@testable import BookBank

@MainActor
struct MonthlyLogShareImageTrimmerTests {
    @Test func detectsTopLeftPixelWithoutFlippingY() {
        let image = try! #require(makeRawImage(width: 16, height: 12, opaqueX: 3, opaqueY: 0))
        let bounds = try! #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image))
        #expect(bounds == CGRect(x: 3, y: 0, width: 1, height: 1))
    }

    @Test func detectsOpaqueRectInTransparentCanvas() {
        let image = try! #require(
            makeImage(width: 100, height: 80, alphaInfo: .premultipliedLast) { context in
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 30, y: 20, width: 12, height: 8))
            }
        )
        let bounds = try! #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image))
        #expect(bounds == CGRect(x: 30, y: 20, width: 12, height: 8))
    }

    @Test func adds24pxPaddingAroundOpaqueContent() {
        let opaque = CGRect(x: 40, y: 40, width: 10, height: 10)
        let crop = MonthlyLogShareImageTrimmer.paddedCropRect(
            opaque: opaque,
            imageWidth: 200,
            imageHeight: 200,
            paddingPixels: 24
        )
        #expect(crop == CGRect(x: 16, y: 16, width: 58, height: 58))
    }

    @Test func clampsPaddingToImageEdges() {
        let opaque = CGRect(x: 5, y: 8, width: 10, height: 6)
        let crop = MonthlyLogShareImageTrimmer.paddedCropRect(
            opaque: opaque,
            imageWidth: 40,
            imageHeight: 30,
            paddingPixels: 24
        )
        #expect(crop.origin.x == 0)
        #expect(crop.origin.y == 0)
        #expect(crop.maxX == 39)
        #expect(crop.maxY == 30)
    }

    @Test func includesSemiTransparentPixels() {
        let image = try! #require(
            makeImage(width: 60, height: 60, alphaInfo: .premultipliedLast) { context in
                context.setFillColor(UIColor.white.withAlphaComponent(0.02).cgColor)
                context.fill(CGRect(x: 10, y: 12, width: 4, height: 3))
            }
        )
        let bounds = try! #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image))
        #expect(bounds.minX <= 10)
        #expect(bounds.minY <= 12)
        #expect(bounds.maxX >= 14)
        #expect(bounds.maxY >= 15)
    }

    @Test func keepsSoftEdgeInsideCrop() {
        let image = try! #require(
            makeImage(width: 120, height: 120, alphaInfo: .premultipliedLast) { context in
                context.setShadow(offset: CGSize(width: 0, height: 0), blur: 6, color: UIColor.white.cgColor)
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 50, y: 50, width: 8, height: 8))
            }
        )
        let bounds = try! #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image))
        #expect(bounds.minX < 50)
        #expect(bounds.minY < 50)
        #expect(bounds.maxX > 58)
        #expect(bounds.maxY > 58)

        let cropped = try! #require(
            MonthlyLogShareImageTrimmer.cropToOpaqueContent(UIImage(cgImage: image), paddingPixels: 24)
        )
        let croppedCG = try! #require(cropped.cgImage)
        let croppedOpaque = try! #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: croppedCG))
        #expect(croppedOpaque.minX >= 1)
        #expect(croppedOpaque.minY >= 1)
        #expect(croppedOpaque.maxX <= CGFloat(croppedCG.width - 1))
        #expect(croppedOpaque.maxY <= CGFloat(croppedCG.height - 1))
    }

    @Test func fullyTransparentImageFails() {
        let image = try! #require(
            makeImage(width: 32, height: 32, alphaInfo: .premultipliedLast) { _ in }
        )
        #expect(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image) == nil)
        #expect(MonthlyLogShareImageTrimmer.cropToOpaqueContent(UIImage(cgImage: image)) == nil)
    }

    @Test func readsPremultipliedFirstAndLastTheSame() throws {
        let last = try #require(
            makeImage(width: 48, height: 48, alphaInfo: .premultipliedLast) { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 16, y: 10, width: 6, height: 5))
            }
        )
        let first = try #require(
            makeImage(width: 48, height: 48, alphaInfo: .premultipliedFirst) { context in
                context.setFillColor(UIColor.red.cgColor)
                context.fill(CGRect(x: 16, y: 10, width: 6, height: 5))
            }
        )
        #expect(
            MonthlyLogShareImageTrimmer.opaquePixelBounds(in: last)
                == MonthlyLogShareImageTrimmer.opaquePixelBounds(in: first)
        )
    }

    @Test func readsLittleEndianPremultipliedFirst() throws {
        let image = try #require(
            makeImage(
                width: 40,
                height: 40,
                alphaInfo: .premultipliedFirst,
                byteOrder: .byteOrder32Little
            ) { context in
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 8, y: 9, width: 7, height: 4))
            }
        )
        let bounds = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: image))
        #expect(bounds == CGRect(x: 8, y: 9, width: 7, height: 4))
    }

    @Test func croppedImageKeepsAlphaAndDoesNotScale() throws {
        let source = try #require(makeRawBlock(width: 80, height: 80, x: 30, y: 30, block: 4))
        let cropped = try #require(
            MonthlyLogShareImageTrimmer.cropToOpaqueContent(UIImage(cgImage: source), paddingPixels: 24)
        )
        let cgImage = try #require(cropped.cgImage)
        #expect(cgImage.width == 52)
        #expect(cgImage.height == 52)
        let alpha = cgImage.alphaInfo
        #expect(
            alpha == .premultipliedLast
                || alpha == .premultipliedFirst
                || alpha == .last
                || alpha == .first
        )

        let croppedOpaque = try #require(MonthlyLogShareImageTrimmer.opaquePixelBounds(in: cgImage))
        #expect(croppedOpaque == CGRect(x: 24, y: 24, width: 4, height: 4))

        let color = try #require(pixelColor(in: cgImage, x: 24, y: 24))
        #expect(color.alpha > 0.9)
        #expect(color.red > 0.9)
    }
}

private func makeImage(
    width: Int,
    height: Int,
    alphaInfo: CGImageAlphaInfo,
    byteOrder: CGBitmapInfo = .byteOrder32Big,
    draw: (CGContext) -> Void
) -> CGImage? {
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = byteOrder.rawValue | alphaInfo.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    return context.makeImage()
}

/// `y = 0` が CGImage 上端になる生ピクセル。走査の上下反転を検出する。
private func makeRawImage(width: Int, height: Int, opaqueX: Int, opaqueY: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let index = (opaqueY * width + opaqueX) * 4
    pixels[index] = 255
    pixels[index + 1] = 255
    pixels[index + 2] = 255
    pixels[index + 3] = 255
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          )
    else {
        return nil
    }
    return image
}

private func makeRawBlock(width: Int, height: Int, x: Int, y: Int, block: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for row in y..<(y + block) {
        for column in x..<(x + block) {
            let index = (row * width + column) * 4
            pixels[index] = 255
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 255
        }
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

private func pixelColor(in image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
    guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
        return nil
    }
    var pixel = [UInt8](repeating: 0, count: 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let ok = pixel.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress,
              let context = CGContext(
                data: base,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              )
        else {
            return false
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard ok else { return nil }
    return (
        red: CGFloat(pixel[0]) / 255,
        green: CGFloat(pixel[1]) / 255,
        blue: CGFloat(pixel[2]) / 255,
        alpha: CGFloat(pixel[3]) / 255
    )
}
