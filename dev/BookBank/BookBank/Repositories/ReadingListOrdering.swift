import Foundation

/// `ReadingList.orderedBooks` と同じ並び解決の純関数（設計メモ 3.3節・前提5）。
/// `bookIds` 順に解決し、記載のない本は末尾へ追記。空の `bookIds` は入力順のまま返す。
enum ReadingListOrdering {
    static func resolve<T>(bookIds: [String], books: [T], uuid: (T) -> String) -> [T] {
        guard !bookIds.isEmpty else { return books }
        let uuidToBook = Dictionary(
            books.map { (uuid($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ordered: [T] = []
        var usedUUIDs = Set<String>()
        for id in bookIds {
            if let book = uuidToBook[id] {
                ordered.append(book)
                usedUUIDs.insert(id)
            }
        }
        for book in books {
            let id = uuid(book)
            if !usedUUIDs.contains(id) {
                ordered.append(book)
            }
        }
        return ordered
    }
}
