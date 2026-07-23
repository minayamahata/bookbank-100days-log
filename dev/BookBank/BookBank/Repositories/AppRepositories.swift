import Foundation
import SwiftData

/// リポジトリ4つを束ねて `.environment` 注入する（設計メモ 前提9）
@Observable
@MainActor
final class AppRepositories {
    let passbooks: SwiftDataPassbookRepository
    let books: SwiftDataBookRepository
    let readingLists: SwiftDataReadingListRepository
    let monthlyMemos: SwiftDataMonthlyMemoRepository

    init(
        passbooks: SwiftDataPassbookRepository,
        books: SwiftDataBookRepository,
        readingLists: SwiftDataReadingListRepository,
        monthlyMemos: SwiftDataMonthlyMemoRepository
    ) {
        self.passbooks = passbooks
        self.books = books
        self.readingLists = readingLists
        self.monthlyMemos = monthlyMemos
    }

    /// 本番・プレビュー共通: SwiftData実装＋共有チェンジパルス
    convenience init(container: ModelContainer) {
        let pulse = RepositoryChangePulse()
        let context = container.mainContext
        self.init(
            passbooks: SwiftDataPassbookRepository(context: context, pulse: pulse),
            books: SwiftDataBookRepository(context: context, pulse: pulse),
            readingLists: SwiftDataReadingListRepository(context: context, pulse: pulse),
            monthlyMemos: SwiftDataMonthlyMemoRepository(context: context, pulse: pulse)
        )
    }
}
