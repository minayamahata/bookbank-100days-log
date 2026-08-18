import Foundation
import Testing
@testable import BookBank

struct RereadTargetResolverTests {
    private func book(
        id: String,
        title: String = "同じ本",
        author: String? = "著者",
        isbn: String? = "9784123456789",
        registeredAt: Date,
        createdAt: Date
    ) -> BookDTO {
        BookDTO(
            id: id,
            title: title,
            author: author,
            isbn: isbn,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: 1000,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: 1000,
            currencyCode: "JPY",
            registeredAt: registeredAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            passbookId: nil,
            hasCoverImage: false
        )
    }

    @Test func isbnMatchIgnoresTitle() {
        let item = book(
            id: "a",
            title: "別タイトル",
            registeredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        #expect(RereadTargetResolver.isSameBook(item, isbn: "9784123456789", title: "同じ本", author: "著者"))
        #expect(!RereadTargetResolver.isSameBook(item, isbn: "111", title: "別タイトル", author: "著者"))
    }

    @Test func titleAuthorMatchWhenISBNMissing() {
        let item = book(
            id: "a",
            isbn: nil,
            registeredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        #expect(RereadTargetResolver.isSameBook(item, isbn: nil, title: "同じ本", author: "著者"))
        #expect(!RereadTargetResolver.isSameBook(item, isbn: "", title: "同じ本", author: "別人"))
    }

    @Test func resolveUsesRegisteredCreatedThenId() {
        let newer = book(
            id: "z",
            registeredAt: Date(timeIntervalSince1970: 30),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let olderLaterCreate = book(
            id: "m",
            registeredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let oldest = book(
            id: "a",
            registeredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 5)
        )
        let sameStampLaterId = book(
            id: "b",
            registeredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 5)
        )
        let picked = RereadTargetResolver.resolveTarget(
            among: [newer, olderLaterCreate, sameStampLaterId, oldest],
            isbn: "9784123456789",
            title: "同じ本",
            author: "著者"
        )
        #expect(picked?.id == "a")
    }
}
