import Foundation

/// 読了リストのView向けDTO（設計メモ 3.3節・前提5・前提6）
///
/// `Hashable` は `NavigationLink(value:)` / `navigationDestination(for:)` に載せるための適合。
/// 遷移先は `id` でストリームから解決し直すため、押下時のスナップショットは初期値としてのみ使う。
struct ReadingListDTO: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String?
    var colorIndex: Int?
    var bookIds: [String]
    /// 並び順解決済みの本（`orderedBooks` 相当）
    var books: [BookDTO]
    var createdAt: Date
    var updatedAt: Date
    /// 共有URL同一性のための `persistentModelID` 文字列（前提6）
    var legacyShareId: String
}

extension ReadingListDTO {
    /// 所属本を差し替えた新しい値を返す（リストCRUDの唯一の書き込み口＝設計メモ 3.1節）。
    ///
    /// `bookIds` が並び順の正であり、`books` はその解決結果。両者を必ず一緒に動かすことで、
    /// View 側で「順序だけ書いて所属を書き忘れる」類の取りこぼしが起きないようにする。
    /// 永続化された `books` はリポジトリが `bookIds` から再解決するため、ここでの `books`
    /// はストリーム到達までの表示用（楽観更新）として使う。
    func replacingBooks(_ books: [BookDTO], updatedAt: Date) -> ReadingListDTO {
        var copy = self
        copy.bookIds = books.map(\.id)
        copy.books = books
        copy.updatedAt = updatedAt
        return copy
    }

    /// 作成フローの確定判定（設計メモ 8.3節-3）。
    ///
    /// 本が1冊も選ばれなければ **リストを作らない**。旧実装は「空リストを作ってから
    /// キャンセル時に delete する」rollback だったが、最終状態（キャンセルでリストが残らない）は同じで、
    /// 選択中にプロセスが落ちても空リストが残らないぶん堅い。
    static func confirmedCreation(
        draft: ReadingListDTO?,
        pickedBooks: [BookDTO],
        now: Date
    ) -> ReadingListDTO? {
        guard let draft, !pickedBooks.isEmpty else { return nil }
        return draft.replacingBooks(pickedBooks, updatedAt: now)
    }
}
