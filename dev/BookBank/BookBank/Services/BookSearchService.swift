//
//  BookSearchService.swift
//  BookBank
//
//  設定「検索データベース」に応じて楽天／NAVERを切り替える検索コーディネーター
//

import Foundation

/// 書籍検索に使用するデータベース設定（@AppStorage("searchDatabase") に保存）
enum SearchDatabase: String, CaseIterable, Identifiable {
    case auto       // 端末の言語設定に連動
    case rakuten    // 日本の本（楽天Books固定）
    case naver      // 한국 도서（NAVER固定）

    var id: String { rawValue }

    /// @AppStorage / UserDefaults の保存キー
    static let storageKey = "searchDatabase"

    /// 設定画面の表示名キー（String Catalog）
    var nameKey: String {
        switch self {
        case .auto: return "search_database.auto"
        case .rakuten: return "search_database.rakuten"
        case .naver: return "search_database.naver"
        }
    }

    /// 実際に使用する検索プロバイダ（auto は実効言語に連動：ko → NAVER、その他 → 楽天）
    var resolvedProvider: SearchProvider {
        switch self {
        case .rakuten: return .rakuten
        case .naver: return .naver
        case .auto: return AppLanguage.effective == .korean ? .naver : .rakuten
        }
    }

    /// 設定画面の補足表示（実際に使われる提供元ブランド名）
    var displayProviderName: String {
        switch resolvedProvider {
        case .rakuten: return "楽天ブックス"
        case .naver: return "NAVER"
        }
    }

    /// 現在の設定（未設定時は auto）
    static var current: SearchDatabase {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return SearchDatabase(rawValue: raw ?? "") ?? .auto
    }
}

/// 実際に検索を行うプロバイダ
enum SearchProvider {
    case rakuten
    case naver
}

/// 検索データベース設定に応じてAPIを振り分ける検索サービス
@MainActor
final class BookSearchService {
    private let rakuten = RakutenBooksService()
    private let naver = NaverBooksService()

    /// キーワード検索（設定に応じて楽天／NAVERを切り替え）
    func search(_ keyword: String, page: Int = 1) async throws -> [RakutenBook] {
        switch SearchDatabase.current.resolvedProvider {
        case .rakuten: return try await rakuten.search(keyword, page: page)
        case .naver: return try await naver.search(keyword, page: page)
        }
    }

    /// ISBN検索（設定に応じて楽天／NAVERを切り替え）
    func searchByISBN(_ isbn: String) async throws -> [RakutenBook] {
        switch SearchDatabase.current.resolvedProvider {
        case .rakuten: return try await rakuten.searchByISBN(isbn)
        case .naver: return try await naver.searchByISBN(isbn)
        }
    }
}
