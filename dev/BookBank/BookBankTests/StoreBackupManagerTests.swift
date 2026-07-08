//
//  StoreBackupManagerTests.swift
//  BookBankTests
//
//  R3ステップ1: 移行前バックアップ＋復元リトライ経路のテスト
//  設計メモ: docs/r3-uuid-migration-notes.md 4.5節①
//

import Foundation
import SwiftData
import Testing
@testable import BookBank

@MainActor
struct StoreBackupManagerTests {

    // MARK: - Helpers

    /// 一時ディレクトリと、その中のダミーストアURLを作る
    private func makeTempStore() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("default.store"))
    }

    private func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    // MARK: - 判定（純関数・前提10の容量スキップ含む）

    @Test func decisionBacksUpInNormalCase() {
        let decision = StoreBackupManager.backupDecision(
            migrationCompleted: false, backupExists: false,
            freeSpace: 1_000, requiredSpace: 100
        )
        #expect(decision == .backup)
    }

    @Test func decisionSkipsWhenMigrationCompleted() {
        let decision = StoreBackupManager.backupDecision(
            migrationCompleted: true, backupExists: false,
            freeSpace: 1_000, requiredSpace: 100
        )
        #expect(decision == .skipMigrationCompleted)
    }

    @Test func decisionSkipsWhenBackupAlreadyExists() {
        // 移行前の無傷のスナップショットを上書きしない
        let decision = StoreBackupManager.backupDecision(
            migrationCompleted: false, backupExists: true,
            freeSpace: 1_000, requiredSpace: 100
        )
        #expect(decision == .skipBackupExists)
    }

    @Test func decisionSkipsWhenInsufficientSpace() {
        // 必要サイズ×1.2 を下回る空きはスキップ（前提10）。境界ちょうどは実行
        let short = StoreBackupManager.backupDecision(
            migrationCompleted: false, backupExists: false,
            freeSpace: 119, requiredSpace: 100
        )
        #expect(short == .skipInsufficientSpace)

        let exact = StoreBackupManager.backupDecision(
            migrationCompleted: false, backupExists: false,
            freeSpace: 120, requiredSpace: 100
        )
        #expect(exact == .backup)
    }

    // MARK: - コピー・復元のラウンドトリップ

    @Test func backupAndRestoreRoundTrip() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // ストア一式（本体・WAL・外部ストレージフォルダ）を模擬
        try Data("original-store".utf8).write(to: store)
        try Data("original-wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))
        let support = directory.appendingPathComponent(".default_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("cover-image".utf8).write(to: support.appendingPathComponent("cover.jpg"))

        try StoreBackupManager.performBackup(storeURL: store)
        #expect(StoreBackupManager.backupExists(storeURL: store))

        // 破損を模擬（本体をゴミに・外部ストレージを喪失）
        try Data("corrupted".utf8).write(to: store)
        try FileManager.default.removeItem(at: support)

        let restored = try StoreBackupManager.restoreBackup(storeURL: store)
        #expect(restored)
        #expect(try contents(of: store) == "original-store")
        #expect(try contents(of: directory.appendingPathComponent("default.store-wal")) == "original-wal")
        #expect(try contents(of: support.appendingPathComponent("cover.jpg")) == "cover-image")
    }

    @Test func backupDoesNotOverwriteExistingSnapshot() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("version-1".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store)

        // 2回目の performBackup（例: 1回目の移行が中断した後の再起動）では上書きしない
        try Data("version-2".utf8).write(to: store)
        try StoreBackupManager.performBackup(storeURL: store)

        let backedUpStore = StoreBackupManager.backupDirectoryURL(for: store)
            .appendingPathComponent("default.store")
        #expect(try contents(of: backedUpStore) == "version-1")
    }

    @Test func restoreWithoutBackupReturnsFalse() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)

        #expect(try StoreBackupManager.restoreBackup(storeURL: store) == false)
        // 復元が実施されない場合、現行ファイルは無傷のまま
        #expect(try contents(of: store) == "store")
    }

    @Test func deleteBackupRemovesSnapshot() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("store".utf8).write(to: store)

        try StoreBackupManager.performBackup(storeURL: store)
        #expect(StoreBackupManager.backupExists(storeURL: store))

        StoreBackupManager.deleteBackup(storeURL: store)
        #expect(!StoreBackupManager.backupExists(storeURL: store))
    }

    @Test func requiredSpaceSumsFilesAndDirectories() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0, count: 100).write(to: store)
        try Data(repeating: 0, count: 50).write(to: directory.appendingPathComponent("default.store-wal"))
        let support = directory.appendingPathComponent(".default_SUPPORT", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 25).write(to: support.appendingPathComponent("cover.jpg"))

        #expect(StoreBackupManager.requiredSpaceForBackup(storeURL: store) == 175)
    }

    // MARK: - 復元リトライ経路の統合テスト（故障注入）

    @Test func containerRecoveryRestoresCorruptedStore() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        // 正常なストアを作成して1件保存し、スコープを抜けて閉じる
        do {
            let configuration = ModelConfiguration(schema: schema, url: store)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Passbook(name: "テスト口座"))
            try context.save()
        }

        try StoreBackupManager.performBackup(storeURL: store)

        // 故障注入: ストア本体を非SQLiteのゴミデータで上書きし、WAL/SHM を除去
        try Data("this is not a sqlite database".utf8).write(to: store)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-shm"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("default.store-wal"))

        // 生成失敗 → バックアップ復元 → 1回リトライで成功し、データが無傷であること
        let configuration = ModelConfiguration(schema: schema, url: store)
        let container = try StoreBackupManager.makeContainerWithRecovery(
            schema: schema,
            configuration: configuration,
            storeURL: store
        )
        let context = ModelContext(container)
        let passbooks = try context.fetch(FetchDescriptor<Passbook>())
        #expect(passbooks.count == 1)
        #expect(passbooks.first?.name == "テスト口座")
    }

    @Test func containerRecoveryThrowsWhenNoBackupExists() throws {
        let (directory, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([
            Passbook.self, UserBook.self, Subscription.self, ReadingList.self, MonthlyMemo.self
        ])

        // バックアップなしで破損ストアを開く → 復元できず throw（fatalError 相当の経路）
        try Data("this is not a sqlite database".utf8).write(to: store)
        let configuration = ModelConfiguration(schema: schema, url: store)
        #expect(throws: (any Error).self) {
            _ = try StoreBackupManager.makeContainerWithRecovery(
                schema: schema,
                configuration: configuration,
                storeURL: store
            )
        }
    }
}
