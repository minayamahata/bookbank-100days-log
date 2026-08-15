//
//  PassbookShelfSearchView.swift
//  BookBank
//
//  通帳ページの右上ツールバーから開く本棚内検索（R4.6・2026-08-13）。
//  本棚と同じインライン切替で、検索中は通帳ページの上にこのビューを重ねる
//  （シート提示にしないのは入口と見え方を本棚と揃えるため・2026-08-14 オーナー確定）。
//
//  検索UI本体は本棚タブと共通の `ShelfSearchView`。ここでは
//  検索対象のスコープ（総合=全冊・カスタム=その口座の本）と、
//  本棚と同じ背景・基準色の解決だけを担う。
//  本・つながり・登録の選択時はコールバックを呼ぶだけにして、
//  遷移（NavigationStackへのpush・タブ切替）は MainTabView 側が行う。
//

import SwiftUI

struct PassbookShelfSearchView: View {

    /// 検索対象の口座（nil = 総合口座＝全冊）
    let passbook: PassbookDTO?

    /// テーマ色・登録先の解決に使うカスタム口座一覧（呼び出し側が保持済み）
    let customPassbooks: [PassbookDTO]

    let onSelectBook: (BookDTO) -> Void
    let onSelectLink: (MemoLinkSelection) -> Void
    /// 検索0件の登録導線。登録先の口座（カスタム口座ならその口座、総合なら先頭のカスタム口座）を返す
    let onRegisterBook: (PassbookDTO) -> Void

    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRepositories.self) private var repos

    /// すべての書籍（リポジトリストリーム）。初回yield前は同期スナップショットで補う
    @State private var loadedBooks: [BookDTO]?
    private var allBooks: [BookDTO] { loadedBooks ?? repos.books.latestSnapshot }

    /// 検索対象（総合口座なら全冊、カスタム口座ならその口座の本だけ・2026-08-13 オーナー確定）
    private var scopedBooks: [BookDTO] {
        guard let passbook else { return allBooks }
        return allBooks.filter { $0.passbookId == passbook.id }
    }

    private var isOverallAccount: Bool { passbook == nil }

    private var themeColor: Color {
        if let passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return PassbookColor.overallAccentColor
    }

    private var isBlackTheme: Bool {
        guard let passbook else { return false }
        return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
    }

    /// 文字・チップの基準色（本棚の `bookshelfControlColor` と同じ判定）
    private var controlColor: Color {
        if isOverallAccount && colorScheme == .light { return .primary }
        return .white
    }

    /// 本を登録する対象口座（総合口座のときは先頭のカスタム口座。本棚と同じ規則）
    private var registrationPassbook: PassbookDTO? {
        passbook ?? customPassbooks.first
    }

    var body: some View {
        let _ = languageManager.currentLanguage

        ScrollView {
            ShelfSearchView(
                books: scopedBooks,
                linkIndex: MemoLinkIndex.build(from: scopedBooks),
                controlColor: controlColor,
                onSelectBook: onSelectBook,
                onSelectLink: onSelectLink,
                onRegisterBook: registrationPassbook.map { target in
                    { onRegisterBook(target) }
                }
            ) {
                // つながり解除チップは本棚タブの絞り込み状態のUIなので、通帳側には出さない
                EmptyView()
            } emptyFallback: {
                // 入力前に0冊（カスタム口座に本が無い場合など）: 本棚と同じ登録プロンプト
                Text("bookshelf.register_prompt")
                    .font(.body)
                    .foregroundColor(controlColor)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        // スクロールでキーボードを閉じる（本棚の検索と同じ挙動）
        .scrollDismissesKeyboard(.immediately)
        .background {
            if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            for await value in repos.books.observeBooks() {
                loadedBooks = value
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PassbookShelfSearchView(
        passbook: PreviewSupport.passbook(named: "漫画"),
        customPassbooks: [],
        onSelectBook: { _ in },
        onSelectLink: { _ in },
        onRegisterBook: { _ in }
    )
    .bookBankPreviewEnvironment()
}
