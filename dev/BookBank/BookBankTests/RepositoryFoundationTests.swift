import Foundation
import SwiftData
import XCTest
@testable import BookBank

@MainActor
final class RepositoryFoundationTests: XCTestCase {
    private var container: ModelContainer!
    private var repos: AppRepositories!
    private var pulse: RepositoryChangePulse!

    override func setUpWithError() throws {
        let schema = Schema([
            Passbook.self,
            UserBook.self,
            Subscription.self,
            ReadingList.self,
            MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        pulse = RepositoryChangePulse()
        let context = container.mainContext
        repos = AppRepositories(
            passbooks: SwiftDataPassbookRepository(context: context, pulse: pulse),
            books: SwiftDataBookRepository(context: context, pulse: pulse),
            readingLists: SwiftDataReadingListRepository(context: context, pulse: pulse),
            monthlyMemos: SwiftDataMonthlyMemoRepository(context: context, pulse: pulse)
        )
    }

    override func tearDownWithError() throws {
        repos = nil
        pulse = nil
        container = nil
    }

    private func samplePassbookDTO(
        id: String = UUID().uuidString,
        name: String = "技術書",
        sortOrder: Int = 1
    ) -> PassbookDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return PassbookDTO(
            id: id,
            name: name,
            type: .custom,
            sortOrder: sortOrder,
            isActive: true,
            colorIndex: 2,
            customColorHex: "#FF0000",
            createdAt: now,
            updatedAt: now
        )
    }

    private func sampleBookDTO(
        id: String = UUID().uuidString,
        title: String = "テスト本",
        passbookId: String? = nil,
        registeredAt: Date = Date(timeIntervalSince1970: 1_700_000_100),
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
    ) -> BookDTO {
        BookDTO(
            id: id,
            title: title,
            author: "著者",
            isbn: "9784123456789",
            publisher: "出版社",
            publishedYear: 2024,
            seriesName: "シリーズ",
            price: 1500,
            imageURL: "https://example.com/cover.jpg",
            bookFormat: "文庫",
            pageCount: 300,
            source: .manual,
            memo: "メモ",
            isFavorite: true,
            priceAtRegistration: 1500,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            passbookId: passbookId,
            hasCoverImage: false
        )
    }

    private func firstValue<T>(_ stream: AsyncStream<T>) async -> T {
        for await value in stream {
            return value
        }
        fatalError("stream finished without value")
    }

    // MARK: - (a) DTO変換の往復

    func testBookDTORoundTripPreservesFields() async throws {
        let passbook = samplePassbookDTO()
        try await repos.passbooks.addPassbook(passbook)

        let cover = Data([0x01, 0x02, 0x03])
        var book = sampleBookDTO(passbookId: passbook.id)
        try await repos.books.addBook(book, coverImageData: cover)

        var observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.count, 1)
        let loaded = try XCTUnwrap(observed.first)
        XCTAssertEqual(loaded.id, book.id)
        XCTAssertEqual(loaded.title, book.title)
        XCTAssertEqual(loaded.author, book.author)
        XCTAssertEqual(loaded.isbn, book.isbn)
        XCTAssertEqual(loaded.publisher, book.publisher)
        XCTAssertEqual(loaded.publishedYear, book.publishedYear)
        XCTAssertEqual(loaded.seriesName, book.seriesName)
        XCTAssertEqual(loaded.price, book.price)
        XCTAssertEqual(loaded.imageURL, book.imageURL)
        XCTAssertEqual(loaded.bookFormat, book.bookFormat)
        XCTAssertEqual(loaded.pageCount, book.pageCount)
        XCTAssertEqual(loaded.source, book.source)
        XCTAssertEqual(loaded.memo, book.memo)
        XCTAssertEqual(loaded.isFavorite, book.isFavorite)
        XCTAssertEqual(loaded.priceAtRegistration, book.priceAtRegistration)
        XCTAssertEqual(loaded.currencyCode, book.currencyCode)
        XCTAssertEqual(loaded.passbookId, passbook.id)
        XCTAssertTrue(loaded.hasCoverImage)

        let coverLoaded = await repos.books.loadCoverImage(bookId: book.id)
        XCTAssertEqual(coverLoaded, cover)

        book.memo = "更新後"
        book.isFavorite = false
        book.updatedAt = Date(timeIntervalSince1970: 1_700_000_200)
        try await repos.books.updateBook(book)

        observed = await firstValue(repos.books.observeBooks())
        let updated = try XCTUnwrap(observed.first)
        XCTAssertEqual(updated.memo, "更新後")
        XCTAssertFalse(updated.isFavorite)
        XCTAssertEqual(updated.updatedAt, book.updatedAt)
        XCTAssertTrue(updated.hasCoverImage)
    }

    func testPassbookDTORoundTripPreservesFields() async throws {
        var dto = samplePassbookDTO()
        try await repos.passbooks.addPassbook(dto)

        var observed = await firstValue(repos.passbooks.observePassbooks())
        XCTAssertEqual(observed, [dto])

        dto.name = "改名"
        dto.colorIndex = 5
        try await repos.passbooks.updatePassbook(dto)
        observed = await firstValue(repos.passbooks.observePassbooks())
        XCTAssertEqual(observed.first?.name, "改名")
        XCTAssertEqual(observed.first?.colorIndex, 5)
    }

    // MARK: - (b) 正準ソート

    func testBooksAreSortedByRegisteredAtThenCreatedAtDescending() async throws {
        let older = sampleBookDTO(
            title: "古い",
            registeredAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newerSameReg = sampleBookDTO(
            title: "同日・後作成",
            registeredAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 250)
        )
        let newerEarlierCreate = sampleBookDTO(
            title: "同日・先作成",
            registeredAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try await repos.books.addBook(older, coverImageData: nil)
        try await repos.books.addBook(newerEarlierCreate, coverImageData: nil)
        try await repos.books.addBook(newerSameReg, coverImageData: nil)

        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.map(\.title), ["同日・後作成", "同日・先作成", "古い"])
    }

