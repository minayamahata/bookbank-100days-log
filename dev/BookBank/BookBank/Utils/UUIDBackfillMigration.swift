import Foundation
import OSLog
import SwiftData

/// R3移行（UUID導入）ステップ2: 既存データへの一意なUUIDバックフィル
/// 設計メモ: docs/r3-uuid-migration-notes.md 4.3・4.5節②(a)(b)
///
/// 軽量マイグレーションで追加した `uuid` は、デフォルト式では既存行の一意性を保証できない
/// （全行が同一文字列/空文字で埋まる既知の落とし穴・設計メモ 4.2）。
/// このマイグレーションが「空・重複」の行を検出して採番し直し、全行の一意性を保証する。
///
/// `CurrencyMigration` の弱点（try? save 後に無条件でフラグを立てる）を踏襲せず、
/// save成功＋整合性検証(a)(b)通過時のみ完了フラグを立てる。失敗時は rollback し次回起動で再試行する。
enum UUIDBackfillMigration {

    /// 完了フラグのキー。StoreBackupManager（ステップ1）と同一キーを参照する
    /// （このフラグが立つと移行前バックアップの再取得も止まる）。
    private static let didBackfillKey = StoreBackupManager.didBackfillUUIDsKey

    /// バックフィルが完了しているか（バックアップ削除の配線判定に使う）
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: didBackfillKey)
    }

    private static var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "BookBank", category: "UUIDBackfill")
    }

    // MARK: - Pure Logic (unit-tested)

    /// uuid配列を受け取り、採番し直すべきインデックスを返す（純関数・設計メモ 4.2/4.3）。
    /// - 空文字 → 採番対象
    /// - 重複 → 2件目以降を採番対象（初出は保持）
    ///
    /// これにより「全行が同一値で埋まった」ケースでも1件目以外がすべて採番し直され、全行が一意になる。
    nonisolated static func indicesNeedingReassignment(currentUUIDs: [String]) -> IndexSet {
        var result = IndexSet()
        var seen = Set<String>()
        for (index, uuid) in currentUUIDs.enumerated() {
            if uuid.isEmpty || seen.contains(uuid) {
                result.insert(index)
            } else {
                seen.insert(uuid)
            }
        }
        return result
    }

    /// 検証(a): モデルごとの件数がマイグレーション前後で一致するか（レコードを増減させない・設計メモ 4.5節②a）。
    nonisolated static func countsMatch(before: [String: Int], after: [String: Int]) -> Bool {
        before == after
    }

    /// 検証(b): 全行のuuidが非空かつモデル内で一意か（設計メモ 4.5節②b）。
    nonisolated static func uuidsAreFulfilled(_ uuids: [String]) -> Bool {
        if uuids.contains(where: { $0.isEmpty }) { return false }
        return Set(uuids).count == uuids.count
    }

    // MARK: - Migration

    /// 既存データに一意なUUIDをバックフィルする（未完了時のみ・一度だけ）。
    /// バックフィルは `uuid` フィールドのみに書き込み、他のフィールド（updatedAt含む）には一切触れない。
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didBackfillKey) else { return }

        let passbooks = (try? context.fetch(FetchDescriptor<Passbook>())) ?? []
        let userBooks = (try? context.fetch(FetchDescriptor<UserBook>())) ?? []
        let readingLists = (try? context.fetch(FetchDescriptor<ReadingList>())) ?? []
        let monthlyMemos = (try? context.fetch(FetchDescriptor<MonthlyMemo>())) ?? []

        let countsBefore: [String: Int] = [
            "Passbook": passbooks.count,
            "UserBook": userBooks.count,
            "ReadingList": readingLists.count,
            "MonthlyMemo": monthlyMemos.count,
        ]

        var changed = false
        changed = reassign(passbooks, get: { $0.uuid }, set: { $0.uuid = $1 }) || changed
        changed = reassign(userBooks, get: { $0.uuid }, set: { $0.uuid = $1 }) || changed
        changed = reassign(readingLists, get: { $0.uuid }, set: { $0.uuid = $1 }) || changed
        changed = reassign(monthlyMemos, get: { $0.uuid }, set: { $0.uuid = $1 }) || changed

        if changed {
            do {
                try context.save()
            } catch {
                logger.error("UUIDバックフィルの保存に失敗: \(error.localizedDescription)。rollbackして次回起動で再試行します")
                context.rollback()
                return
            }
        }

        // 整合性検証(a)(b)。save後の永続状態を再fetchして検証し、通過時のみフラグを立てる（設計メモ 4.5節②）
        let verifiedPassbooks = (try? context.fetch(FetchDescriptor<Passbook>())) ?? []
        let verifiedUserBooks = (try? context.fetch(FetchDescriptor<UserBook>())) ?? []
        let verifiedReadingLists = (try? context.fetch(FetchDescriptor<ReadingList>())) ?? []
        let verifiedMonthlyMemos = (try? context.fetch(FetchDescriptor<MonthlyMemo>())) ?? []

        let countsAfter: [String: Int] = [
            "Passbook": verifiedPassbooks.count,
            "UserBook": verifiedUserBooks.count,
            "ReadingList": verifiedReadingLists.count,
            "MonthlyMemo": verifiedMonthlyMemos.count,
        ]
        guard countsMatch(before: countsBefore, after: countsAfter) else {
            logger.error("UUIDバックフィルの検証(a)件数一致に失敗。フラグを立てず次回起動で再試行します")
            return
        }
        guard uuidsAreFulfilled(verifiedPassbooks.map(\.uuid)),
              uuidsAreFulfilled(verifiedUserBooks.map(\.uuid)),
              uuidsAreFulfilled(verifiedReadingLists.map(\.uuid)),
              uuidsAreFulfilled(verifiedMonthlyMemos.map(\.uuid)) else {
            logger.error("UUIDバックフィルの検証(b)uuid充足に失敗。フラグを立てず次回起動で再試行します")
            return
        }

        UserDefaults.standard.set(true, forKey: didBackfillKey)
        logger.notice("UUIDバックフィルが完了しました")
    }

    /// 空・重複の行にのみ新しいUUIDを採番する。uuid以外のフィールドには触れない。
    /// - Returns: 1件以上採番したら true
    @MainActor
    private static func reassign<T>(
        _ items: [T],
        get: (T) -> String,
        set: (T, String) -> Void
    ) -> Bool {
        let indices = indicesNeedingReassignment(currentUUIDs: items.map(get))
        for index in indices {
            set(items[index], UUID().uuidString)
        }
        return !indices.isEmpty
    }
}
