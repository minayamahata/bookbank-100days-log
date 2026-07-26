import Foundation

// - Note: 初回フレームの空表示（設計メモ 5.1節）を埋める `latestSnapshot` は、
//   **意図的にこのプロトコルへ載せていない**（オーナー承認 2026-07-25）。
//   具象 `SwiftData*Repository` にのみ置くことで、R6でFirestore実装へ差し替えた瞬間に
//   参照元のViewがコンパイルエラーになり、解体漏れを機械的に検出できる。
//   前提9の「View層はプロトコルのシグネチャのみに依存する」に対する既知の例外
//   （設計メモ 前提9・4.6節）。

/// リポジトリが検出する保存不能な状態。View はエラーUIを出さないが（4.5節）、
/// **失敗を成功として振る舞わない**ために throw を伝播させる（ステップ4レビュー S4-11）。
enum RepositoryError: Error, Equatable {
    /// `passbookId` が指定されているのに該当する口座が見つからない。
    /// 旧実装（@Model 直参照）は「保存しない」であり、`passbook: nil` で保存すると
    /// 「別の口座（総合）に入る」という悪化した失敗モードになるため throw する
    case passbookNotFound(String)

    /// 更新対象の本が見つからない（2026-07-26 オーナー判断）。
    ///
    /// not-found は「並行削除」を保証しない（uuid不整合など本物の異常でも出る）ため、
    /// リポジトリが log+return で握り潰すと**本物の失敗を成功に見せる**ことになる。
    /// 「並行削除なら閉じてよい」というUX判断は View 側の catch が持つ（4.5節）。
    /// - Note: 削除系（`deleteBook`）の not-found→return は**冪等削除**として据え置く
    case bookNotFound(String)
}

/// 書誌の更新時に表紙をどう扱うか（設計メモ 3.1節への追補・ステップ4レビュー S4-12）。
/// 旧実装は表紙と書誌を1回の `save()` で書いていたため、2トランザクションに割ると
/// 部分永続化（表紙だけ書かれる）が起きる。1回の書き込みへ畳むための指定。
enum CoverImageUpdate: Sendable, Equatable {
    /// 表紙に触れない
    case unchanged
    /// 表紙を差し替える（`nil` は削除）
    case replace(Data?)
}

protocol BookRepository: AnyObject {
    func observeBooks() -> AsyncStream<[BookDTO]>
    func addBook(_ book: BookDTO, coverImageData: Data?) async throws
    /// 書誌と表紙を**1トランザクション**で反映する
    func updateBook(_ book: BookDTO, cover: CoverImageUpdate) async throws
    func deleteBook(id: String) async throws
    func loadCoverImage(bookId: String) async -> Data?
    func updateCoverImage(bookId: String, data: Data?) async throws
}

extension BookRepository {
    /// 表紙に触れない更新（お気に入り・メモ等）
    func updateBook(_ book: BookDTO) async throws {
        try await updateBook(book, cover: .unchanged)
    }
}

protocol PassbookRepository: AnyObject {
    func observePassbooks() -> AsyncStream<[PassbookDTO]>
    func addPassbook(_ passbook: PassbookDTO) async throws
    func updatePassbook(_ passbook: PassbookDTO) async throws
    func deletePassbook(id: String) async throws
}

protocol ReadingListRepository: AnyObject {
    func observeReadingLists() -> AsyncStream<[ReadingListDTO]>
    func addReadingList(_ list: ReadingListDTO) async throws
    func updateReadingList(_ list: ReadingListDTO) async throws
    func deleteReadingList(id: String) async throws
}

/// 月別メモのリポジトリ契約（設計メモ 3.1節）。
/// 旧 `MonthlyMemoRepository` enum はステップ2（2026-07-23）で本プロトコル実装へ置換・廃止済み。
protocol MonthlyMemoRepository: AnyObject {
    func observeMemo(year: Int, month: Int) -> AsyncStream<MonthlyMemoDTO?>
    func saveMemo(year: Int, month: Int, text: String) async throws
}
