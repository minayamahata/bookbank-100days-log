//
//  BookSearchService.swift
//  BookBank
//
//  設定「検索データベース」に応じて楽天／NAVERを切り替える検索コーディネーター
//

import Foundation

/// 書籍検索に使用するデータベース設定（@AppStorage("searchDatabase") に保存）
enum SearchDatabase: String, CaseIterable, Identifiable {
    case rakuten    // 日本語の本（楽天Books）
    case naver      // 韓国語の本（NAVER）
    case google     // 英語の本（Google Books）

    var id: String { rawValue }

    /// @AppStorage / UserDefaults の保存キー
    static let storageKey = "searchDatabase"

    /// 設定画面の表示名キー（String Catalog）
    var nameKey: String {
        switch self {
        case .rakuten: return "search_database.rakuten"
        case .naver: return "search_database.naver"
        case .google: return "search_database.google"
        }
    }

    /// 実際に使用する検索プロバイダ
    var resolvedProvider: SearchProvider {
        switch self {
        case .rakuten: return .rakuten
        case .naver: return .naver
        case .google: return .google
        }
    }

    /// 設定画面の補足表示（実際に使われる提供元ブランド名）
    var displayProviderName: String {
        switch resolvedProvider {
        case .rakuten: return L10n.string("search.provider.rakuten")
        case .naver: return L10n.string("search.provider.naver")
        case .google: return L10n.string("search.provider.google")
        }
    }

    /// 端末の言語設定から推定した既定のデータベース
    /// （ja → 日本語、ko → 韓国語、その他 → 英語）
    static var deviceDefault: SearchDatabase {
        switch AppLanguage.effective {
        case .japanese: return .rakuten
        case .korean: return .naver
        default: return .google
        }
    }

    /// 現在の設定（未設定・不正値のときは端末言語から推定した既定）
    static var current: SearchDatabase {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return SearchDatabase(rawValue: raw ?? "") ?? deviceDefault
    }
}

/// 実際に検索を行うプロバイダ
enum SearchProvider {
    case rakuten
    case naver
    case google
}

/// キーワード検索の1ページ分の結果（取得した書籍＋APIが返す総ヒット件数）
struct BookSearchPage {
    /// このページで取得した書籍
    let books: [RakutenBook]
    /// 検索にヒットした総件数（APIが返す推定値。取得できない場合は nil）
    let totalCount: Int?
    /// サーバー側にまだ次のページがあるか。
    /// - Note: ローカルの絞り込み後の件数ではなく、API が返す生のページ情報から判定する。
    ///   （絞り込みで 1 ページの件数が減っても、途中でページングが止まらないようにするため）
    let hasMorePages: Bool
}

/// 検索データベース設定に応じてAPIを振り分ける検索サービス
@MainActor
final class BookSearchService {
    private let rakuten = RakutenBooksService()
    private let naver = NaverBooksService()
    private let google = GoogleBooksService()

    /// キーワード検索（設定に応じて楽天／NAVER／Google Booksを切り替え）
    func search(_ keyword: String, page: Int = 1) async throws -> BookSearchPage {
        switch SearchDatabase.current.resolvedProvider {
        case .rakuten: return try await rakuten.search(keyword, page: page)
        case .naver: return try await naver.search(keyword, page: page)
        case .google: return try await google.search(keyword, page: page)
        }
    }

    /// ISBN検索（設定に応じて楽天／NAVER／Google Booksを切り替え）
    func searchByISBN(_ isbn: String) async throws -> [RakutenBook] {
        switch SearchDatabase.current.resolvedProvider {
        case .rakuten: return try await rakuten.searchByISBN(isbn)
        case .naver: return try await naver.searchByISBN(isbn)
        case .google: return try await google.searchByISBN(isbn)
        }
    }

    /// 発行形態（size）を後追いで補完する。
    /// 楽天のみ追加APIが必要で、NAVER／Google は size を返さないためそのまま返す。
    func enrichFormats(for books: [RakutenBook]) async -> [RakutenBook] {
        switch SearchDatabase.current.resolvedProvider {
        case .rakuten: return await rakuten.enrichWithFormat(books)
        case .naver, .google: return books
        }
    }
}
