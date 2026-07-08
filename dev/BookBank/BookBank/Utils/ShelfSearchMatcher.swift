//
//  ShelfSearchMatcher.swift
//  BookBank
//
//  本棚内検索（所有本のローカル絞り込み）のマッチング純関数。
//  オンライン検索（BookSearchView の SearchPhase・世代管理・ページング）とは
//  完全に別系統であり、状態を一切共有しない。View に依存しないため
//  ユニットテスト対象にできる（docs/bookshelf-search-spec.md 7章）。
//

import Foundation

/// 本棚内検索の正規化・AND部分一致を担う純関数群。
/// - Note: プロジェクト既定のメインアクター分離下でも `map`/`filter` 等の非分離クロージャから
///   安全に呼べるよう、状態を持たない純関数はすべて `nonisolated` を明示する。
enum ShelfSearchMatcher {
    /// 検索・比較用にテキストを正規化する。
    /// - 大文字/小文字・全角/半角・濁点等の diacritic のゆれを吸収（`folding`）
    /// - ひらがな→カタカナへ寄せてかな表記のゆれを吸収（`hiraganaToKatakana`）
    ///   例: 「murakami」「MURAKAMI」「ムラカミ」「むらかみ」「ﾑﾗｶﾐ」が同じ正規形になる。
    /// - 空白を除去し、著者名等のスペース有無のゆれを吸収する
    ///   （例: 「東野圭吾」と「東野 圭吾」を同一視。クエリの語分割は `normalizedTerms` で
    ///   正規化前に済ませているため、AND検索の語区切りには影響しない）。
    nonisolated static func normalize(_ text: String) -> String {
        let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        let folded = katakana.folding(
            options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
            locale: nil
        )
        return folded.filter { !$0.isWhitespace }
    }

    /// 検索クエリを空白（半角・全角）区切りの語に分割し、正規化する（空語は除外）。
    nonisolated static func normalizedTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// 与えたフィールド群に対して、クエリの全語が「いずれかのフィールド」に部分一致するか判定する。
    /// - 複数語は AND（全語が一致必須）、各語はフィールド横断の OR（どれかにマッチすればよい）
    /// - 空クエリ（語なし）は全件一致として true を返す
    /// - Parameters:
    ///   - fields: 検索対象フィールドの値（nil・空文字は無視）
    ///   - query: 生の検索クエリ
    nonisolated static func matches(fields: [String?], query: String) -> Bool {
        let terms = normalizedTerms(from: query)
        guard !terms.isEmpty else { return true }

        let normalizedFields = fields
            .compactMap { $0 }
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedFields.isEmpty else { return false }

        return terms.allSatisfy { term in
            normalizedFields.contains { $0.contains(term) }
        }
    }
}
