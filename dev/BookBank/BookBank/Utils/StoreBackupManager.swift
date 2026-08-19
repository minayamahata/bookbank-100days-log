import Foundation
import OSLog
import SwiftData

/// R3移行（UUID導入）前のストアバックアップと復元
/// 設計メモ: docs/r3-uuid-migration-notes.md 4.5節①
///
/// 最も危険な瞬間は ModelContainer 生成時に走る軽量スキーママイグレーションであるため、
/// バックアップは「ストアが開かれる前」に取得する（WAL込みでファイル一式をコピーすれば整合したスナップショットになる）。
/// バックアップは追加の防御層であり、それ自体が起動障害の原因になってはならない
/// （失敗・容量不足時はスキップして通常起動する。設計メモ前提10）。
///
/// **バックアップ対象はDBファイル（`default.store`・`-shm`・`-wal`）のみ**。
/// 移行（スキーマ変更・UUIDバックフィル・並び順変換）が書き換えるのはDBだけで、
/// 書影（`.externalStorage` の外部blob）は移行中に不変であり保護不要なため対象外とする。
/// これにより必要容量が数MB規模に収まり、容量不足によるスキップが事実上発生しなくなる。
/// externalStorage をコピー対象にも復元削除対象にも含めないことで、復元時に画像を削除する事故が構造的に起きない。
/// 移行前バックアップの種類。R3とR4.7は完了キーも保存先も分ける。
enum StoreBackupKind: Equatable, Sendable {
    /// R3 UUIDバックフィル（`didBackfillUUIDsV1` / `PreMigrationBackup`）
    case uuidBackfill
    /// R4.7 再読スキーマ（`didValidateRereadSchemaV1` / `PreRereadSchemaMigrationBackupV1`）
    case rereadSchemaV1

    var completionKey: String {
        switch self {
        case .uuidBackfill: StoreBackupManager.didBackfillUUIDsKey
        case .rereadSchemaV1: StoreBackupManager.didValidateRereadSchemaV1Key
        }
    }

    var directoryName: String {
        switch self {
        case .uuidBackfill: StoreBackupManager.backupDirectoryName
        case .rereadSchemaV1: StoreBackupManager.rereadSchemaBackupDirectoryName
        }
    }
}

enum StoreBackupManager {

    // MARK: - Constants

    /// R3マイグレーション（UUIDバックフィル）の完了フラグのUserDefaultsキー。
    /// フラグを立てる処理はR3ステップ2（バックフィル＋整合性検証）で実装される。ここでは参照のみ。
    nonisolated static let didBackfillUUIDsKey = "didBackfillUUIDsV1"

    /// R4.7 再読スキーマ検証の完了フラグ。R3のキーとは分離する。
    nonisolated static let didValidateRereadSchemaV1Key = "didValidateRereadSchemaV1"

    /// バックアップフォルダ名（ストアと同じディレクトリ内に作成）
    nonisolated static let backupDirectoryName = "PreMigrationBackup"

    /// R4.7専用のバックアップフォルダ名
    nonisolated static let rereadSchemaBackupDirectoryName = "PreRereadSchemaMigrationBackupV1"

    /// 空き容量の安全マージン（必要サイズ×1.2を要求）
    nonisolated static let freeSpaceMargin: Double = 1.2

