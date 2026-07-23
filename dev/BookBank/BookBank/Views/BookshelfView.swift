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
    @Environment(AppRepositories.self) private var repos
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

    /// 本棚内検索モード（フィルター行が検索フィールドに変形）
    /// - Note: オンライン検索（`BookSearchView` の `SearchPhase`・世代管理・ページング）とは
    ///   完全に別系統。ここでは所有本のローカル絞り込みのみを行い、既存の検索状態は参照しない。
    @State private var isSearching: Bool = false

    /// 本棚内検索のクエリ（1文字ごとに即時絞り込み）
    @State private var shelfSearchText: String = ""

    /// 検索フィールドのフォーカス
    @FocusState private var isSearchFieldFocused: Bool

    /// 月別メモ編集用（口座横断・年月ごとに1つ。全口座のカレンダーから編集可能）
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

        // 本棚内検索（タイトル・著者のローカル絞り込み）。既存フィルターとAND合成する。
        // 数百〜千冊でもタイトル+著者の正規化は軽量なため、毎キーストロークのインライン計算で十分。
        if isSearching {
            let query = shelfSearchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                books = books.filter {
                    ShelfSearchMatcher.matches(fields: [$0.title, $0.author], query: query)
                }
            }
        }

        return books
    }

    /// 本棚内検索が有効な絞り込みを行っているか（モードON かつ 入力あり）
    private var isShelfSearchActive: Bool {
        isSearching && !shelfSearchText.trimmingCharacters(in: .whitespaces).isEmpty
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

    /// フィルター/プロンプトの基準色
    /// 総合口座のライトモードは白背景なので primary、それ以外（テーマ色背景・ダーク）は白
    private var bookshelfControlColor: Color {
        if isOverallAccount && colorScheme == .light { return .primary }
        return .white
    }

    /// 丸アクションボタン（カレンダー切替・本棚検索）のグラス tint
    /// 総合口座はボタン自体をシステム前景色に合わせてダーク=白／ライト=黒にする。
    /// 個別口座は従来どおりテーマ色（ダークモード×黒テーマのみ白）。
    private var actionButtonGlassTint: Color {
        if isOverallAccount { return colorScheme == .dark ? .white : .black }
        return colorScheme == .dark && isBlackTheme ? .white : themeColor
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

    /// カレンダー切替ボタン・本棚検索の虫眼鏡ボタンの記号色
    /// 総合口座は tint（ダーク=白／ライト=黒）に対してコントラストを取り、ダーク=黒／ライト=白にする。
    /// 個別口座はグラス tint が白（ダークモード×黒テーマ）のときだけ、白背景に埋もれないよう黒にする。
    private var calendarToggleIconColor: Color {
        if isOverallAccount { return colorScheme == .dark ? .black : .white }
        if colorScheme == .dark && isBlackTheme { return .black }
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
                        // フィルターセクション（通常のピル行 ⇔ 検索フィールド行）
                        filterSection

                        // 検索中は件数を検索フィールド直下に表示
                        if isShelfSearchActive {
                            searchResultCount
                        }

                        // 本棚グリッド
                        gridContent
                    }
                }
                // スクロールでキーボードを閉じる（検索モード自体は維持・仕様3.5）
                .scrollDismissesKeyboard(.immediately)
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
                // 共有 chrome を状態源として採用し、外部からのカレンダー起動（通帳からの導線）を反映する
                showCalendarView = bookshelfChromeState.isCalendar
            }
        }
        .onChange(of: showCalendarView) { _, newValue in
            if managesCalendarChrome {
                bookshelfChromeState.isCalendar = newValue
            }
            // カレンダーへ切り替えたら本棚内検索モードを解除する（仕様3.5）
            if newValue {
                exitShelfSearch()
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
                // 失敗は現行同様に静かに飲む（リポジトリ内でOSLog記録・rollback済み。設計メモ 4.5節）
                Task {
                    try? await repos.monthlyMemos.saveMemo(
                        year: target.year,
                        month: target.month,
                        text: newText
                    )
                }
            }
        }
    }
    
    // MARK: - Filter Section
    
    @ViewBuilder
    private var filterSection: some View {
        if isSearching {
            searchFieldRow
        } else {
            normalFilterRow
        }
    }

    private var normalFilterRow: some View {
        VStack(spacing: 0) {
        HStack(alignment: .bottom, spacing: 10) {
            // タブ切替風のフィルター。行全体に薄い境界線を通し、アクティブ要素の下だけ太く見せる。
            // タブエリアを幅いっぱいに広げ、3タブを均等に散らしてゆったり配置する。
            HStack(alignment: .bottom, spacing: 0) {
                filterTab(
                    label: "common.all",
                    count: allBooksCount,
                    alwaysShowCount: true,
                    isSelected: !showFavoritesOnly && !showWithMemoOnly
                ) {
                    showFavoritesOnly = false
                    showWithMemoOnly = false
                }

                Spacer(minLength: 8)

                filterTab(
                    label: "bookshelf.favorite",
                    count: favoriteCount,
                    isSelected: showFavoritesOnly
                ) {
                    showFavoritesOnly.toggle()
                    if showFavoritesOnly {
                        showWithMemoOnly = false
                    }
                }

                Spacer(minLength: 8)

                filterTab(
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
            .frame(maxWidth: .infinity)

            // 虫眼鏡・カレンダーボタンはまとめて間隔を狭くする
            HStack(alignment: .bottom, spacing: 4) {
            // 本棚内検索を開く（カレンダーボタンの左隣・同一グラス様式）
            Button(action: { enterShelfSearch() }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(calendarToggleIconColor)
                    .frame(width: 34, height: 34)
                    .passbookCircleGlass(tint: actionButtonGlassTint)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("bookshelf.search.placeholder"))
            .padding(.bottom, 6)

            // カレンダービューへ切り替え（グリッド表示時のみ表示）
            // 総合口座の通帳ビューの丸アクションボタンと同じグラススタイルにする
            Button(action: {
                showCalendarView = true
            }) {
                Image("icon-calendar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(calendarToggleIconColor)
                    .frame(width: 34, height: 34)
                    .passbookCircleGlass(tint: actionButtonGlassTint)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            }
        }

        // 行全体（タブ＋虫眼鏡・カレンダーボタンの下）に通す薄い境界線。
        // アクティブタブの下だけ、この線の上に太い色線が重なって太く見える。
        Rectangle()
            .fill(bookshelfControlColor.opacity(0.2))
            .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// 検索モード時のフィルター行（虫眼鏡＋テキストフィールド＋クリア＋キャンセル）
    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(bookshelfControlColor.opacity(0.7))

                TextField(
                    "",
                    text: $shelfSearchText,
                    prompt: Text("bookshelf.search.placeholder")
                        .foregroundColor(bookshelfControlColor.opacity(0.5))
                )
                .font(.system(size: 13))
                .focused($isSearchFieldFocused)
                .foregroundColor(bookshelfControlColor)
                .tint(bookshelfControlColor)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(Text("bookshelf.search.placeholder"))

                if !shelfSearchText.isEmpty {
                    Button(action: { shelfSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(bookshelfControlColor.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(bookshelfControlColor.opacity(0.08)))
            .overlay(Capsule().strokeBorder(bookshelfControlColor.opacity(0.3), lineWidth: 1))

            Button("common.cancel") { exitShelfSearch() }
                .font(.system(size: 14))
                .foregroundColor(bookshelfControlColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// 検索結果の件数表示（検索フィールド直下）
    private var searchResultCount: some View {
        HStack {
            Text(L10n.format("bookshelf.search.result_count", Int64(userBooks.count)))
                .font(.caption)
                .foregroundColor(bookshelfControlColor.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// 検索モードに入る（フィールドを展開してフォーカス）
    private func enterShelfSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearching = true
        }
        isSearchFieldFocused = true
    }

    /// 検索モードを終了（テキストをクリアして通常のフィルター行へ戻す）
    private func exitShelfSearch() {
        isSearchFieldFocused = false
        shelfSearchText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearching = false
        }
    }

    /// タブ切替風のフィルター項目（等幅）。カプセルで個々を囲まず、
    /// 全タブに共通の薄い境界線を通し、アクティブ要素の下だけ太い色線を重ねる。
    private func filterTab(
        label: LocalizedStringKey,
        count: Int,
        alwaysShowCount: Bool = false,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                    if alwaysShowCount || count > 0 {
                        Text(count.formatted())
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(bookshelfControlColor.opacity(0.2))
                            )
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(isSelected ? bookshelfControlColor : bookshelfControlColor.opacity(0.5))

                // アクティブのみ太い色線（薄い基準線は行全体に敷いた線が担うため、ここはクリア）。
                // 固定高でラベルが動かないようにする。
                Rectangle()
                    .fill(isSelected ? bookshelfControlColor : Color.clear)
                    .frame(height: 2.5)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
                if isShelfSearchActive {
                    searchEmptyState
                } else {
                    VStack(spacing: 8) {
                        Text("bookshelf.register_prompt")
                            .font(.body)
                            .foregroundColor(bookshelfControlColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
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
    
    /// 本棚内検索で0件のときの空状態。オンライン検索（登録）への導線を出す（仕様3.4）。
    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(bookshelfControlColor.opacity(0.5))

            Text("bookshelf.search.empty_title")
                .font(.headline)
                .foregroundColor(bookshelfControlColor)

            Text("bookshelf.search.empty_message")
                .font(.subheadline)
                .foregroundColor(bookshelfControlColor.opacity(0.7))
                .multilineTextAlignment(.center)

            // 総合口座でカスタム口座が無い場合は登録先が無いため導線を出さない
            if let registrationPassbook {
                NavigationLink(value: BookSearchDestination(passbook: registrationPassbook)) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("bookshelf.search.online_cta")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(bookshelfControlColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().strokeBorder(bookshelfControlColor.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Monthly Memo

    private func openMonthlyMemo(year: Int, month: Int) {
        // observeMemo は購読開始時に現在値を即yieldするため、先頭値の取得＝現行fetchと同義
        Task {
            var text = ""
            for await memo in repos.monthlyMemos.observeMemo(year: year, month: month) {
                text = memo?.text ?? ""
                break
            }
            monthlyMemoTarget = MonthlyMemoTarget(year: year, month: month, text: text)
        }
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
