import Foundation
import UIKit

/// 共有画像用の表紙を、ImageRenderer の外で事前解決する。
/// DTO / リポジトリへ画像バイナリ項目は足さない。
enum MonthlyLogShareCoverResolver {
    static let maxConcurrentRemoteFetches = 4

    @MainActor
    static func resolve(
        books: [BookDTO],
        loadLocalCover: (String) async -> Data?,
        fetchRemote: (@Sendable (URL) async -> Data?)? = nil
    ) async -> [String: UIImage] {
        var result: [String: UIImage] = [:]
        var remoteNeeded: [(bookId: String, url: URL)] = []

        for book in books {
            if Task.isCancelled { return [:] }

            if book.hasCoverImage {
                if let cached = LocalCoverDataCache.shared.image(for: book.id) {
                    result[book.id] = cached
                    continue
                }
                if let data = await loadLocalCover(book.id), !data.isEmpty {
                    if Task.isCancelled { return [:] }
                    if let image = LocalCoverDataCache.shared.storeAndDecode(data, for: book.id) {
                        result[book.id] = image
                        continue
                    }
                }
            }

            if let urlString = book.coverImageURL, let url = URL(string: urlString) {
                if let cached = BookCoverImageCache.shared.image(for: url) {
                    result[book.id] = cached
                    continue
                }
                remoteNeeded.append((book.id, url))
            }
        }

        if Task.isCancelled { return [:] }
        guard !remoteNeeded.isEmpty else { return result }

        var urlToBookIds: [URL: [String]] = [:]
        for item in remoteNeeded {
            urlToBookIds[item.url, default: []].append(item.bookId)
        }

        let fetched = await fetchRemoteImages(
            urls: Array(urlToBookIds.keys),
            fetchRemote: fetchRemote ?? defaultFetchData
        )
        if Task.isCancelled { return [:] }

        for (url, image) in fetched {
            BookCoverImageCache.shared.setImage(image, for: url)
            for bookId in urlToBookIds[url] ?? [] {
                result[bookId] = image
            }
        }
        return result
    }

    @MainActor
    private static func fetchRemoteImages(
        urls: [URL],
        fetchRemote: @escaping @Sendable (URL) async -> Data?
    ) async -> [URL: UIImage] {
        let gate = RemoteFetchGate(limit: maxConcurrentRemoteFetches)
        return await withTaskGroup(of: (URL, UIImage?).self, returning: [URL: UIImage].self) { group in
            for url in urls {
                group.addTask {
                    await gate.withPermit {
                        if Task.isCancelled { return (url, nil) }
                        let data = await fetchRemote(url)
                        if Task.isCancelled { return (url, nil) }
                        let image = await MainActor.run { data.flatMap(UIImage.init(data:)) }
                        return (url, image)
                    }
                }
            }

            var images: [URL: UIImage] = [:]
            for await (url, image) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return [:]
                }
                if let image {
                    images[url] = image
                }
            }
            return images
        }
    }

    private static func defaultFetchData(_ url: URL) async -> Data? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }
}

actor RemoteFetchGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func withPermit<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await work()
    }

    private func acquire() async {
        if running >= limit {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        running += 1
    }

    private func release() {
        running -= 1
        if running < limit, !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
