import Foundation
import OSLog
import SwiftData

/// R4.7 再読スキーマの読み取り検証と完了キー。
/// 設計書 `docs/reread-history-spec.md` 12.1節。
enum RereadSchemaValidation {

    private static var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "BookBank", category: "RereadSchema")
    }

    /// 全 `UserBook` と `rereads` を読めるか。空の id は不正とする。
    static func validateAllUserBooks(_ books: [UserBook]) -> Bool {
        for book in books {
            if book.uuid.isEmpty { return false }
            if let rereads = book.rereads {
                for record in rereads where record.id.isEmpty {
                    return false
                }
            }
        }
        return true
    }

    /// R3 と読了リスト移行のあと、検証成功時だけ完了キーを立てて R4.7 バックアップを削除する。
    /// 失敗時はキーもバックアップも残す。
    @MainActor
    static func finalizeIfValid(
        context: ModelContext,
        storeURL: URL,
        defaults: UserDefaults = .standard,
        r3Completed: Bool = UUIDBackfillMigration.hasCompleted,
        readingListCompleted: Bool = ReadingListOrderMigration.hasCompleted
    ) {
        guard r3Completed, readingListCompleted else { return }
        do {
            let books = try context.fetch(FetchDescriptor<UserBook>())
            guard validateAllUserBooks(books) else {
                logger.error("再読スキーマ検証に失敗したため完了キーとバックアップを残します")
                return
            }
            defaults.set(true, forKey: StoreBackupManager.didValidateRereadSchemaV1Key)
            StoreBackupManager.deleteBackup(storeURL: storeURL, kind: .rereadSchemaV1)
        } catch {
            logger.error("再読スキーマ検証の fetch に失敗: \(error.localizedDescription)")
        }
    }
}
