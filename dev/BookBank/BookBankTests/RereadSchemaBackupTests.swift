import Foundation
import SwiftData
import Testing
@testable import BookBank

@MainActor
struct RereadSchemaBackupTests {
    private func makeTempStore() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RereadSchemaBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("default.store"))
    }

    private func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test func backupCreatesRereadDirectoryAndLeavesR3Untouched() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("reread-store".utf8).write(to: store)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        StoreBackupManager.backupIfNeeded(storeURL: store, defaults: defaults, kind: .rereadSchemaV1)

        #expect(StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
        #expect(!StoreBackupManager.backupExists(storeURL: store, kind: .uuidBackfill))
        let backupStore = StoreBackupManager.backupDirectoryURL(for: store, kind: .rereadSchemaV1)
            .appendingPathComponent("default.store")
        #expect(try contents(of: backupStore) == "reread-store")
        #expect(
            StoreBackupManager.backupDirectoryURL(for: store, kind: .rereadSchemaV1).lastPathComponent
            == "PreRereadSchemaMigrationBackupV1"
        )
    }

    @Test func backupSkipsWhenValidationCompleted() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: StoreBackupManager.didValidateRereadSchemaV1Key)

        StoreBackupManager.backupIfNeeded(storeURL: store, defaults: defaults, kind: .rereadSchemaV1)

        #expect(!StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
    }

    @Test func backupSkipsWhenSnapshotAlreadyExists() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("version-1".utf8).write(to: store)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        StoreBackupManager.backupIfNeeded(storeURL: store, defaults: defaults, kind: .rereadSchemaV1)
        try Data("version-2".utf8).write(to: store)
        StoreBackupManager.backupIfNeeded(storeURL: store, defaults: defaults, kind: .rereadSchemaV1)

        let backupStore = StoreBackupManager.backupDirectoryURL(for: store, kind: .rereadSchemaV1)
            .appendingPathComponent("default.store")
        #expect(try contents(of: backupStore) == "version-1")
    }

    @Test func restoreRecoversFromRereadBackup() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("original".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store, kind: .rereadSchemaV1)
        try Data("broken".utf8).write(to: store)

        #expect(try StoreBackupManager.restoreBackup(storeURL: store, kind: .rereadSchemaV1))
        #expect(try contents(of: store) == "original")
    }

    @Test func containerRecoveryUsesRereadBackup() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        do {
            let configuration = ModelConfiguration(schema: schema, url: store)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Passbook(name: "再読前口座"))
            try context.save()
        }

        try StoreBackupManager.performBackup(storeURL: store, kind: .rereadSchemaV1)
        try Data("this is not a sqlite database".utf8).write(to: store)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-shm"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-wal"))

        let configuration = ModelConfiguration(schema: schema, url: store)
        let container = try StoreBackupManager.makeContainerWithRecovery(
            schema: schema,
            configuration: configuration,
            storeURL: store,
            kind: .rereadSchemaV1
        )
        let passbooks = try ModelContext(container).fetch(FetchDescriptor<Passbook>())
        #expect(passbooks.count == 1)
        #expect(passbooks.first?.name == "再読前口座")
    }

    @Test func containerRecoveryFallsBackToR3BackupWhenRereadBackupMissing() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        do {
            let configuration = ModelConfiguration(schema: schema, url: store)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Passbook(name: "R3口座"))
            try context.save()
        }

        try StoreBackupManager.performBackup(storeURL: store, kind: .uuidBackfill)
        #expect(!StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
        try Data("this is not a sqlite database".utf8).write(to: store)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-shm"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-wal"))

        let configuration = ModelConfiguration(schema: schema, url: store)
        let container = try StoreBackupManager.makeContainerWithRecovery(
            schema: schema,
            configuration: configuration,
            storeURL: store
        )
        let passbooks = try ModelContext(container).fetch(FetchDescriptor<Passbook>())
        #expect(passbooks.count == 1)
        #expect(passbooks.first?.name == "R3口座")
    }

    @Test func validationSuccessSetsKeyAndDeletesBackup() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store, kind: .rereadSchemaV1)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(UserBook(title: "検証用"))
        try context.save()

        RereadSchemaValidation.finalizeIfValid(
            context: context,
            storeURL: store,
            defaults: defaults,
            r3Completed: true,
            readingListCompleted: true
        )

        #expect(defaults.bool(forKey: StoreBackupManager.didValidateRereadSchemaV1Key))
        #expect(!StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
    }

    @Test func validationFailureKeepsKeyUnsetAndBackup() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store, kind: .rereadSchemaV1)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let book = UserBook(title: "壊れた再読")
        book.rereads = [RereadRecord(id: "", date: Date())]
        context.insert(book)
        try context.save()

        RereadSchemaValidation.finalizeIfValid(
            context: context,
            storeURL: store,
            defaults: defaults,
            r3Completed: true,
            readingListCompleted: true
        )

        #expect(!defaults.bool(forKey: StoreBackupManager.didValidateRereadSchemaV1Key))
        #expect(StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
    }

    @Test func finalizeWaitsForR3Completion() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store, kind: .rereadSchemaV1)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.insert(UserBook(title: "本"))
        try container.mainContext.save()

        RereadSchemaValidation.finalizeIfValid(
            context: container.mainContext,
            storeURL: store,
            defaults: defaults,
            r3Completed: false,
            readingListCompleted: true
        )

        #expect(!defaults.bool(forKey: StoreBackupManager.didValidateRereadSchemaV1Key))
        #expect(StoreBackupManager.backupExists(storeURL: store, kind: .rereadSchemaV1))
    }

    @Test func emptyRereadIdFailsPureValidation() {
        let book = UserBook(title: "不正")
        book.rereads = [RereadRecord(id: "", date: Date())]
        #expect(!RereadSchemaValidation.validateAllUserBooks([book]))
        book.rereads = [RereadRecord(date: Date())]
        #expect(RereadSchemaValidation.validateAllUserBooks([book]))
    }
}