    func testPassbooksAreSortedBySortOrderAscending() async throws {
        try await repos.passbooks.addPassbook(samplePassbookDTO(name: "C", sortOrder: 3))
        try await repos.passbooks.addPassbook(samplePassbookDTO(name: "A", sortOrder: 1))
        try await repos.passbooks.addPassbook(samplePassbookDTO(name: "B", sortOrder: 2))

        let observed = await firstValue(repos.passbooks.observePassbooks())
        XCTAssertEqual(observed.map(\.name), ["A", "B", "C"])
    }

    func testReadingListsAreSortedByUpdatedAtDescending() async throws {
        let older = ReadingListDTO(
            id: UUID().uuidString,
            title: "古いリスト",
            description: nil,
            colorIndex: nil,
            bookIds: [],
            books: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 10),
            legacyShareId: ""
        )
        let newer = ReadingListDTO(
            id: UUID().uuidString,
            title: "新しいリスト",
            description: nil,
            colorIndex: nil,
            bookIds: [],
            books: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 20),
            legacyShareId: ""
        )
        try await repos.readingLists.addReadingList(older)
        try await repos.readingLists.addReadingList(newer)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertEqual(observed.map(\.title), ["新しいリスト", "古いリスト"])
    }

    // MARK: - (c) ReadingList 並び順解決

    func testReadingListOrderingMatchesOrderedBooksSemantics() {
        struct Item: Equatable {
            let uuid: String
            let title: String
        }
        let books = [
            Item(uuid: "uA", title: "A"),
            Item(uuid: "uB", title: "B"),
            Item(uuid: "uC", title: "C")
        ]
        let ordered = ReadingListOrdering.resolve(
            bookIds: ["uC", "uA"],
            books: books,
            uuid: { $0.uuid }
        )
        XCTAssertEqual(ordered.map(\.uuid), ["uC", "uA", "uB"])

        let emptyIds = ReadingListOrdering.resolve(bookIds: [], books: books, uuid: { $0.uuid })
        XCTAssertEqual(emptyIds.map(\.uuid), ["uA", "uB", "uC"])
    }

    func testReadingListDTOBooksFollowBookIdsOrder() async throws {
        let a = sampleBookDTO(title: "A")
        let b = sampleBookDTO(title: "B")
        let c = sampleBookDTO(title: "C")
        try await repos.books.addBook(a, coverImageData: nil)
        try await repos.books.addBook(b, coverImageData: nil)
        try await repos.books.addBook(c, coverImageData: nil)

        let list = ReadingListDTO(
            id: UUID().uuidString,
            title: "順不同",
            description: "desc",
            colorIndex: 1,
            bookIds: [c.id, a.id],
            books: [],
            createdAt: Date(),
            updatedAt: Date(),
            legacyShareId: ""
        )
        try await repos.readingLists.addReadingList(list)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.books.map(\.id), [c.id, a.id])
        XCTAssertEqual(dto.description, "desc")
        XCTAssertFalse(dto.legacyShareId.isEmpty)
    }

    // MARK: - (d) チェンジパルス

    func testChangePulseYieldsOnWrite() async throws {
        let stream = repos.passbooks.observePassbooks()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, [])

        let dto = samplePassbookDTO()
        try await repos.passbooks.addPassbook(dto)
        let afterAdd = await iterator.next()
        XCTAssertEqual(afterAdd, [dto])
    }

    // MARK: - (e) 削除の波及

    func testDeletingPassbookAlsoDeletesItsBooks() async throws {
        let passbook = samplePassbookDTO()
        try await repos.passbooks.addPassbook(passbook)
        try await repos.books.addBook(sampleBookDTO(passbookId: passbook.id), coverImageData: nil)
        try await repos.books.addBook(sampleBookDTO(passbookId: passbook.id), coverImageData: nil)

        try await repos.passbooks.deletePassbook(id: passbook.id)

        let books = await firstValue(repos.books.observeBooks())
        let passbooks = await firstValue(repos.passbooks.observePassbooks())
        XCTAssertTrue(books.isEmpty)
        XCTAssertTrue(passbooks.isEmpty)
    }

    func testDeletingBookRemovesItFromReadingListBookIds() async throws {
        let book = sampleBookDTO()
        let other = sampleBookDTO()
        try await repos.books.addBook(book, coverImageData: nil)
        try await repos.books.addBook(other, coverImageData: nil)

        let list = ReadingListDTO(
            id: UUID().uuidString,
            title: "リスト",
            description: nil,
            colorIndex: nil,
            bookIds: [book.id, other.id],
            books: [],
            createdAt: Date(),
            updatedAt: Date(),
            legacyShareId: ""
        )
        try await repos.readingLists.addReadingList(list)
        try await repos.books.deleteBook(id: book.id)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.bookIds, [other.id])
        XCTAssertEqual(dto.books.map(\.id), [other.id])
    }

    // MARK: - MonthlyMemo

    func testMonthlyMemoEmptyTextDeletesRecord() async throws {
        try await repos.monthlyMemos.saveMemo(year: 2026, month: 7, text: "  hello  ")

        var memo = await firstValue(repos.monthlyMemos.observeMemo(year: 2026, month: 7))
        XCTAssertEqual(memo?.text, "hello")

        try await repos.monthlyMemos.saveMemo(year: 2026, month: 7, text: "   ")
        memo = await firstValue(repos.monthlyMemos.observeMemo(year: 2026, month: 7))
        XCTAssertNil(memo)
    }
}