    private nonisolated static var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "BookBank", category: "StoreBackup")
    }

    // MARK: - Decision (pure)

    /// バックアップ実行判定の結果
    enum BackupDecision: Equatable {
        /// バックアップを実行する
        case backup
        /// R3移行が完了済みのためスキップ
        case skipMigrationCompleted
        /// 既存バックアップを保持するためスキップ（移行前の無傷のスナップショットを上書きしない）
        case skipBackupExists
        /// 空き容量不足のためスキップ（前提10）
        case skipInsufficientSpace
    }

    /// バックアップを取るべきかの純関数判定（ユニットテスト対象）
    nonisolated static func backupDecision(
        migrationCompleted: Bool,
        backupExists: Bool,
        freeSpace: Int64,
        requiredSpace: Int64
    ) -> BackupDecision {
        if migrationCompleted { return .skipMigrationCompleted }
        if backupExists { return .skipBackupExists }
        if Double(freeSpace) < Double(requiredSpace) * freeSpaceMargin { return .skipInsufficientSpace }
        return .backup
    }

    // MARK: - Public API

    /// 移行前バックアップ（必要な場合のみ）。ModelContainer 生成前に呼ぶこと。
    /// `kind` の既定は R3。R4.7 は `.rereadSchemaV1` を渡す。
    nonisolated static func backupIfNeeded(
        storeURL: URL,
        defaults: UserDefaults = .standard,
        kind: StoreBackupKind = .uuidBackfill
    ) {
        // 新規ユーザー（ストア未作成）はバックアップ対象なし
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let decision = backupDecision(
            migrationCompleted: defaults.bool(forKey: kind.completionKey),
            backupExists: backupExists(storeURL: storeURL, kind: kind),
            freeSpace: availableCapacity(at: storeURL),
            requiredSpace: requiredSpaceForBackup(storeURL: storeURL)
        )

        switch decision {
        case .backup:
            do {
                try performBackup(storeURL: storeURL, kind: kind)
                logger.notice("移行前バックアップを作成しました (\(kind.directoryName, privacy: .public))")
            } catch {
                // バックアップ失敗は起動を妨げない（追加の防御層のため）
                logger.error("移行前バックアップの作成に失敗: \(error.localizedDescription)")
            }
        case .skipMigrationCompleted:
            break
        case .skipBackupExists:
            logger.info("既存の移行前バックアップを保持します（上書きしない）")
        case .skipInsufficientSpace:
            logger.error("空き容量不足のため移行前バックアップをスキップしました")
        }
    }

    /// バックアップが存在するか
    nonisolated static func backupExists(
        storeURL: URL,
        kind: StoreBackupKind = .uuidBackfill
    ) -> Bool {
        FileManager.default.fileExists(atPath: backupDirectoryURL(for: storeURL, kind: kind).path)
    }

    /// ストアファイル一式をバックアップフォルダへコピーする。
    /// 途中失敗が「完全なバックアップ」と誤認されないよう、一時フォルダへコピー後にリネームで確定する。
    /// 既存バックアップがある場合は何もしない（上書きしない）。
    nonisolated static func performBackup(
        storeURL: URL,
        kind: StoreBackupKind = .uuidBackfill
    ) throws {
        let fm = FileManager.default
        let backupDir = backupDirectoryURL(for: storeURL, kind: kind)
        guard !fm.fileExists(atPath: backupDir.path) else { return }

        let tempDir = backupDir.appendingPathExtension("tmp")
        if fm.fileExists(atPath: tempDir.path) {
            // 前回の中断残骸を除去
            try fm.removeItem(at: tempDir)
        }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for item in storeFileItems(for: storeURL) where fm.fileExists(atPath: item.path) {
            try fm.copyItem(at: item, to: tempDir.appendingPathComponent(item.lastPathComponent))
        }
        // リネームで確定（部分コピーがバックアップ扱いされない）
        try fm.moveItem(at: tempDir, to: backupDir)
        excludeFromICloudBackup(backupDir)
    }

    /// バックアップからストア一式を復元する。
    /// 現行のストアファイル（壊れている前提）は除去してから書き戻す。
    /// - Returns: 復元を実施したら true（バックアップが存在しなければ false）
    @discardableResult
    nonisolated static func restoreBackup(
        storeURL: URL,
        kind: StoreBackupKind = .uuidBackfill
    ) throws -> Bool {
        let fm = FileManager.default
        let backupDir = backupDirectoryURL(for: storeURL, kind: kind)
        guard fm.fileExists(atPath: backupDir.path) else { return false }

        // 壊れた現行DBファイルのみを除去（バックアップに無い古いWAL等が復元後のストアと混ざらないように）。
        // externalStorage（書影）は storeFileItems に含まれないため削除されず、そのまま据え置かれる。
        for item in storeFileItems(for: storeURL) where fm.fileExists(atPath: item.path) {
            try fm.removeItem(at: item)
        }
        let storeDirectory = storeURL.deletingLastPathComponent()
        for backedUp in try fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: backedUp, to: storeDirectory.appendingPathComponent(backedUp.lastPathComponent))
        }
        logger.notice("移行前バックアップからストアを復元しました")
        return true
    }

    /// バックアップを削除する（整合性検証の通過後に呼ぶ。呼び出しはR3ステップ2で実装）
    nonisolated static func deleteBackup(
        storeURL: URL,
        kind: StoreBackupKind = .uuidBackfill
    ) {
        let fm = FileManager.default
        let backupDir = backupDirectoryURL(for: storeURL, kind: kind)
        guard fm.fileExists(atPath: backupDir.path) else { return }
        do {
            try fm.removeItem(at: backupDir)
            logger.notice("移行前バックアップを削除しました")
        } catch {
            logger.error("移行前バックアップの削除に失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - Container Recovery

    /// 生成失敗時の復元順。R4.7を優先し、無い／失敗したら R3 へ戻す。
    nonisolated static let containerRecoveryKinds: [StoreBackupKind] = [.rereadSchemaV1, .uuidBackfill]

    /// ModelContainer を生成する。失敗時はバックアップから復元して**1回だけ**再試行する（設計メモ4.5節①）。
    ///
    /// 既定では R4.7 バックアップを優先し、存在しない／復元できない場合は R3 バックアップを使う。
    /// 復元は決定的なマイグレーションバグ自体を直せない（同じコードで開けば同じ失敗をする）。
    /// 復元の価値は「修正版が出るまでデータを無傷で保全すること」にあり、
    /// リトライは一時的要因（I/Oエラー等）の救済。2度目の失敗はそのまま throw する。
    nonisolated static func makeContainerWithRecovery(
        schema: Schema,
        configuration: ModelConfiguration,
        storeURL: URL,
        kinds: [StoreBackupKind] = containerRecoveryKinds
    ) throws -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("ModelContainer の生成に失敗: \(error.localizedDescription)")
            guard restoreFirstAvailable(storeURL: storeURL, kinds: kinds) else {
                // バックアップなし・復元自体の失敗は元のエラーで失敗させる
                throw error
            }
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// 単一 kind だけを試す（既存の R3 / R4.7 復元テスト用）。
    nonisolated static func makeContainerWithRecovery(
        schema: Schema,
        configuration: ModelConfiguration,
        storeURL: URL,
        kind: StoreBackupKind
    ) throws -> ModelContainer {
        try makeContainerWithRecovery(
            schema: schema,
            configuration: configuration,
            storeURL: storeURL,
            kinds: [kind]
        )
    }

    /// 先頭から順に復元を試し、最初に成功した kind で止める。
    nonisolated private static func restoreFirstAvailable(
        storeURL: URL,
        kinds: [StoreBackupKind]
    ) -> Bool {
        for kind in kinds {
            do {
                if try restoreBackup(storeURL: storeURL, kind: kind) {
                    return true
                }
            } catch {
                logger.error("\(kind.directoryName) からの復元に失敗: \(error.localizedDescription)")
            }
        }
        return false
    }

    // MARK: - Paths

    /// バックアップフォルダ（ストアと同じディレクトリ内）
    nonisolated static func backupDirectoryURL(
        for storeURL: URL,
        kind: StoreBackupKind = .uuidBackfill
    ) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// バックアップ・復元の対象（DBファイルのみ・存在するもののみ扱う）:
    /// ストア本体・`-shm`・`-wal`。**コピー対象と復元時削除対象で共用する単一の真実源**。
    ///
    /// 書影（`.externalStorage` の外部blob）は意図的に含めない。移行で書き換えられず保護不要であり、
    /// この集合に現れないことで復元時に画像を削除する事故が構造的に起きない（承認事項・決定点①A）。
    nonisolated static func storeFileItems(for storeURL: URL) -> [URL] {
        let directory = storeURL.deletingLastPathComponent()
        let fileName = storeURL.lastPathComponent  // 例: default.store
        return [
            storeURL,
            directory.appendingPathComponent(fileName + "-shm"),
            directory.appendingPathComponent(fileName + "-wal"),
        ]
    }

    // MARK: - Sizes

    /// バックアップに必要なサイズ（DBファイルの合計バイト数）。
    /// 書影を含めないため数MB規模に収まる。
    nonisolated static func requiredSpaceForBackup(storeURL: URL) -> Int64 {
        storeFileItems(for: storeURL).reduce(0) { $0 + itemSize(at: $1) }
    }

    /// ストアのあるボリュームの空き容量。取得不能時は「充足」とみなす
    /// （バックアップ自体を起動障害の原因にしないため。コピー失敗は backupIfNeeded 側で握って続行する）
    nonisolated static func availableCapacity(at storeURL: URL) -> Int64 {
        let values = try? storeURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    /// ファイルまたはフォルダの合計サイズ
    nonisolated static func itemSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Private

    private nonisolated static func excludeFromICloudBackup(_ url: URL) {
        // バックアップの複製でiCloud/iTunesバックアップ容量を倍増させない
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
