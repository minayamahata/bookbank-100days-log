import Foundation

/// 再読の追加先を、既存の同一本判定と確定ソートで選ぶ。
enum RereadTargetResolver {
    /// ISBN があれば ISBN 一致。なければタイトル＋著者の完全一致。
    static func isSameBook(_ book: BookDTO, isbn: String?, title: String, author: String?) -> Bool {
        if let isbn, !isbn.isEmpty {
            return book.isbn == isbn
        }
        return book.title == title && (book.author ?? "") == (author ?? "")
    }

    /// 複数の既存重複があるときは `registeredAt` 昇順 → `createdAt` 昇順 → `id` 昇順の先頭。
    static func resolveTarget(
        among books: [BookDTO],
        isbn: String?,
        title: String,
        author: String?
    ) -> BookDTO? {
        books
            .filter { isSameBook($0, isbn: isbn, title: title, author: author) }
            .sorted { lhs, rhs in
                if lhs.registeredAt != rhs.registeredAt {
                    return lhs.registeredAt < rhs.registeredAt
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
            .first
    }
}
