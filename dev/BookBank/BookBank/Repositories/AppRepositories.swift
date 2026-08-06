import Foundation
import SwiftData

/// リポジトリ4つを束ねて `.environment` 注入する（設計メモ 前提9）
@Observable
@MainActor
final class AppRepositories {
    /// 共有チェンジパルス（リポジトリ外書き込みの再通知にも使う・設計メモ 4.3節）
    private let pulse: RepositoryChangePulse

    let passbooks: SwiftDataPassbookRepository
    let books: SwiftDataBookRepository
    let readingLists: SwiftDataReadingListRepository
    let monthlyMemos: SwiftDataMonthlyMemoRepository

    init(
        passbooks: SwiftDataPassbookRepository,
        books: SwiftDataBookRepository,
        readingLists: SwiftDataReadingListRepository,
        monthlyMemos: SwiftDataMonthlyMemoRepository,
        pulse: RepositoryChangePulse
    ) {
        self.pulse = pulse
        self.passbooks = passbooks
        self.books = books
        self.readingLists = readingLists
        self.monthlyMemos = monthlyMemos
    }

    /// 本番・プレビュー共通: SwiftData実装＋共有チェンジパルス
    convenience init(container: ModelContainer) {
        let pulse = RepositoryChangePulse()
        let context = container.mainContext
        let books = SwiftDataBookRepository(context: context, pulse: pulse)
        self.init(
            passbooks: SwiftDataPassbookRepository(context: context, pulse: pulse, books: books),
            books: books,
            readingLists: SwiftDataReadingListRepository(context: context, pulse: pulse),
            monthlyMemos: SwiftDataMonthlyMemoRepository(context: context, pulse: pulse),
            pulse: pulse
        )
    }

    /// リポジトリを介さない書き込み（前提7のマイグレーション等）の後に呼び、購読中ストリームを再fetchさせる。
    func notifyExternalChange() {
        pulse.notify()
    }
}
