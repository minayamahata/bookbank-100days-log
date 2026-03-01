import XCTest
import SwiftData
@testable import BookBank

final class DataPersistenceTests: XCTestCase {
    
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
        let schema = Schema([UserBook.self, Passbook.self, ReadingList.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
    }
    
    // MARK: - UserBook CRUD
    
    func testCreateUserBook() throws {
        let book = UserBook(
            title: "吾輩は猫である",
            author: "夏目漱石",
            isbn: "9784101010014",
            publisher: "新潮社",
            price: 572,
            source: .manual
        )
        context.insert(book)
        try context.save()
        
        let descriptor = FetchDescriptor<UserBook>()
        let books = try context.fetch(descriptor)
        
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.title, "吾輩は猫である")
        XCTAssertEqual(books.first?.author, "夏目漱石")
        XCTAssertEqual(books.first?.isbn, "9784101010014")
        XCTAssertEqual(books.first?.publisher, "新潮社")
        XCTAssertEqual(books.first?.price, 572)
        XCTAssertEqual(books.first?.priceAtRegistration, 572)
        XCTAssertEqual(books.first?.source, .manual)
        XCTAssertFalse(books.first?.isFavorite ?? true)
    }
    
    func testFetchUserBook() throws {
        let book1 = UserBook(title: "こころ", author: "夏目漱石", source: .manual)
        let book2 = UserBook(title: "羅生門", author: "芥川龍之介", source: .manual)
        let book3 = UserBook(title: "走れメロス", author: "太宰治", source: .api)
        context.insert(book1)
        context.insert(book2)
        context.insert(book3)
        try context.save()
        
        let allDescriptor = FetchDescriptor<UserBook>()
        let allBooks = try context.fetch(allDescriptor)
        XCTAssertEqual(allBooks.count, 3)
        
        let apiBooks = allBooks.filter { $0.source == .api }
        XCTAssertEqual(apiBooks.count, 1)
        XCTAssertEqual(apiBooks.first?.title, "走れメロス")
    }
    
    func testUpdateUserBook() throws {
        let book = UserBook(title: "人間失格", author: "太宰治", source: .manual)
        context.insert(book)
        try context.save()
        
        XCTAssertFalse(book.isFavorite)
        XCTAssertNil(book.memo)
        
        book.isFavorite = true
        book.memo = "名作"
        book.updatedAt = Date()
        try context.save()
        
        let descriptor = FetchDescriptor<UserBook>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched.first?.isFavorite ?? false)
        XCTAssertEqual(fetched.first?.memo, "名作")
    }
    
    func testDeleteUserBook() throws {
        let book = UserBook(title: "銀河鉄道の夜", author: "宮沢賢治", source: .manual)
        context.insert(book)
        try context.save()
        
        let beforeDescriptor = FetchDescriptor<UserBook>()
        XCTAssertEqual(try context.fetch(beforeDescriptor).count, 1)
        
        context.delete(book)
        try context.save()
        
        let afterDescriptor = FetchDescriptor<UserBook>()
        XCTAssertEqual(try context.fetch(afterDescriptor).count, 0)
    }
    
    // MARK: - Passbook CRUD
    
    func testCreatePassbook() throws {
        let passbook = Passbook(name: "技術書", type: .custom, sortOrder: 1)
        context.insert(passbook)
        try context.save()
        
        let descriptor = FetchDescriptor<Passbook>()
        let passbooks = try context.fetch(descriptor)
        
        XCTAssertEqual(passbooks.count, 1)
        XCTAssertEqual(passbooks.first?.name, "技術書")
        XCTAssertEqual(passbooks.first?.type, .custom)
        XCTAssertEqual(passbooks.first?.sortOrder, 1)
        XCTAssertTrue(passbooks.first?.isActive ?? false)
        XCTAssertEqual(passbooks.first?.bookCount, 0)
    }
    
    func testCreateOverallPassbook() throws {
        let overall = Passbook.createOverall()
        context.insert(overall)
        try context.save()
        
        let descriptor = FetchDescriptor<Passbook>()
        let passbooks = try context.fetch(descriptor)
        
        XCTAssertEqual(passbooks.count, 1)
        XCTAssertEqual(passbooks.first?.name, "総合口座")
        XCTAssertEqual(passbooks.first?.type, .overall)
        XCTAssertTrue(passbooks.first?.isOverall ?? false)
    }
    
    // MARK: - Relationship Tests
    
    func testAddBookToPassbook() throws {
        let passbook = Passbook(name: "小説", type: .custom, sortOrder: 1)
        context.insert(passbook)
        
        let book1 = UserBook(title: "こころ", author: "夏目漱石", price: 400, source: .manual, passbook: passbook)
        let book2 = UserBook(title: "坊っちゃん", author: "夏目漱石", price: 350, source: .manual, passbook: passbook)
        context.insert(book1)
        context.insert(book2)
        try context.save()
        
        let descriptor = FetchDescriptor<Passbook>()
        let fetched = try context.fetch(descriptor)
        let fetchedPassbook = try XCTUnwrap(fetched.first)
        
        XCTAssertEqual(fetchedPassbook.bookCount, 2)
        XCTAssertEqual(fetchedPassbook.totalValue, 750)
        
        let titles = fetchedPassbook.userBooks.map { $0.title }.sorted()
        XCTAssertEqual(titles, ["こころ", "坊っちゃん"])
    }
    
    func testDeletePassbookCascadesBooks() throws {
        let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 2)
        context.insert(passbook)
        
        let book = UserBook(title: "ONE PIECE", author: "尾田栄一郎", source: .manual, passbook: passbook)
        context.insert(book)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserBook>()).count, 1)
        
        context.delete(passbook)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Passbook>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserBook>()).count, 0)
    }
    
    func testMoveBookBetweenPassbooks() throws {
        let novels = Passbook(name: "小説", type: .custom, sortOrder: 1)
        let favorites = Passbook(name: "お気に入り", type: .custom, sortOrder: 2)
        context.insert(novels)
        context.insert(favorites)
        
        let book = UserBook(title: "ノルウェイの森", author: "村上春樹", source: .manual, passbook: novels)
        context.insert(book)
        try context.save()
        
        XCTAssertEqual(novels.bookCount, 1)
        XCTAssertEqual(favorites.bookCount, 0)
        
        book.passbook = favorites
        try context.save()
        
        XCTAssertEqual(novels.bookCount, 0)
        XCTAssertEqual(favorites.bookCount, 1)
        XCTAssertEqual(book.passbook?.name, "お気に入り")
    }
}
