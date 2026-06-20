import UIKit

/// 表紙画像のメモリキャッシュ（ビュー再生成時も画像を保持）
final class BookCoverImageCache: @unchecked Sendable {
    static let shared = BookCoverImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: cacheKey(for: url))
    }

    func setImage(_ image: UIImage, for url: URL) {
        let cost = image.jpegData(compressionQuality: 1)?.count ?? 0
        cache.setObject(image, forKey: cacheKey(for: url), cost: cost)
    }

    private func cacheKey(for url: URL) -> NSString {
        url.absoluteString as NSString
    }
}
