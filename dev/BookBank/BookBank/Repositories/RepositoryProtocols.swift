import Foundation

protocol BookRepository: AnyObject {
    func observeBooks() -> AsyncStream<[BookDTO]>
    func addBook(_ book: BookDTO, coverImageData: Data?) async throws
    func updateBook(_ book: BookDTO) async throws
    func deleteBook(id: String) async throws
    func loadCoverImage(bookId: String) async -> Data?
    func updateCoverImage(bookId: String, data: Data?) async throws
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
/// 既存の `LegacyMonthlyMemoRepository` enum（旧 `MonthlyMemoRepository`）はステップ2で本プロトコル実装へ置換する。
protocol MonthlyMemoRepository: AnyObject {
    func observeMemo(year: Int, month: Int) -> AsyncStream<MonthlyMemoDTO?>
    func saveMemo(year: Int, month: Int, text: String) async throws
}
