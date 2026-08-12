//
//  MemoLinkIndex.swift
//  BookBank
//
//  全書籍のメモをパースして作るつながりの集計（docs/memo-tagging-design.md 3.3節）。
//  つながりは永続化しないため、本棚の絞り込み（ステップ8'）はこの都度構築の
//  インデックスから導く。スキーマを持たないぶん「メモを直せばつながりが変わる」
//  という単純さが保たれる。
//

import Foundation

/// 本棚で選択中のつながり（絞り込み状態・ステップ8'）。
/// 判定は `key`、チップの表示は `display` を使う。口座切替をまたいで維持するため
/// `BookshelfChromeState` に載せる（2026-08-12 オーナー確定）
struct MemoLinkSelection: Equatable, Sendable {
    let key: String
    let display: String
}

struct MemoLinkIndex: Equatable, Sendable {
    struct Link: Equatable, Hashable, Sendable {
        /// 一致判定に使う正規化キー
        let key: String
        /// 表示に使うラベル。同じキーに複数の書き方があれば最も多く書かれたもの
        let display: String
        /// このつながりを持つ本の数
        let bookCount: Int
    }

    /// 使う本の多い順、同数なら綴り順。絞り込みのチップの並びにそのまま使える
    let links: [Link]

    /// つながり → そのつながりを持つ本のID。絞り込み（既存フィルターとのAND合成）用
    private let bookIdsByKey: [String: Set<String>]

    static let empty = MemoLinkIndex(links: [], bookIdsByKey: [:])

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

        return MemoLinkIndex(links: links, bookIdsByKey: bookIdsByKey)
    }

    /// このつながりを持つ本のID。キーが存在しなければ空
    func bookIds(for key: String) -> Set<String> {
        bookIdsByKey[key] ?? []
    }

    /// 検索語に一致するつながり（並びは `links` のまま＝多い順）。
    ///
    /// 判定は**部分一致・本棚内検索と同じ正規化**（`ShelfSearchMatcher`＝かな寄せ・全半角・
    /// 大小文字・濁点・空白区切りAND。2026-08-12 オーナー確定）。これは「見つけるための一致」
    /// であり、つながりの同一性（NFKC・かな寄せなし＝前提4）には触れない。
    /// `[[きょうと]]` と `[[キョウト]]` は別々のつながりのまま、どちらも「きょうと」で見つかる。
    /// 代表綴り（`display`）だけを照合すれば足りる——同じキーの別綴りとの差は大小文字・全半角
    /// 程度で、`ShelfSearchMatcher` の folding が吸収する範囲に収まるため。
    /// 空クエリは全件を返す（検索の入力前に出す一覧に使う）
    func links(matching query: String) -> [Link] {
        links.filter { ShelfSearchMatcher.matches(fields: [$0.display], query: query) }
    }

    /// 最も多く書かれた綴り。同数なら辞書順の小さいほうを選び、結果が入力順に依存しないようにする
    private static func representativeSpelling(in spellings: [String: Int]) -> String? {
        spellings.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
