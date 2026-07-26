import Foundation
import OSLog
import SwiftData

/// DTO の本 id（uuid）から SwiftData の `UserBook` @Model を解決する（R4ステップ4→5のハイブリッド用）。
///
/// ステップ4で本の読み取りは `BookDTO` に切り替わったが、`ReadingList.books`（SwiftDataリレーション）へ
/// 本を追加する経路（`BookSelectorView`）はステップ5まで `@Model` を必要とする。
/// ステップ5で `ReadingListDTO.bookIds` 経由の `updateReadingList` に一本化されたら**参照ゼロになるので削除する**。
///
/// - Note: 失敗時のユーザー向けエラーUIは新設しない（設計メモ 4.5節・前提13）。
///   ただしステップ3レビュー #5 で指摘された「サイレント無保存」を観測可能にするため、
///   **fetch失敗（throw）と該当なし（見つからない）を区別して OSLog に記録**する。
@MainActor
enum BookModelLookup {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BookBank",
        category: "BookModelLookup"
    )

    /// 指定 id 群に対応する `UserBook` を返す。引数の順序を保持し、解決できなかった id は落とす。
    static func fetch(ids: [String], context: ModelContext) -> [UserBook] {
        guard !ids.isEmpty else { return [] }
        let targets = Set(ids)
        do {
            // 全件fetchせず述語で絞る（レビュー S4-19）。返り順はストア順なので入力順へ並べ直す
            let descriptor = FetchDescriptor<UserBook>(
                predicate: #Predicate { targets.contains($0.uuid) }
            )
            let matched = try context.fetch(descriptor)
            let byUUID = Dictionary(
                matched.map { ($0.uuid, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let resolved = ids.compactMap { byUUID[$0] }
            let missing = ids.filter { byUUID[$0] == nil }
            if !missing.isEmpty {
                // 該当なし: fetch自体は成功している（削除済み・uuid不整合が疑わしい）
                logger.error(
                    "BookModelLookup: not found requested=\(ids.count, privacy: .public) missing=\(missing.count, privacy: .public) ids=\(missing.joined(separator: ","), privacy: .public)"
                )
            }
            return resolved
        } catch {
            // fetch失敗: ストア側の異常。該当なしとは原因が異なるため別メッセージで記録する
            logger.error(
                "BookModelLookup: fetch failed requested=\(ids.count, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
