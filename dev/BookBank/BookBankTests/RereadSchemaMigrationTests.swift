import Foundation
import SwiftData
import Testing
@testable import BookBank

@MainActor
struct RereadSchemaMigrationTests {
    @Test func legacyStoreOpensWithNilRereadsAndKeepsExistingData() throws {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RereadSchemaLegacy", isDirectory: true)
        let sourceStore = fixtureDir.appendingPathComponent("legacy.store")
        #expect(FileManager.default.fileExists(atPath: sourceStore.path))

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RereadSchemaMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let destStore = workDir.appendingPathComponent("legacy.store")
        for item in StoreBackupManager.storeFileItems(for: sourceStore) {
            let dest = workDir.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: item.path) {
                try FileManager.default.copyItem(at: item, to: dest)
            }
        }

        let schema = Schema([
            Passbook.self,
            UserBook.self,
            Subscription.self,
            ReadingList.self,
            MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: destStore)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let books = try context.fetch(FetchDescriptor<UserBook>())
        #expect(books.count == 1)
        let book = try #require(books.first)
        #expect(book.uuid == "legacy-book-uuid")
        #expect(book.title == "レガシー本")
        #expect(book.author == "旧著者")
        #expect(book.isbn == "9784123456789")
        #expect(book.memo == "移行前メモ")
        #expect(book.isFavorite)
        #expect(book.priceAtRegistration == 1800)
        #expect(book.rereads == nil)

        let dto = ModelDTOMapping.bookDTO(from: book)
        #expect(dto.rereads.isEmpty)
        #expect(dto.readCount == 1)
        #expect(dto.passbookId == "legacy-passbook-uuid")
    }
}
