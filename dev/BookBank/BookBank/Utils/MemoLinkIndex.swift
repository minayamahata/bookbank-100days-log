//
//  MemoLinkIndex.swift
//  BookBank
//
//  全書籍のメモをパースして作るつながりの集計（docs/memo-tagging-design.md 3.3節）。
//  つながりは永続化しないため、サジェストと絞り込みはこの都度構築のインデックスから導く。
//  スキーマを持たないぶん「メモを直せばつながりが変わる」という単純さが保たれる。
//

import Foundation

struct MemoLinkIndex: Equatable, Sendable {
    struct Link: Equatable, Hashable, Sendable {
        /// 一致判定に使う正規化キー
        let key: String
        /// 表示・挿入に使うラベル。同じキーに複数の書き方があれば最も多く書かれたもの
        let display: String
        /// このつながりを持つ本の数
        let bookCount: Int
    }

    /// 使う本の多い順、同数なら綴り順。サジェストの表示順にそのまま使える
    let links: [Link]

    static let empty = MemoLinkIndex(links: [])

    static func build(from books: [BookDTO]) -> MemoLinkIndex {
        var bookIdsByKey: [String: Set<String>] = [:]
        var spellingsByKey: [String: [String: Int]] = [:]

        for book in books {
            guard let memo = book.memo, !memo.isEmpty else { continue }
            for link in MemoLinkParser.parse(memo) {
                bookIdsByKey[link.key, default: []].insert(book.id)
                spellingsByKey[link.key, default: [:]][link.display, default: 0] += 1
            }
        }

        var links: [Link] = []
        for (key, bookIds) in bookIdsByKey {
            let display = representativeSpelling(in: spellingsByKey[key] ?? [:]) ?? key
            links.append(Link(key: key, display: display, bookCount: bookIds.count))
        }
        links.sort { lhs, rhs in
            lhs.bookCount == rhs.bookCount ? lhs.key < rhs.key : lhs.bookCount > rhs.bookCount
        }

        return MemoLinkIndex(links: links)
    }

    /// 入力中の断片に前方一致するつながりを、既にメモに書かれているものを除いて返す
    func suggestions(matching partialKey: String, excluding usedKeys: Set<String>) -> [Link] {
        links.filter { !usedKeys.contains($0.key) && $0.key.hasPrefix(partialKey) }
    }

    /// 最も多く書かれた綴り。同数なら辞書順の小さいほうを選び、結果が入力順に依存しないようにする
    private static func representativeSpelling(in spellings: [String: Int]) -> String? {
        spellings.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
