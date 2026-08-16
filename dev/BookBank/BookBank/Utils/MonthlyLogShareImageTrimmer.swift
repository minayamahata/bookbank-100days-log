import CoreGraphics
import Foundation
import UIKit

/// 共有マスター画像から、描画済みピクセルの最小矩形＋余白を切り出す。
enum MonthlyLogShareImageTrimmer {
    /// 最終 PNG 上の透明余白（pt ではなく物理ピクセル）。
    static let paddingPixels = 24

    /// 完全透明、または入力が壊れているときは `nil`。再拡大はしない。
    static func cropToOpaqueContent(
        _ image: UIImage,
        paddingPixels: Int = paddingPixels
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard let opaque = opaquePixelBounds(in: cgImage) else { return nil }
        let crop = paddedCropRect(
            opaque: opaque,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            paddingPixels: paddingPixels
        )
        guard crop.width > 0, crop.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// `alpha > 0` の最小矩形。座標はピクセル、origin は左上。完全透明なら `nil`。
    static func opaquePixelBounds(in image: CGImage) -> CGRect? {
        guard let buffer = RGBABuffer(image: image) else { return nil }
        var minX = buffer.width
        var minY = buffer.height
        var maxX = -1
        var maxY = -1

        for y in 0..<buffer.height {
            let row = y * buffer.bytesPerRow
            for x in 0..<buffer.width {
                let alpha = buffer.bytes[row + x * 4 + 3]
                if alpha > 0 {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= 0, maxY >= 0 else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    /// 不透明矩形の四辺へ余白を足し、画像内へクランプする。
    static func paddedCropRect(
        opaque: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        paddingPixels: Int = paddingPixels
    ) -> CGRect {
        let padding = max(0, paddingPixels)
        let minX = Int(opaque.minX.rounded(.towardZero))
        let minY = Int(opaque.minY.rounded(.towardZero))
        let maxX = Int(opaque.maxX.rounded(.towardZero)) - 1
        let maxY = Int(opaque.maxY.rounded(.towardZero)) - 1
        let x0 = max(0, minX - padding)
        let y0 = max(0, minY - padding)
        let x1 = min(imageWidth, maxX + 1 + padding)
        let y1 = min(imageHeight, maxY + 1 + padding)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

/// 入力の alphaInfo / byte order に依存せず、RGBA（alpha last）へ正規化する。
private struct RGBABuffer {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let created = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { return nil }

        self.bytes = pixels
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }
}
