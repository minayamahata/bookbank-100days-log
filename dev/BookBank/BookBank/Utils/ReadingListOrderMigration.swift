import Foundation
import OSLog
import SwiftData

/// R3移行（UUID導入）ステップ3: 読了リストの並び順を stableID配列 → UUID配列（bookIds）へ変換
/// 設計メモ: docs/r3-uuid-migration-notes.md 5.3・4.5節②(c)
///
/// 変換は「旧 orderedBooks の解決順（stableID照合）を、そのまま各本の uuid 列に転記するだけ」。
/// 独自ソートや不整合の"修正"は一切加えず、旧ロジックの現在の振る舞いをそのまま踏襲する。
/// 前提: UUIDバックフィル（ステップ2）が完了済みであること（実行順で保証）。
enum ReadingListOrderMigration {

    /// 完了フラグのキー
    private static let didMigrateKey = "didMigrateBookOrderToUUIDV1"

    /// 移行が完了しているか（バックアップ削除の配線判定に使う）
    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: didMigrateKey)
    }

    private static var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "BookBank", category: "ReadingListOrder")
    }

    // MARK: - Legacy helpers（旧ロジックを変換のためだけにここへ移設）

    /// 旧 stableID の生成式（旧 ReadingList.stableID(for:) と同一。変換時に一度だけ使う）
    nonisolated static func legacyStableID(title: String, createdAt: Date) -> String {
        "\(title)_\(createdAt.timeIntervalSince1970)"
    }

    /// 旧 bookOrderData（stableID配列のJSON）をデコードする
    nonisolated static func decodeLegacyOrderIDs(_ bookOrderData: String?) -> [String] {
        guard let data = bookOrderData?.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    // MARK: - Pure Logic (unit-tested)

    /// 旧 orderedBooks の解決順を純粋に再現し、並び順どおりの uuid 列を返す（設計メモ 5.3）。
    /// - orderIDs が空 → books の自然順（現行 orderedBooks と同一）
    /// - stableID照合で並べ、記載のない本は末尾に追記
    /// - stableID衝突時は旧 Dictionary(uniquingKeysWith:{first}) と同じく先勝ちで、旧挙動を忠実に踏襲する
    nonisolated static func resolveLegacyOrder(
        orderIDs: [String],
        books: [(stableID: String, uuid: String)]
    ) -> [String] {
        guard !orderIDs.isEmpty else { return books.map(\.uuid) }
        var stableIDToUUID: [String: String] = [:]
        for book in books where stableIDToUUID[book.stableID] == nil {
            stableIDToUUID[book.stableID] = book.uuid
        }
        var ordered: [String] = []
        var usedStableIDs = Set<String>()
        for id in orderIDs {
            if let uuid = stableIDToUUID[id] {
                ordered.append(uuid)
                usedStableIDs.insert(id)
            }
        }
        for book in books where !usedStableIDs.contains(book.stableID) {
            ordered.append(book.uuid)
        }
        return ordered
    }

    /// 新 orderedBooks の解決順を純粋に再現し、並び順どおりの uuid 列を返す。
    /// モデルの orderedBooks（uuid照合＋未記載は末尾）と同一ロジック。
    nonisolated static func resolveUUIDOrder(bookIds: [String], bookUUIDs: [String]) -> [String] {
        guard !bookIds.isEmpty else { return bookUUIDs }
        let available = Set(bookUUIDs)
        var ordered: [String] = []
        var used = Set<String>()
        for id in bookIds where available.contains(id) {
            ordered.append(id)
            used.insert(id)
        }
        for uuid in bookUUIDs where !used.contains(uuid) {
            ordered.append(uuid)
        }
        return ordered
    }

    /// 検証(c): 変換前後の並び順の完全一致（順序ずれ・欠落・重複を検出）。
    /// 配列の == は要素・順序・個数すべてを比較するため、いずれのズレも false になる。
    nonisolated static func ordersMatch(before: [String], after: [String]) -> Bool {
        before == after
    }

    // MARK: - Migration

    /// 読了リストの並び順を bookIds（uuid配列）へ変換する（未完了時のみ・一度だけ）。
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        guard !hasCompleted else { return }

        let lists = (try? context.fetch(FetchDescriptor<ReadingList>())) ?? []

        // 変換前の legacySeq をリストごとに控える（検証(c)で使う）
        var legacyByList: [PersistentIdentifier: [String]] = [:]
        var changed = false
        for list in lists {
            // 既に bookIds が非空（saveBookOrder 新ロジックが先に走った等）は二重変換を避けてスキップ（設計メモ 5.3）
            guard list.bookIds.isEmpty else { continue }

            let orderIDs = decodeLegacyOrderIDs(list.bookOrderData)
            let books = list.books.map {
                (stableID: legacyStableID(title: $0.title, createdAt: $0.createdAt), uuid: $0.uuid)
            }
            let legacySeq = resolveLegacyOrder(orderIDs: orderIDs, books: books)
            list.bookIds = legacySeq
            legacyByList[list.persistentModelID] = legacySeq
            if !legacySeq.isEmpty { changed = true }
        }

        if changed {
            do {
                try context.save()
            } catch {
                logger.error("読了リスト並び順変換の保存に失敗: \(error.localizedDescription)。rollbackして次回起動で再試行します")
                context.rollback()
                return
            }
        }

        // 検証(c): save後の永続状態を再fetchし、変換前後の完全一致を確認（設計メモ 4.5節②c）
        let verifiedLists = (try? context.fetch(FetchDescriptor<ReadingList>())) ?? []
        for list in verifiedLists {
            guard let legacySeq = legacyByList[list.persistentModelID] else { continue }
            let restored = resolveUUIDOrder(bookIds: list.bookIds, bookUUIDs: legacySeq)
            guard ordersMatch(before: legacySeq, after: restored) else {
                logger.error("読了リスト並び順変換の検証(c)に失敗: list.uuid=\(list.uuid)。フラグを立てず次回起動で再試行します")
                return
            }
        }

        UserDefaults.standard.set(true, forKey: didMigrateKey)
        logger.notice("読了リストの並び順変換が完了しました")
    }
}
