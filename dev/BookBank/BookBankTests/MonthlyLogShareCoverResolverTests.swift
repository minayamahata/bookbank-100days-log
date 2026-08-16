import Foundation
import Testing
import UIKit
@testable import BookBank

@MainActor
struct MonthlyLogShareCoverResolverTests {
    private func sampleData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }.pngData() ?? Data()
    }

    private func book(
        id: String,
        hasCoverImage: Bool = false,
        imageURL: String? = nil
    ) -> BookDTO {
        let now = Date()
        return BookDTO(
            id: id,
            title: id,
            author: nil,
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: nil,
            imageURL: imageURL,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: nil,
            currencyCode: "JPY",
            registeredAt: now,
            createdAt: now,
            updatedAt: now,
            passbookId: "pb",
            hasCoverImage: hasCoverImage
        )
    }

    @Test func prefersLocalCacheThenLoadCoverThenRemote() async {
        LocalCoverDataCache.shared.removeAll()
        let data = sampleData()
        let cachedId = "local-cache-\(UUID().uuidString)"
        LocalCoverDataCache.shared.setData(data, for: cachedId)

        var loadedIds: [String] = []
        let fetched = URLBox()
        let cached = book(id: cachedId, hasCoverImage: true)
        let loadedId = "local-load-\(UUID().uuidString)"
        let loaded = book(id: loadedId, hasCoverImage: true)
        let remoteURL = URL(string: "https://example.test/covers/\(UUID().uuidString).jpg")!
        let remote = book(id: "remote-\(UUID().uuidString)", imageURL: remoteURL.absoluteString)
        let failedURL = URL(string: "https://example.test/covers/\(UUID().uuidString)-fail.jpg")!
        let failed = book(id: "fail-\(UUID().uuidString)", imageURL: failedURL.absoluteString)

        let result = await MonthlyLogShareCoverResolver.resolve(
            books: [cached, loaded, remote, failed],
            loadLocalCover: { bookId in
                loadedIds.append(bookId)
                return bookId == loadedId ? data : nil
            },
            fetchRemote: { url in
                fetched.add(url)
                return url == remoteURL ? data : nil
            }
        )

        #expect(result[cachedId] != nil)
        #expect(result[loadedId] != nil)
        #expect(result[remote.id] != nil)
        #expect(result[failed.id] == nil)
        #expect(!loadedIds.contains(cachedId), "キャッシュ済みの手動表紙は loadCoverImage しない")
        #expect(loadedIds.contains(loadedId))
        #expect(fetched.urls == Set([remoteURL, failedURL]))
        LocalCoverDataCache.shared.removeAll()
    }

    @Test func fetchesDuplicateURLOnce() async {
        let data = sampleData()
        let url = URL(string: "https://example.test/covers/\(UUID().uuidString).jpg")!
        let first = book(id: "dup-a-\(UUID().uuidString)", imageURL: url.absoluteString)
        let second = book(id: "dup-b-\(UUID().uuidString)", imageURL: url.absoluteString)
        let fetchCount = LockedCounter()

        let result = await MonthlyLogShareCoverResolver.resolve(
            books: [first, second],
            loadLocalCover: { _ in nil },
            fetchRemote: { _ in
                fetchCount.increment()
                return data
            }
        )

        #expect(fetchCount.value == 1)
        #expect(result[first.id] != nil)
        #expect(result[second.id] != nil)
    }

    @Test func limitsConcurrentRemoteFetchesToFour() async {
        let data = sampleData()
        let books = (0..<8).map { index in
            book(
                id: "parallel-\(index)-\(UUID().uuidString)",
                imageURL: "https://example.test/covers/\(UUID().uuidString).jpg"
            )
        }
        let counter = ConcurrencyCounter()

        let result = await MonthlyLogShareCoverResolver.resolve(
            books: books,
            loadLocalCover: { _ in nil },
            fetchRemote: { _ in
                counter.enter()
                try? await Task.sleep(for: .milliseconds(40))
                counter.leave()
                return data
            }
        )

        #expect(result.count == 8)
        #expect(counter.maxValue <= MonthlyLogShareCoverResolver.maxConcurrentRemoteFetches)
        #expect(counter.maxValue >= 1)
        #expect(MonthlyLogShareCoverResolver.maxConcurrentRemoteFetches == 4)
    }

    @Test func usesRemoteCacheWithoutFetching() async {
        let data = sampleData()
        let url = URL(string: "https://example.test/covers/\(UUID().uuidString).jpg")!
        let image = UIImage(data: data)!
        BookCoverImageCache.shared.setImage(image, for: url)
        let fetchCount = LockedCounter()
        let target = book(id: "cached-remote-\(UUID().uuidString)", imageURL: url.absoluteString)

        let result = await MonthlyLogShareCoverResolver.resolve(
            books: [target],
            loadLocalCover: { _ in nil },
            fetchRemote: { _ in
                fetchCount.increment()
                return data
            }
        )

        #expect(fetchCount.value == 0)
        #expect(result[target.id] != nil)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        values.append(url)
        lock.unlock()
    }

    var urls: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return Set(values)
    }
}

final class ConcurrencyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var maxValue = 0

    func enter() {
        lock.lock()
        current += 1
        maxValue = max(maxValue, current)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        current -= 1
        lock.unlock()
    }
}
