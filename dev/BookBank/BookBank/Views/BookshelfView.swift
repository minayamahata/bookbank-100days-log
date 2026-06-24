//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI
import SwiftData

/// 本棚画面
struct BookshelfView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nil = 総合口座）
    let passbook: Passbook?

    /// 本棚タブのルートとして表示しているか（カレンダー時の戻るボタン制御を共有状態と同期する）
    let managesCalendarChrome: Bool

    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Environment(BookshelfChromeState.self) private var bookshelfChromeState
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    // MARK: - State
    
    /// お気に入りフィルター
    @State private var showFavoritesOnly: Bool
    
    /// メモありフィルター
    @State private var showWithMemoOnly: Bool
    
    /// カレンダー表示モード
    @State private var showCalendarView: Bool

    /// 月別メモ編集用（総合口座のみ）
    /// 年・月・本文を1つの値で持ち、`.sheet(item:)` で開くことで
    /// 常に正しい月のデータで開き直され、別の月のメモを保存してしまう不具合を防ぐ
    @State private var monthlyMemoTarget: MonthlyMemoTarget?

    /// 月別メモシートの対象
    private struct MonthlyMemoTarget: Identifiable {
        let year: Int
        let month: Int
        let text: String
        var id: String { "\(year)-\(month)" }
    }
    
    /// 口座に紐づく書籍（総合口座の場合は全書籍）
    private var passbookBooks: [UserBook] {
        if let passbook {
            return allUserBooks.filter { book in
                book.passbook?.persistentModelID == passbook.persistentModelID
            }
        }
        return allUserBooks
    }
    
    /// フィルター適用後の書籍
    private var userBooks: [UserBook] {
        var books = passbookBooks
        
        // お気に入りフィルター
        if showFavoritesOnly {
            books = books.filter { $0.isFavorite }
        }
        
        // メモありフィルター
        if showWithMemoOnly {
            books = books.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }
        }
        
        return books
    }
    
    /// カスタム口座のリスト
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// 総合口座かどうか
    private var isOverallAccount: Bool {
        passbook == nil
    }

    /// この口座のテーマカラー
    private var themeColor: Color {
        if let passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return PassbookColor.overallAccentColor
    }

    /// UIアクセントカラー
    private var accentColor: Color {
        isOverallAccount ? PassbookColor.overallAccentColor : themeColor
    }
    
    /// テーマカラーが黒かどうか
    private var isBlackTheme: Bool {
        guard let passbook else { return false }
        return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
    }

    /// 本を登録する対象口座（総合口座のときは先頭のカスタム口座）
    private var registrationPassbook: Passbook? {
        passbook ?? customPassbooks.first
    }

    /// カレンダー右上の＋ボタンの塗り色（通帳シート展開時の＋ボタンと同じ判定）
    private var calendarAddTint: Color {
        if colorScheme == .dark && isBlackTheme { return .white }
        return accentColor
    }

    /// カレンダー右上の＋ボタンの記号色
    private var calendarAddIconColor: Color {
        if colorScheme == .dark && calendarAddTint.luminance > 0.5 { return .black }
        return .white
    }
    
    /// この口座の全書籍数
    private var allBooksCount: Int {
        passbookBooks.count
    }
    
    /// お気に入りの書籍数
    private var favoriteCount: Int {
        passbookBooks.filter(\.isFavorite).count
    }
    
    /// メモありの書籍数
    private var memoCount: Int {
        passbookBooks.filter { book in
            book.memo != nil && !(book.memo?.isEmpty ?? true)
        }.count
    }
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    // MARK: - Initialization
    
    init(passbook: Passbook?, startsWithCalendarView: Bool = false, managesCalendarChrome: Bool = false) {
        self.passbook = passbook
        self.managesCalendarChrome = managesCalendarChrome
        _showFavoritesOnly = State(initialValue: false)
        _showWithMemoOnly = State(initialValue: false)
        _showCalendarView = State(initialValue: startsWithCalendarView)
        _monthlyMemoTarget = State(initialValue: nil)
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        let _ = languageManager.currentLanguage

        Group {
            if showCalendarView {
                // カレンダー：フィルター行・切替ボタンは不要（左上の戻るボタンで本棚へ戻る）
                BookshelfCalendarView(
                    books: passbookBooks,
                    isOverallAccount: isOverallAccount,
                    onMonthlyMemo: { year, month in
                        openMonthlyMemo(year: year, month: month)
                    },
                    header: {
                        EmptyView()
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // フィルターセクション
                        filterSection

                        // 本棚グリッド
                        gridContent
                    }
                }
            }
        }
        .id(passbook?.persistentModelID.hashValue.description ?? "overall")
        .background {
            if showCalendarView && colorScheme == .light {
                // カレンダー表示のライトモードは silver を敷かず白背景にする
                Color.white.ignoresSafeArea()
            } else if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
        }
        .navigationTitle(showCalendarView ? "bookshelf.calendar_title" : "bookshelf.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 通帳ページから開いたカレンダーの右上に、シート展開時と同じ＋ボタンを表示
            if showCalendarView, !managesCalendarChrome, let registrationPassbook {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: BookSearchDestination(passbook: registrationPassbook)) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(calendarAddIconColor)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(calendarAddTint)
                }
            }
        }
        .onAppear {
            if managesCalendarChrome {
                bookshelfChromeState.isCalendar = showCalendarView
            }
        }
        .onDisappear {
            if managesCalendarChrome {
                bookshelfChromeState.isCalendar = false
            }
        }
        .onChange(of: showCalendarView) { _, newValue in
            if managesCalendarChrome {
                bookshelfChromeState.isCalendar = newValue
            }
        }
        .onChange(of: bookshelfChromeState.isCalendar) { _, newValue in
            if managesCalendarChrome, showCalendarView != newValue {
                showCalendarView = newValue
            }
        }
        .sheet(item: $monthlyMemoTarget) { target in
            MemoEditorView(
                memo: .constant(target.text),
                title: "bookshelf.monthly_log"
            ) { newText in
                MonthlyMemoRepository.save(
                    year: target.year,
                    month: target.month,
                    text: newText,
                    context: context
                )
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterPill(
                        label: "common.all",
                        count: allBooksCount,
                        alwaysShowCount: true,
                        isSelected: !showFavoritesOnly && !showWithMemoOnly
                    ) {
                        showFavoritesOnly = false
                        showWithMemoOnly = false
                    }

                    filterPill(
                        label: "bookshelf.favorite",
                        count: favoriteCount,
                        isSelected: showFavoritesOnly
                    ) {
                        showFavoritesOnly.toggle()
                        if showFavoritesOnly {
                            showWithMemoOnly = false
                        }
                    }

                    filterPill(
                        label: "bookshelf.memo",
                        count: memoCount,
                        isSelected: showWithMemoOnly
                    ) {
                        showWithMemoOnly.toggle()
                        if showWithMemoOnly {
                            showFavoritesOnly = false
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            // カレンダービューへ切り替え（グリッド表示時のみ表示）
            Button(action: {
                showCalendarView = true
            }) {
                Image("icon-calendar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func filterPill(
        label: LocalizedStringKey,
        count: Int,
        alwaysShowCount: Bool = false,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if alwaysShowCount || count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
                VStack(spacing: 8) {
                    Text("bookshelf.register_prompt")
                        .font(.body)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(userBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .animation(nil, value: userBooks.count)
            }
        }
        .padding(.bottom, 100)
    }
    
    // MARK: - Monthly Memo

    private func openMonthlyMemo(year: Int, month: Int) {
        let text = MonthlyMemoRepository.fetch(year: year, month: month, context: context)?.text ?? ""
        monthlyMemoTarget = MonthlyMemoTarget(year: year, month: month, text: text)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BookshelfView(passbook: PreviewSupport.passbook(named: "漫画"))
    }
    .bookBankPreviewEnvironment()
    .environment(BookshelfChromeState())
}
