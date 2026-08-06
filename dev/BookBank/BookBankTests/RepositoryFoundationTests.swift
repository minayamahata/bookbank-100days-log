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
        let books = SwiftDataBookRepository(context: context, pulse: pulse)
        repos = AppRepositories(
            passbooks: SwiftDataPassbookRepository(context: context, pulse: pulse, books: books),
            books: books,
            readingLists: SwiftDataReadingListRepository(context: context, pulse: pulse, books: books),
            monthlyMemos: SwiftDataMonthlyMemoRepository(context: context, pulse: pulse),
            pulse: pulse
        )
    }

    override func tearDownWithError() throws {
        repos = nil
        pulse = nil
        container = nil
        // プロセス共有のシングルトンがテスト間で状態を持ち越さないようにする（レビュー S4-5）。
        // 脱シングルトン化（DI）はステップ6またはR6の解体時（設計メモ 4.6節）
        LocalCoverDataCache.shared.removeAll()
    }

    private func samplePassbookDTO(
        id: String = UUID().uuidString,
        name: String = "技術書",
        sortOrder: Int = 1,
        colorIndex: Int? = 2,
        customColorHex: String? = "#FF0000"
    ) -> PassbookDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return PassbookDTO(
            id: id,
            name: name,
            type: .custom,
            sortOrder: sortOrder,
            isActive: true,
            colorIndex: colorIndex,
            customColorHex: customColorHex,
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

    private func makeListDTO(
        id: String = UUID().uuidString,
        title: String = "リスト",
        colorIndex: Int? = 10,
        bookIds: [String] = [],
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) -> ReadingListDTO {
        ReadingListDTO(
            id: id,
            title: title,
            description: nil,
            colorIndex: colorIndex,
            bookIds: bookIds,
            books: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_400),
            updatedAt: updatedAt,
            legacyShareId: ""
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

    /// R4ステップ2確認項目: メモ編集→アプリ再起動→保持
    /// オンディスクのストアに保存し、コンテナを破棄・再生成（＝再起動相当）しても読めることを確認する
    func testMonthlyMemoPersistsAcrossContainerReload() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("restart-test.store")
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        // 1回目の「起動」で保存
        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let firstContainer = try ModelContainer(for: schema, configurations: [config])
            let repo = SwiftDataMonthlyMemoRepository(
                context: firstContainer.mainContext,
                pulse: RepositoryChangePulse()
            )
            try await repo.saveMemo(year: 2026, month: 7, text: "再起動チェック")
        }

        // 2回目の「起動」（別コンテナ）で読み出し
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let secondContainer = try ModelContainer(for: schema, configurations: [config])
        let repo = SwiftDataMonthlyMemoRepository(
            context: secondContainer.mainContext,
            pulse: RepositoryChangePulse()
        )
        let memo = await firstValue(repo.observeMemo(year: 2026, month: 7))
        XCTAssertEqual(memo?.text, "再起動チェック")
    }

    // MARK: - R4ステップ3 レビュー修正 (#1/#2/#6)

    func testResolvedDefaultColorIndexEmptyListReturnsNil() {
        let dto = samplePassbookDTO(colorIndex: nil, customColorHex: nil)
        XCTAssertNil(PassbookColor.resolvedDefaultColorIndex(for: dto, in: []))
    }

    func testResolvedDefaultColorIndexReturnsListPosition() {
        let a = samplePassbookDTO(id: "a", sortOrder: 0, colorIndex: nil, customColorHex: nil)
        let b = samplePassbookDTO(id: "b", sortOrder: 1, colorIndex: nil, customColorHex: nil)
        XCTAssertEqual(PassbookColor.resolvedDefaultColorIndex(for: b, in: [a, b]), 1)
    }

    func testResolvedDefaultColorIndexReturnsNilWhenAlreadySet() {
        let dto = samplePassbookDTO(colorIndex: 5, customColorHex: nil)
        XCTAssertNil(PassbookColor.resolvedDefaultColorIndex(for: dto, in: [dto]))
    }

    func testApplyingResolvedColorIndexAtNonZeroPosition() async throws {
        let first = samplePassbookDTO(id: "first", sortOrder: 0, colorIndex: 3, customColorHex: nil)
        let second = samplePassbookDTO(id: "second", sortOrder: 1, colorIndex: nil, customColorHex: nil)
        try await repos.passbooks.addPassbook(first)
        try await repos.passbooks.addPassbook(second)

        let list = await firstValue(repos.passbooks.observePassbooks())
        let index = try XCTUnwrap(PassbookColor.resolvedDefaultColorIndex(for: second, in: list))
        XCTAssertEqual(index, 1)
        var updated = second
        updated.colorIndex = index
        try await repos.passbooks.updatePassbook(updated)

        let after = await firstValue(repos.passbooks.observePassbooks())
        let saved = try XCTUnwrap(after.first(where: { $0.id == "second" }))
        XCTAssertEqual(saved.colorIndex, 1)
    }

    func testNotifyExternalChangeYieldsUpdatedPassbookUUID() async throws {
        let dto = samplePassbookDTO(id: "old-uuid")
        try await repos.passbooks.addPassbook(dto)

        let stream = repos.passbooks.observePassbooks()
        var iterator = stream.makeAsyncIterator()
        let initialOptional = await iterator.next()
        let initial = try XCTUnwrap(initialOptional)
        XCTAssertEqual(initial.first?.id, "old-uuid")

        // リポジトリ外で uuid を書き換え（マイグレーション相当）
        let context = container.mainContext
        let target = "old-uuid"
        let descriptor = FetchDescriptor<Passbook>(predicate: #Predicate { $0.uuid == target })
        let model = try XCTUnwrap(try context.fetch(descriptor).first)
        model.uuid = "backfilled-uuid"
        try context.save()

        // パルス無しではストリームは旧値のまま（notify しないと next が来ない／値が変わらない）
        repos.notifyExternalChange()
        let refreshedOptional = await iterator.next()
        let refreshed = try XCTUnwrap(refreshedOptional)
        XCTAssertEqual(refreshed.first?.id, "backfilled-uuid")
    }

    // MARK: - R4ステップ4

    /// 申し送り（設計メモ 4.4節）: `deletePassbook` を `deleteBook` の bookIds 掃除セマンティクスへ寄せた
    func testDeletingPassbookRemovesItsBooksFromReadingListBookIds() async throws {
        let passbook = samplePassbookDTO()
        try await repos.passbooks.addPassbook(passbook)

        let inPassbook = sampleBookDTO(passbookId: passbook.id)
        let otherPassbookBook = sampleBookDTO(passbookId: passbook.id)
        let unrelated = sampleBookDTO(passbookId: nil)
        try await repos.books.addBook(inPassbook, coverImageData: nil)
        try await repos.books.addBook(otherPassbookBook, coverImageData: nil)
        try await repos.books.addBook(unrelated, coverImageData: nil)

        let list = ReadingListDTO(
            id: UUID().uuidString,
            title: "リスト",
            description: nil,
            colorIndex: nil,
            bookIds: [inPassbook.id, unrelated.id, otherPassbookBook.id],
            books: [],
            createdAt: Date(),
            updatedAt: Date(),
            legacyShareId: ""
        )
        try await repos.readingLists.addReadingList(list)

        try await repos.passbooks.deletePassbook(id: passbook.id)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        // 口座に属していた本のuuidだけが bookIds から消え、無関係な本は順序ごと残る
        XCTAssertEqual(dto.bookIds, [unrelated.id])
        XCTAssertEqual(dto.books.map(\.id), [unrelated.id])

        let books = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(books.map(\.id), [unrelated.id])
    }

    /// ステップ3 #2 の UserBook 版。`CurrencyMigration` はリポジトリを介さず UserBook を書くため、
    /// `notifyExternalChange()` で UserBook ストリームが再fetchされる経路を固定する（設計メモ 4.3節）
    func testNotifyExternalChangeYieldsUpdatedBook() async throws {
        let dto = sampleBookDTO(id: "book-uuid")
        try await repos.books.addBook(dto, coverImageData: nil)

        let stream = repos.books.observeBooks()
        var iterator = stream.makeAsyncIterator()
        let initialOptional = await iterator.next()
        let initial = try XCTUnwrap(initialOptional)
        XCTAssertEqual(initial.first?.id, "book-uuid")
        XCTAssertEqual(initial.first?.currencyCode, "JPY")

        // リポジトリ外で書き換え（CurrencyMigration 相当）
        let context = container.mainContext
        let target = "book-uuid"
        let descriptor = FetchDescriptor<UserBook>(predicate: #Predicate { $0.uuid == target })
        let model = try XCTUnwrap(try context.fetch(descriptor).first)
        model.currencyCode = "USD"
        model.title = "マイグレーション後"
        try context.save()

        repos.notifyExternalChange()
        let refreshedOptional = await iterator.next()
        let refreshed = try XCTUnwrap(refreshedOptional)
        XCTAssertEqual(refreshed.first?.currencyCode, "USD")
        XCTAssertEqual(refreshed.first?.title, "マイグレーション後")
    }

    /// リストへの追加・並び替えは `bookIds` の順序がそのまま正になる。
    /// ストア順に引きずられないことを固定する（R3で守った並び順の非破壊・旧 `BookModelLookup` の観点を継承）
    func testUpdateReadingListPreservesRequestedBookOrder() async throws {
        let first = sampleBookDTO(id: "a", title: "A")
        let second = sampleBookDTO(id: "b", title: "B")
        let third = sampleBookDTO(id: "c", title: "C")
        // 挿入順は a → b → c
        try await repos.books.addBook(first, coverImageData: nil)
        try await repos.books.addBook(second, coverImageData: nil)
        try await repos.books.addBook(third, coverImageData: nil)

        var list = makeListDTO(id: "list", bookIds: [])
        try await repos.readingLists.addReadingList(list)

        // 逆順・未知IDを混ぜて要求する
        list.bookIds = ["c", "unknown", "a", "b"]
        try await repos.readingLists.updateReadingList(list)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.books.map(\.id), ["c", "a", "b"], "解決できない id は落とし、残りは要求順を保つ")
    }

    // MARK: - 表紙画像（レビュー S4-4）

    private func makeCoverData(_ byte: UInt8, count: Int = 32) -> Data {
        Data(repeating: byte, count: count)
    }

    /// ① `updateCoverImage(data:)` / `(nil)` → `loadCoverImage` の読み戻しと `hasCoverImage` の追従
    func testUpdateCoverImageRoundTripsAndTracksHasCoverImage() async throws {
        let book = sampleBookDTO(id: "cover-book")
        try await repos.books.addBook(book, coverImageData: nil)

        var observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.first?.hasCoverImage, false)
        var loaded = await repos.books.loadCoverImage(bookId: "cover-book")
        XCTAssertNil(loaded)

        // 設定
        let data = makeCoverData(0xAB)
        try await repos.books.updateCoverImage(bookId: "cover-book", data: data)
        loaded = await repos.books.loadCoverImage(bookId: "cover-book")
        XCTAssertEqual(loaded, data)
        observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.first?.hasCoverImage, true)
        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "cover-book"), true)

        // 削除
        try await repos.books.updateCoverImage(bookId: "cover-book", data: nil)
        loaded = await repos.books.loadCoverImage(bookId: "cover-book")
        XCTAssertNil(loaded)
        observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.first?.hasCoverImage, false)
        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "cover-book"), false)
    }

    /// ② 本を削除したら `loadCoverImage` は nil を返し、表紙キャッシュも残らない
    func testDeletingBookDropsItsCoverImage() async throws {
        let book = sampleBookDTO(id: "doomed")
        try await repos.books.addBook(book, coverImageData: makeCoverData(0x11))
        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "doomed"), true)

        try await repos.books.deleteBook(id: "doomed")

        let loaded = await repos.books.loadCoverImage(bookId: "doomed")
        XCTAssertNil(loaded)
        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "doomed"), false)
    }

    /// 口座ごと削除しても、所属本の表紙キャッシュが取り残されない
    func testDeletingPassbookDropsCoverImagesOfItsBooks() async throws {
        let passbook = samplePassbookDTO()
        try await repos.passbooks.addPassbook(passbook)
        let book = sampleBookDTO(id: "in-passbook", passbookId: passbook.id)
        try await repos.books.addBook(book, coverImageData: makeCoverData(0x22))
        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "in-passbook"), true)

        try await repos.passbooks.deletePassbook(id: passbook.id)

        XCTAssertEqual(LocalCoverDataCache.shared.hasData(for: "in-passbook"), false)
    }

    /// ③ `RakutenBook.toBookDTO` が旧 `toUserBook` と同じ値を組み立てる（全フィールド等価）
    func testToBookDTOMapsAllFields() throws {
        let result = RakutenBook(
            title: "テスト書籍",
            author: "著者名",
            publisherName: "出版社名",
            isbn: "9781234567897",
            itemPrice: 1234,
            salesDate: "2024年05月01日",
            itemCaption: "本文の説明。320ページ。",
            mediumImageUrl: "https://example.com/medium.jpg",
            largeImageUrl: "https://example.com/large.jpg",
            size: "文庫",
            seriesName: "テストシリーズ",
            booksGenreId: nil
        )

        let before = Date()
        let dto = result.toBookDTO(passbookId: "pb-1")
        let after = Date()

        XCTAssertFalse(dto.id.isEmpty)
        XCTAssertEqual(dto.title, "テスト書籍")
        XCTAssertEqual(dto.author, "著者名")
        XCTAssertEqual(dto.isbn, "9781234567897")
        XCTAssertEqual(dto.publisher, "出版社名")
        XCTAssertEqual(dto.publishedYear, result.publishedYear)
        XCTAssertEqual(dto.seriesName, "テストシリーズ")
        XCTAssertEqual(dto.price, 1234)
        XCTAssertEqual(dto.imageURL, BookCoverImageURL.normalized("https://example.com/large.jpg"))
        XCTAssertEqual(dto.bookFormat, result.displayFormat)
        XCTAssertEqual(dto.pageCount, 320)
        XCTAssertEqual(dto.source, .api)
        XCTAssertNil(dto.memo)
        XCTAssertFalse(dto.isFavorite)
        // 旧 UserBook.init と同じ規則: 登録時価格は定価のコピー
        XCTAssertEqual(dto.priceAtRegistration, 1234)
        XCTAssertEqual(dto.currencyCode, AppCurrency(code: result.sourceCurrencyCode)?.code ?? AppCurrency.jpy.code)
        XCTAssertEqual(dto.passbookId, "pb-1")
        XCTAssertFalse(dto.hasCoverImage)
        // 日時は生成時刻（3つとも同値）
        XCTAssertEqual(dto.registeredAt, dto.createdAt)
        XCTAssertEqual(dto.createdAt, dto.updatedAt)
        XCTAssertGreaterThanOrEqual(dto.registeredAt, before)
        XCTAssertLessThanOrEqual(dto.registeredAt, after)
    }

    // MARK: - 保存失敗の意味論（レビュー S4-11 / S4-12）

    /// `passbookId` が引けないとき、旧実装と同じく**保存しない**（`passbook: nil` で保存しない）
    func testAddBookThrowsWhenPassbookMissing() async throws {
        let book = sampleBookDTO(id: "orphan", passbookId: "no-such-passbook")

        do {
            try await repos.books.addBook(book, coverImageData: nil)
            XCTFail("passbook が引けないのに保存された")
        } catch RepositoryError.passbookNotFound(let id) {
            XCTAssertEqual(id, "no-such-passbook")
        }

        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertTrue(observed.isEmpty, "保存されていないこと")
    }

    /// 更新でも「意図しない nil 化（総合口座送り）」を許さない
    func testUpdateBookThrowsWhenPassbookMissingAndKeepsOldValues() async throws {
        let passbook = samplePassbookDTO()
        try await repos.passbooks.addPassbook(passbook)
        let book = sampleBookDTO(id: "keeper", passbookId: passbook.id)
        try await repos.books.addBook(book, coverImageData: nil)

        var broken = book
        broken.title = "変更後"
        broken.passbookId = "no-such-passbook"
        do {
            try await repos.books.updateBook(broken)
            XCTFail("passbook が引けないのに更新された")
        } catch RepositoryError.passbookNotFound {
            // 期待どおり
        }

        let observed = await firstValue(repos.books.observeBooks())
        let saved = try XCTUnwrap(observed.first)
        XCTAssertEqual(saved.passbookId, passbook.id, "口座が nil 化していないこと")
        XCTAssertEqual(saved.title, book.title, "タイトルも巻き戻っていること")
    }

    /// 更新対象の本が無いときは throw する（log+return で握り潰さない・2026-07-26 オーナー判断）
    func testUpdateBookThrowsWhenBookMissing() async throws {
        let ghost = sampleBookDTO(id: "ghost")

        do {
            try await repos.books.updateBook(ghost)
            XCTFail("本が存在しないのに更新が成功として扱われた")
        } catch RepositoryError.bookNotFound(let id) {
            XCTAssertEqual(id, "ghost")
        }

        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertTrue(observed.isEmpty, "存在しない本が作られていないこと")
    }

    /// 表紙単独更新も同じ契約（更新系の not-found は throw）
    func testUpdateCoverImageThrowsWhenBookMissing() async throws {
        do {
            try await repos.books.updateCoverImage(bookId: "ghost", data: makeCoverData(0x55))
            XCTFail("本が存在しないのに表紙更新が成功として扱われた")
        } catch RepositoryError.bookNotFound(let id) {
            XCTAssertEqual(id, "ghost")
        }
    }

    /// 削除系の not-found は据え置き（冪等削除）
    func testDeleteBookIsIdempotentForMissingId() async throws {
        try await repos.books.deleteBook(id: "never-existed")
        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertTrue(observed.isEmpty)
    }

    // MARK: - 楽観更新の鮮度ガード（2026-07-26）

    /// 現在値がまだ自分の楽観値なら、直前の値へ書き戻す
    func testRollbackAppliesWhenCurrentStillMatchesOptimisticValue() {
        let previous = sampleBookDTO(id: "x", title: "元")
        var optimistic = previous
        optimistic.isFavorite.toggle()

        let value = OptimisticUpdate.rollbackValue(
            current: optimistic,
            optimistic: optimistic,
            previous: previous
        )
        XCTAssertEqual(value, previous)
    }

    /// 待っている間に別の値が入っていたら書き戻さない（自分より新しい値を踏み潰さない）
    func testRollbackSkippedWhenCurrentDivergedFromOptimisticValue() {
        let previous = sampleBookDTO(id: "x", title: "元")
        var optimistic = previous
        optimistic.isFavorite.toggle()
        // ストリームのyieldや別操作で先へ進んだ状態
        var newer = optimistic
        newer.title = "他経路で更新"

        let value = OptimisticUpdate.rollbackValue(
            current: newer,
            optimistic: optimistic,
            previous: previous
        )
        XCTAssertNil(value, "自分より新しい値を踏み潰さないこと")
    }

    /// `passbookId == nil`（未割当）は正常系
    func testAddBookWithoutPassbookSucceeds() async throws {
        let book = sampleBookDTO(id: "unassigned", passbookId: nil)
        try await repos.books.addBook(book, coverImageData: nil)

        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.map(\.id), ["unassigned"])
        XCTAssertNil(observed.first?.passbookId)
    }

    /// 書誌と表紙が1トランザクションで反映される（S4-12）
    func testUpdateBookWritesFieldsAndCoverTogether() async throws {
        let book = sampleBookDTO(id: "combined")
        try await repos.books.addBook(book, coverImageData: nil)

        var updated = book
        updated.title = "新しいタイトル"
        try await repos.books.updateBook(updated, cover: .replace(makeCoverData(0x33)))

        let observed = await firstValue(repos.books.observeBooks())
        let saved = try XCTUnwrap(observed.first)
        XCTAssertEqual(saved.title, "新しいタイトル")
        XCTAssertEqual(saved.hasCoverImage, true)
        let loaded = await repos.books.loadCoverImage(bookId: "combined")
        XCTAssertEqual(loaded, makeCoverData(0x33))
    }

    /// `.unchanged` は表紙に触れない（お気に入り・メモ更新で表紙が消えない）
    func testUpdateBookUnchangedKeepsCover() async throws {
        let book = sampleBookDTO(id: "keep-cover")
        try await repos.books.addBook(book, coverImageData: makeCoverData(0x44))

        var updated = book
        updated.isFavorite.toggle()
        try await repos.books.updateBook(updated)

        let loaded = await repos.books.loadCoverImage(bookId: "keep-cover")
        XCTAssertEqual(loaded, makeCoverData(0x44))
        let observed = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(observed.first?.hasCoverImage, true)
    }

    func testDeletingMultiplePassbooksLeavesOthersIntact() async throws {
        let keep = samplePassbookDTO(id: "keep", sortOrder: 0)
        let drop1 = samplePassbookDTO(id: "drop1", sortOrder: 1)
        let drop2 = samplePassbookDTO(id: "drop2", sortOrder: 2)
        try await repos.passbooks.addPassbook(keep)
        try await repos.passbooks.addPassbook(drop1)
        try await repos.passbooks.addPassbook(drop2)
        try await repos.books.addBook(sampleBookDTO(passbookId: keep.id), coverImageData: nil)
        try await repos.books.addBook(sampleBookDTO(passbookId: drop1.id), coverImageData: nil)
        try await repos.books.addBook(sampleBookDTO(passbookId: drop2.id), coverImageData: nil)

        // PassbookListView と同様: 削除対象を先に配列確定してから逐次削除
        let targets = [drop1, drop2]
        for target in targets {
            try await repos.passbooks.deletePassbook(id: target.id)
        }
        // 未知IDは冪等
        try await repos.passbooks.deletePassbook(id: "unknown-id")

        let passbooks = await firstValue(repos.passbooks.observePassbooks())
        let books = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(passbooks.map(\.id), ["keep"])
        XCTAssertEqual(books.map(\.passbookId), [keep.id])
    }

    // MARK: - R4ステップ5: ReadingList

    /// 8.2節: 並び替え→再起動→維持。
    /// `updateReadingList` で書いた並びがオンディスクに残り、コンテナ再生成（＝再起動相当）後も同じ順で読めること
    func testReorderedBookOrderPersistsAcrossContainerReload() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("reorder-test.store")
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        // 1回目の「起動」: 3冊を登録してリストへ入れ、逆順に並び替える
        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let firstContainer = try ModelContainer(for: schema, configurations: [config])
            let repos = AppRepositories(container: firstContainer)
            for id in ["a", "b", "c"] {
                try await repos.books.addBook(sampleBookDTO(id: id, title: id), coverImageData: nil)
            }
            try await repos.readingLists.addReadingList(
                makeListDTO(id: "list", bookIds: ["a", "b", "c"])
            )

            let stored = await firstValue(repos.readingLists.observeReadingLists())
            var list = try XCTUnwrap(stored.first)
            list = list.replacingBooks(list.books.reversed(), updatedAt: Date())
            try await repos.readingLists.updateReadingList(list)
        }

        // 2回目の「起動」（別コンテナ）で読み出し
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let secondContainer = try ModelContainer(for: schema, configurations: [config])
        let reopened = AppRepositories(container: secondContainer)
        let observed = await firstValue(reopened.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.bookIds, ["c", "b", "a"])
        XCTAssertEqual(dto.books.map(\.id), ["c", "b", "a"])
    }

    /// 8.2節: タイトル変更を挟んでも並びが崩れない（R3で直した旧バグの再発防止）。
    /// `EditReadingListView` は DTO スナップショットの全フィールドを書き戻すため、
    /// メタ情報だけを編集したつもりでも `bookIds` を巻き戻していないことを固定する
    func testTitleEditKeepsBookOrder() async throws {
        for id in ["a", "b", "c"] {
            try await repos.books.addBook(sampleBookDTO(id: id, title: id), coverImageData: nil)
        }
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["c", "a", "b"]))

        let stored = await firstValue(repos.readingLists.observeReadingLists())
        var list = try XCTUnwrap(stored.first)
        // EditReadingListView.saveChanges と同じ形（タイトル・色・updatedAt のみ差し替え）
        list.title = "改名後"
        list.colorIndex = 3
        list.updatedAt = Date()
        try await repos.readingLists.updateReadingList(list)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.title, "改名後")
        XCTAssertEqual(dto.bookIds, ["c", "a", "b"], "タイトル変更で並びが崩れないこと")
        XCTAssertEqual(dto.books.map(\.id), ["c", "a", "b"])
    }

    /// レビュー S5-1: `bookIds` が `books` を網羅していないリストを、メタ情報だけ編集して
    /// 保存しても所属が消えないこと。
    ///
    /// 読み（`ReadingListOrdering`）は `bookIds` に無い `books` を末尾へ足す寛容さを持つ。
    /// 書きが `bookIds` だけを見ると、その差分が保存1回で確定的に失われる（`bookIds` が
    /// 空なら所属が丸ごと消える）。`testTitleEditKeepsBookOrder` は常に `bookIds` が
    /// 全件を網羅しているためこの軸を通らない
    func testTitleEditKeepsBooksWhenBookIdsDoNotCoverThem() async throws {
        for id in ["a", "b", "c"] {
            try await repos.books.addBook(sampleBookDTO(id: id, title: id), coverImageData: nil)
        }
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["a", "b", "c"]))

        // R3移行後に不整合が入った状態を @Model へ直接作る（`bookIds` だけが空）
        let target = "list"
        let descriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.uuid == target })
        let model = try XCTUnwrap(try container.mainContext.fetch(descriptor).first)
        model.bookIds = []
        try container.mainContext.save()

        let stored = await firstValue(repos.readingLists.observeReadingLists())
        var list = try XCTUnwrap(stored.first)
        XCTAssertTrue(list.bookIds.isEmpty, "前提: bookIds は空")
        XCTAssertEqual(list.books.count, 3, "読みは寛容なので books は3件見える")

        // EditReadingListView.saveChanges と同じ形（タイトルだけ差し替え）
        list.title = "改名後"
        list.updatedAt = Date()
        try await repos.readingLists.updateReadingList(list)

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        let dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.title, "改名後")
        XCTAssertEqual(Set(dto.books.map(\.id)), ["a", "b", "c"], "bookIds に無い所属が刈られないこと")
        XCTAssertEqual(
            Set(dto.bookIds), ["a", "b", "c"],
            "書き込みのたびに bookIds が books を網羅する状態へ正規化されること"
        )
    }

    /// レビュー S5-1 の裏側: 網羅性の救済が**本の除去を無効化していない**こと。
    /// 救済の相手を DTO の `books` ではなく永続化済みの `model.books` にすると、
    /// 外したはずの本が毎回戻ってきて除去が永久に効かなくなる
    func testRemovalStillWorksAfterMembershipFallback() async throws {
        for id in ["a", "b"] {
            try await repos.books.addBook(sampleBookDTO(id: id, title: id), coverImageData: nil)
        }
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["a", "b"]))

        let stored = await firstValue(repos.readingLists.observeReadingLists())
        let list = try XCTUnwrap(stored.first)
        let remaining = list.books.filter { $0.id != "a" }
        try await repos.readingLists.updateReadingList(
            list.replacingBooks(remaining, updatedAt: Date())
        )

        var observed = await firstValue(repos.readingLists.observeReadingLists())
        var dto = try XCTUnwrap(observed.first)
        XCTAssertEqual(dto.books.map(\.id), ["b"], "除去した本が戻らないこと")

        // 最後の1冊を外して空にできること（空の bookIds が「未設定」と解釈されない）
        try await repos.readingLists.updateReadingList(
            dto.replacingBooks([], updatedAt: Date())
        )
        observed = await firstValue(repos.readingLists.observeReadingLists())
        dto = try XCTUnwrap(observed.first)
        XCTAssertTrue(dto.books.isEmpty, "全部外せば空にできること")
        XCTAssertTrue(dto.bookIds.isEmpty)
    }

    /// 8.2節: 共有URLの同一性。`legacyShareId` は旧 `ShareService` が使っていた
    /// `"\(persistentModelID)"` と同一文字列であり（＝R4前後で同じURL）、
    /// メタ編集・並び替えを挟んでも変わらない（前提6）
    func testLegacyShareIdMatchesPersistentModelIDAndSurvivesEdits() async throws {
        try await repos.books.addBook(sampleBookDTO(id: "a", title: "A"), coverImageData: nil)
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["a"]))

        // 旧実装が組み立てていた共有IDを @Model から直接算出する
        let target = "list"
        let descriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.uuid == target })
        let model = try XCTUnwrap(try container.mainContext.fetch(descriptor).first)
        let legacyIdFromModel = "\(model.persistentModelID)"

        let stored = await firstValue(repos.readingLists.observeReadingLists())
        var list = try XCTUnwrap(stored.first)
        XCTAssertEqual(list.legacyShareId, legacyIdFromModel)
        XCTAssertNotEqual(list.legacyShareId, list.id, "uuid ではなく persistentModelID を運ぶこと（前提6）")

        // 編集を挟んでも共有IDは変わらない＝同じリストは同じURL
        list.title = "改名後"
        list.updatedAt = Date()
        try await repos.readingLists.updateReadingList(list)

        let reloaded = await firstValue(repos.readingLists.observeReadingLists())
        let after = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(after.legacyShareId, legacyIdFromModel)
    }

    /// 8.3節-3: 作成フローのキャンセルでリストが残らない。
    /// 旧実装は「空リストを作って delete」だったが、新実装は**確定するまで作らない**
    func testConfirmedCreationOnlyProducesListWhenBooksArePicked() async throws {
        let draft = makeListDTO(id: "draft")
        let now = Date()

        XCTAssertNil(
            ReadingListDTO.confirmedCreation(draft: draft, pickedBooks: [], now: now),
            "本が選ばれなければリストを作らない"
        )
        XCTAssertNil(ReadingListDTO.confirmedCreation(draft: nil, pickedBooks: [], now: now))

        let picked = [sampleBookDTO(id: "b1"), sampleBookDTO(id: "b2")]
        let created = try XCTUnwrap(
            ReadingListDTO.confirmedCreation(draft: draft, pickedBooks: picked, now: now)
        )
        XCTAssertEqual(created.id, draft.id)
        XCTAssertEqual(created.bookIds, ["b1", "b2"], "選択順がそのまま並び順になる")
        XCTAssertEqual(created.updatedAt, now)
        XCTAssertEqual(created.createdAt, draft.createdAt, "作成日時はタイトル確定時のまま")
    }

    /// キャンセル相当では `confirmedCreation` が nil を返し、永続化する対象が生まれない。
    ///
    /// **担保範囲に注意（レビュー S5-7）**: 検証しているのは純関数の戻り値までで、
    /// `AddReadingListView.finishCreation` の結線（nil なら `addReadingList` を呼ばない）は
    /// テスト側のコードで模しているにすぎない。結線が壊れてもこのテストはグリーンのままなので、
    /// そちらはコードレビューで担保する（8.2節の切り分け方針）
    func testCancelledCreationProducesNoDTO() async throws {
        let draft = makeListDTO(id: "draft")
        if let list = ReadingListDTO.confirmedCreation(draft: draft, pickedBooks: [], now: Date()) {
            try await repos.readingLists.addReadingList(list)
        }

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertTrue(observed.isEmpty)
    }

    /// 更新系の not-found は throw する（4.5節・本／口座と同じ契約）
    func testUpdateReadingListThrowsWhenListMissing() async throws {
        let ghost = makeListDTO(id: "ghost")

        do {
            try await repos.readingLists.updateReadingList(ghost)
            XCTFail("リストが存在しないのに更新が成功として扱われた")
        } catch RepositoryError.readingListNotFound(let id) {
            XCTAssertEqual(id, "ghost")
        }

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertTrue(observed.isEmpty, "存在しないリストが作られていないこと")
    }

    /// 削除系の not-found は据え置き（冪等削除）
    func testDeleteReadingListIsIdempotentForMissingId() async throws {
        try await repos.readingLists.deleteReadingList(id: "never-existed")
        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertTrue(observed.isEmpty)
    }

    /// リストからの本の除去は `bookIds` からだけ消し、本そのものは残す
    func testRemovingBookFromListKeepsTheBook() async throws {
        try await repos.books.addBook(sampleBookDTO(id: "a", title: "A"), coverImageData: nil)
        try await repos.books.addBook(sampleBookDTO(id: "b", title: "B"), coverImageData: nil)
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["a", "b"]))

        let stored = await firstValue(repos.readingLists.observeReadingLists())
        let list = try XCTUnwrap(stored.first)
        let remaining = list.books.filter { $0.id != "a" }
        try await repos.readingLists.updateReadingList(
            list.replacingBooks(remaining, updatedAt: Date())
        )

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertEqual(try XCTUnwrap(observed.first).bookIds, ["b"])
        let books = await firstValue(repos.books.observeBooks())
        XCTAssertEqual(Set(books.map(\.id)), ["a", "b"], "リストから外しただけで本は消えない")
    }

    /// `ReadingListDTO.books` の表紙もキャッシュへ同期投入される（`LocalCoverImage` の同期ヒット・4.6節）。
    /// リスト系Viewは `observeBooks()` を購読しないため、ここが抜けると手動表紙が初回フレームで出ない
    func testReadingListFetchPrimesLocalCoverCache() async throws {
        try await repos.books.addBook(
            sampleBookDTO(id: "with-cover"),
            coverImageData: makeCoverData(0x66)
        )
        try await repos.readingLists.addReadingList(makeListDTO(id: "list", bookIds: ["with-cover"]))
        // addBook 経由で入ったキャッシュを落とし、「リスト側の fetch だけ」で埋まることを見る
        LocalCoverDataCache.shared.removeAll()
        XCTAssertFalse(LocalCoverDataCache.shared.hasData(for: "with-cover"))

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertEqual(try XCTUnwrap(observed.first).books.map(\.id), ["with-cover"])
        XCTAssertTrue(LocalCoverDataCache.shared.hasData(for: "with-cover"))
    }

    /// リストの書き込みもチェンジパルスに乗る（ステップ4までは購読者ゼロで未検証だった経路）
    func testReadingListWriteYieldsOnStream() async throws {
        let stream = repos.readingLists.observeReadingLists()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial?.isEmpty, true)

        try await repos.readingLists.addReadingList(makeListDTO(id: "list", title: "新規"))
        let afterAdd = await iterator.next()
        XCTAssertEqual(afterAdd?.map(\.title), ["新規"])

        try await repos.readingLists.deleteReadingList(id: "list")
        let afterDelete = await iterator.next()
        XCTAssertEqual(afterDelete?.isEmpty, true)
    }

    /// `latestSnapshot` は `observe〜` の yield と同じ正準ソート（`updatedAt` 降順）で埋まる（4.6節の不変条件1）
    func testReadingListLatestSnapshotMatchesStreamOrder() async throws {
        try await repos.readingLists.addReadingList(
            makeListDTO(id: "old", title: "古い", updatedAt: Date(timeIntervalSince1970: 10))
        )
        try await repos.readingLists.addReadingList(
            makeListDTO(id: "new", title: "新しい", updatedAt: Date(timeIntervalSince1970: 20))
        )

        let observed = await firstValue(repos.readingLists.observeReadingLists())
        XCTAssertEqual(observed.map(\.id), ["new", "old"])
        XCTAssertEqual(repos.readingLists.latestSnapshot.map(\.id), observed.map(\.id))
    }
}
