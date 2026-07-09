//
//  UUIDBackfillMigrationTests.swift
//  BookBankTests
//
//  R3ステップ2: UUIDバックフィルの採番判定・整合性検証・全行同一値救済のテスト
//  設計メモ: docs/r3-uuid-migration-notes.md 4.2・4.3・4.5節②(a)(b)
//

import Foundation
import SwiftData
import Testing
@testable import BookBank

@MainActor
struct UUIDBackfillMigrationTests {

    // MARK: - 採番判定（純関数）

    @Test func reassignmentEmptyWhenAllUnique() {
        let uuids = ["a", "b", "c"]
        #expect(UUIDBackfillMigration.indicesNeedingReassignment(currentUUIDs: uuids).isEmpty)
    }

    @Test func reassignmentTargetsEmptyStrings() {
        let uuids = ["a", "", "c", ""]
        let indices = UUIDBackfillMigration.indicesNeedingReassignment(currentUUIDs: uuids)
        #expect(indices == IndexSet([1, 3]))
    }

    @Test func reassignmentTargetsAllButFirstWhenAllIdentical() {
        // 全行同一値（4.2の落とし穴）→ 1件目以外すべて採番対象
        let uuids = ["dup", "dup", "dup", "dup"]
        let indices = UUIDBackfillMigration.indicesNeedingReassignment(currentUUIDs: uuids)
        #expect(indices == IndexSet([1, 2, 3]))
    }

    @Test func reassignmentTargetsDuplicatesKeepingFirst() {
        let uuids = ["a", "b", "a", "c", "b"]
        let indices = UUIDBackfillMigration.indicesNeedingReassignment(currentUUIDs: uuids)
        #expect(indices == IndexSet([2, 4]))
    }

    @Test func reassignmentEmptyForEmptyList() {
        #expect(UUIDBackfillMigration.indicesNeedingReassignment(currentUUIDs: []).isEmpty)
    }

    // MARK: - 検証(a) 件数一致

    @Test func countsMatchWhenEqual() {
        let counts = ["Passbook": 2, "UserBook": 10, "ReadingList": 1, "MonthlyMemo": 3]
        #expect(UUIDBackfillMigration.countsMatch(before: counts, after: counts))
    }

    @Test func countsMismatchWhenValueDiffers() {
        let before = ["UserBook": 10]
        let after = ["UserBook": 9]
        #expect(!UUIDBackfillMigration.countsMatch(before: before, after: after))
    }

    @Test func countsMismatchWhenKeyMissing() {
        let before = ["Passbook": 1, "UserBook": 2]
        let after = ["Passbook": 1]
        #expect(!UUIDBackfillMigration.countsMatch(before: before, after: after))
    }

    // MARK: - 検証(b) uuid充足

    @Test func uuidsFulfilledWhenNonEmptyAndUnique() {
        #expect(UUIDBackfillMigration.uuidsAreFulfilled(["a", "b", "c"]))
    }

    @Test func uuidsNotFulfilledWhenEmptyPresent() {
        #expect(!UUIDBackfillMigration.uuidsAreFulfilled(["a", "", "c"]))
    }

    @Test func uuidsNotFulfilledWhenDuplicatePresent() {
        #expect(!UUIDBackfillMigration.uuidsAreFulfilled(["a", "b", "a"]))
    }

    @Test func uuidsFulfilledForEmptyList() {
        #expect(UUIDBackfillMigration.uuidsAreFulfilled([]))
    }

    // MARK: - 新規モデル作成時に uuid が非空

    @Test func newModelsHaveNonEmptyUUID() {
        #expect(!Passbook(name: "口座").uuid.isEmpty)
        #expect(!UserBook(title: "本").uuid.isEmpty)
        #expect(!ReadingList(title: "リスト").uuid.isEmpty)
        #expect(!MonthlyMemo(year: 2026, month: 7).uuid.isEmpty)
    }

    // MARK: - 統合: 全行同一値の再現→バックフィルで救済

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func backfillRescuesAllIdenticalUUIDs() throws {
        let context = try makeInMemoryContext()
        UserDefaults.standard.removeObject(forKey: StoreBackupManager.didBackfillUUIDsKey)

        // 4.2の落とし穴を再現: 複数行を同一uuidで埋める（updatedAtも記録して不変を確認）
        var savedUpdatedAt: [Date] = []
        for i in 0..<5 {
            let book = UserBook(title: "本\(i)")
            book.uuid = "same-value"
            context.insert(book)
            savedUpdatedAt.append(book.updatedAt)
        }
        try context.save()

        UUIDBackfillMigration.migrateIfNeeded(context: context)

        let books = try context.fetch(FetchDescriptor<UserBook>())
        let uuids = books.map(\.uuid)
        #expect(uuids.allSatisfy { !$0.isEmpty })
        #expect(Set(uuids).count == books.count)  // 全行一意

        // uuid以外（updatedAt・title）に触れていないこと
        #expect(Set(books.map(\.title)) == Set((0..<5).map { "本\($0)" }))
        let updatedAtByTitle = Dictionary(uniqueKeysWithValues: zip((0..<5).map { "本\($0)" }, savedUpdatedAt))
        for book in books {
            #expect(book.updatedAt == updatedAtByTitle[book.title])
        }
    }

    @Test func backfillSetsFlagAndIsIdempotent() throws {
        let context = try makeInMemoryContext()
        UserDefaults.standard.removeObject(forKey: StoreBackupManager.didBackfillUUIDsKey)

        context.insert(Passbook(name: "口座"))
        context.insert(UserBook(title: "本"))
        try context.save()

        UUIDBackfillMigration.migrateIfNeeded(context: context)
        #expect(UserDefaults.standard.bool(forKey: StoreBackupManager.didBackfillUUIDsKey))

        // 既に一意なuuidを持つため、再実行しても値が変わらない（冪等）
        let uuidBefore = try context.fetch(FetchDescriptor<UserBook>()).first?.uuid
        UUIDBackfillMigration.migrateIfNeeded(context: context)
        let uuidAfter = try context.fetch(FetchDescriptor<UserBook>()).first?.uuid
        #expect(uuidBefore == uuidAfter)

        UserDefaults.standard.removeObject(forKey: StoreBackupManager.didBackfillUUIDsKey)
    }
}
