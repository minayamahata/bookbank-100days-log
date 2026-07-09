//
//  ReadingListOrderMigrationTests.swift
//  BookBankTests
//
//  R3ステップ3: 並び順変換（stableID→uuid転記）・検証(c)・汚れデータ踏襲のテスト
//  設計メモ: docs/r3-uuid-migration-notes.md 5.3・4.5節②(c)
//

import Foundation
import SwiftData
import Testing
@testable import BookBank

@MainActor
struct ReadingListOrderMigrationTests {

    typealias Book = (stableID: String, uuid: String)

    // MARK: - resolveLegacyOrder（旧ロジックの忠実な再現）

    @Test func legacyOrderFollowsRecordedOrder() {
        let books: [Book] = [("sA", "uA"), ("sB", "uB"), ("sC", "uC")]
        let result = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: ["sC", "sA", "sB"], books: books)
        #expect(result == ["uC", "uA", "uB"])
    }

    @Test func legacyOrderAppendsUnlistedAtEnd() {
        // bookOrderData に未登録の本は末尾へ（現行フォールバック）
        let books: [Book] = [("sA", "uA"), ("sB", "uB"), ("sC", "uC")]
        let result = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: ["sB"], books: books)
        #expect(result == ["uB", "uA", "uC"])
    }

    @Test func legacyOrderNaturalWhenNoOrderData() {
        let books: [Book] = [("sA", "uA"), ("sB", "uB")]
        let result = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: [], books: books)
        #expect(result == ["uA", "uB"])
    }

    @Test func legacyOrderSkipsDeletedReferences() {
        // 記録された本が既に削除済み（books に無い stableID）→ スキップ（旧挙動踏襲）
        let books: [Book] = [("sA", "uA"), ("sB", "uB")]
        let result = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: ["sX", "sB", "sA"], books: books)
        #expect(result == ["uB", "uA"])
    }

    @Test func legacyOrderDropsStableIDCollisionVictimLikeOldLogic() {
        // stableID衝突: 2冊が同一stableID。旧ロジックは先勝ち＋usedで片方を欠落させる（ケースd）
        let books: [Book] = [("dup", "uA"), ("dup", "uB"), ("sC", "uC")]
        let result = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: ["dup", "sC"], books: books)
        // uB（衝突の犠牲）は legacySeq に含まれない＝旧の非表示を忠実に踏襲
        #expect(result == ["uA", "uC"])
    }

    // MARK: - resolveUUIDOrder（新ロジック）

    @Test func uuidOrderFollowsBookIds() {
        let result = ReadingListOrderMigration.resolveUUIDOrder(bookIds: ["uC", "uA", "uB"], bookUUIDs: ["uA", "uB", "uC"])
        #expect(result == ["uC", "uA", "uB"])
    }

    @Test func uuidOrderAppendsUnlistedAtEnd() {
        let result = ReadingListOrderMigration.resolveUUIDOrder(bookIds: ["uB"], bookUUIDs: ["uA", "uB", "uC"])
        #expect(result == ["uB", "uA", "uC"])
    }

    @Test func uuidOrderNaturalWhenNoBookIds() {
        let result = ReadingListOrderMigration.resolveUUIDOrder(bookIds: [], bookUUIDs: ["uA", "uB"])
        #expect(result == ["uA", "uB"])
    }

    // MARK: - 検証(c): 完全一致（順序ずれ・欠落・重複を検出）

    @Test func ordersMatchWhenIdentical() {
        #expect(ReadingListOrderMigration.ordersMatch(before: ["uA", "uB", "uC"], after: ["uA", "uB", "uC"]))
    }

    @Test func ordersMatchDetectsReorder() {
        #expect(!ReadingListOrderMigration.ordersMatch(before: ["uA", "uB", "uC"], after: ["uA", "uC", "uB"]))
    }

    @Test func ordersMatchDetectsOmission() {
        #expect(!ReadingListOrderMigration.ordersMatch(before: ["uA", "uB", "uC"], after: ["uA", "uB"]))
    }

    @Test func ordersMatchDetectsDuplicate() {
        #expect(!ReadingListOrderMigration.ordersMatch(before: ["uA", "uB"], after: ["uA", "uB", "uB"]))
    }

    // MARK: - 変換の round-trip 一致（転記→復元で同一）

    @Test func transcriptionRoundTripMatches() {
        let books: [Book] = [("sA", "uA"), ("sB", "uB"), ("sC", "uC")]
        let legacySeq = ReadingListOrderMigration.resolveLegacyOrder(orderIDs: ["sC", "sA", "sB"], books: books)
        let restored = ReadingListOrderMigration.resolveUUIDOrder(bookIds: legacySeq, bookUUIDs: legacySeq)
        #expect(ReadingListOrderMigration.ordersMatch(before: legacySeq, after: restored))
    }

    // MARK: - タイトル変更後も順序維持（旧バグ解消）

    @Test func uuidOrderSurvivesTitleChange() {
        // bookIds は uuid ベースなので、タイトル（＝旧stableID）が変わっても順序は不変
        let bookIds = ["uC", "uA", "uB"]
        let afterTitleChange = ReadingListOrderMigration.resolveUUIDOrder(bookIds: bookIds, bookUUIDs: ["uA", "uB", "uC"])
        #expect(afterTitleChange == ["uC", "uA", "uB"])
    }

    // MARK: - 統合: 実データ変換

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func migrationTranscribesLegacyOrderToBookIds() throws {
        let context = try makeInMemoryContext()
        UserDefaults.standard.removeObject(forKey: "didMigrateBookOrderToUUIDV1")

        let list = ReadingList(title: "リスト")
        let bookA = UserBook(title: "A")
        let bookB = UserBook(title: "B")
        let bookC = UserBook(title: "C")
        list.books = [bookA, bookB, bookC]
        context.insert(list)
        [bookA, bookB, bookC].forEach { context.insert($0) }

        // 旧 bookOrderData を「C, A, B」の stableID 配列で作る
        let orderIDs = [bookC, bookA, bookB].map {
            ReadingListOrderMigration.legacyStableID(title: $0.title, createdAt: $0.createdAt)
        }
        list.bookOrderData = String(data: try JSONEncoder().encode(orderIDs), encoding: .utf8)
        try context.save()

        ReadingListOrderMigration.migrateIfNeeded(context: context)

        let migrated = try context.fetch(FetchDescriptor<ReadingList>()).first!
        #expect(migrated.bookIds == [bookC.uuid, bookA.uuid, bookB.uuid])
        // orderedBooks（新ロジック）も同じ順序を返す
        #expect(migrated.orderedBooks.map(\.uuid) == [bookC.uuid, bookA.uuid, bookB.uuid])
        #expect(ReadingListOrderMigration.hasCompleted)

        UserDefaults.standard.removeObject(forKey: "didMigrateBookOrderToUUIDV1")
    }

    @Test func migrationSkipsListsWithExistingBookIds() throws {
        let context = try makeInMemoryContext()
        UserDefaults.standard.removeObject(forKey: "didMigrateBookOrderToUUIDV1")

        let list = ReadingList(title: "リスト")
        let bookA = UserBook(title: "A")
        let bookB = UserBook(title: "B")
        list.books = [bookA, bookB]
        // 既に bookIds が非空（saveBookOrder 新ロジックが先に走ったケース）
        list.bookIds = [bookB.uuid, bookA.uuid]
        context.insert(list)
        [bookA, bookB].forEach { context.insert($0) }
        try context.save()

        ReadingListOrderMigration.migrateIfNeeded(context: context)

        let result = try context.fetch(FetchDescriptor<ReadingList>()).first!
        // 二重変換されず、そのまま保持
        #expect(result.bookIds == [bookB.uuid, bookA.uuid])

        UserDefaults.standard.removeObject(forKey: "didMigrateBookOrderToUUIDV1")
    }
}
