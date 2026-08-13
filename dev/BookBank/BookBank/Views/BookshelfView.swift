//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI

/// 本棚画面
struct BookshelfView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nil = 総合口座）
    let passbook: PassbookDTO?

    /// 本棚タブのルートとして表示しているか（カレンダー時の戻るボタン制御を共有状態と同期する）
    let managesCalendarChrome: Bool

    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRepositories.self) private var repos
    @Environment(BookshelfChromeState.self) private var bookshelfChromeState
    
    // MARK: - State / Query
    
    /// すべての口座（リポジトリストリーム）
    @State private var allPassbooks: [PassbookDTO] = []

    /// すべての書籍（リポジトリストリーム・registeredAt 降順＋createdAt 降順の正準ソート）。
    /// 初回yield前は同期スナップショットで補い、空状態UIが1フレーム瞬くのを防ぐ（設計メモ 5.1節）
    @State private var loadedUserBooks: [BookDTO]?
    private var allUserBooks: [BookDTO] { loadedUserBooks ?? repos.books.latestSnapshot }

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

    /// つながり一覧を全件に展開しているか（検索モードに入り直すと畳んだ状態に戻る）
    @State private var showsAllLinks = false

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

    /// カレンダーの同日複数冊一覧シートで選ばれた本。
    /// 一覧シートのdismiss完了後にセットされ、本棚側の通常のNavigationStackから詳細をpushする
    /// （シート内へpushすると詳細を物理画面最上端まで展開できないため。D-4の後日変更・2026-08-12）
    @State private var calendarSelectedBook: BookDTO?
    
    /// 口座に紐づく書籍（総合口座の場合は全書籍）
    private var passbookBooks: [BookDTO] {
        if let passbook {
            return allUserBooks.filter { book in
                book.passbookId == passbook.id
            }
        }
        return allUserBooks
    }

    /// フィルター適用後の書籍
    private var userBooks: [BookDTO] {
        var books = passbookBooks
        
        // お気に入りフィルター
        if showFavoritesOnly {
            books = books.filter { $0.isFavorite }
        }
        
        // メモありフィルター
        if showWithMemoOnly {
            books = books.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }
        }

        // つながり絞り込み（ステップ8'）。既存の絞り込み・本棚内検索とAND合成する。
        // 状態は口座切替をまたいで維持される（BookshelfChromeState・2026-08-12 オーナー確定）
        if let linkFilter {
            books = books.filter { book in
                guard let memo = book.memo, !memo.isEmpty else { return false }
                return MemoLinkParser.parse(memo).contains { $0.key == linkFilter.key }
            }
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

    /// つながりでの絞り込み（本棚タブ全体で共有・口座切替をまたいで維持）
    private var linkFilter: MemoLinkSelection? {
        bookshelfChromeState.linkFilter
    }

    /// 表示中の口座のつながり集計（多い順）。検索モードの一覧と一致チップに使う。
    /// メモリ上の都度構築で足りる規模（設計メモ 3.3節）なので、検索モードのときだけ呼ぶ
    private var linkIndex: MemoLinkIndex {
        MemoLinkIndex.build(from: passbookBooks)
    }
    
    /// カスタム口座のリスト
    private var customPassbooks: [PassbookDTO] {
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
    private var registrationPassbook: PassbookDTO? {
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
    
    init(passbook: PassbookDTO?, startsWithCalendarView: Bool = false, managesCalendarChrome: Bool = false) {
        self.passbook = passbook
        self.managesCalendarChrome = managesCalendarChrome
        _showFavoritesOnly = State(initialValue: false)
        _showWithMemoOnly = State(initialValue: false)
        _showCalendarView = State(initialValue: startsWithCalendarView)
        _monthlyMemoTarget = State(initialValue: nil)
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
                    onSelectDayBook: { book in
                        // 一覧シートのdismiss完了後に呼ばれる。通常のNavigationStackから詳細をpushする
                        calendarSelectedBook = book
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

                        // つながりで絞り込み中だけ出る解除チップ。
                        // 3タブ・本棚内検索とAND併用中も出したままにして、解除の口を失わない
                        if linkFilter != nil {
                            linkFilterChipRow
                        }

                        if isSearching {
                            if isShelfSearchActive {
                                // 入力あり: 一致するつながりのチップ（検索結果の上・決定事項3）＋件数
                                linkMatchRow
                                searchResultCount
                            } else {
                                // 入力前: つながりの一覧（表記ゆれに気づく場所・設計メモ4.1節）
                                linkListSection
                            }
                        }

                        // 本棚グリッド
                        gridContent
                    }
                }
                // スクロールでキーボードを閉じる（検索モード自体は維持・仕様3.5）
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .id(passbook?.id ?? "overall")
        .navigationDestination(item: $calendarSelectedBook) { book in
            UserBookDetailView(book: book)
        }
        .task {
            for await value in repos.passbooks.observePassbooks() {
                allPassbooks = value
            }
        }
        .task {
            for await value in repos.books.observeBooks() {
                loadedUserBooks = value
            }
        }
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
            // 口座切替（.id によるView再生成）で検索モードは終わるので、
            // ＋ボタン用の共有状態が「検索中」のまま残らないよう同期する
            bookshelfChromeState.isSearching = isSearching
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

    // MARK: - Link Filter（つながり絞り込み・ステップ8'）

    /// つながりの印（メモ編集ツールバーの「つなぐ」と同じ図像）。
    /// チップの言葉だけでは著者・タイトルの一致と見分けがつかないため添える
    /// （2026-08-12 オーナー指示——文言だと5言語で幅が伸びるのでアイコンで示す）
    private func linkChipIcon(size: CGFloat = 12) -> some View {
        Image("icn_node")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    /// 絞り込み中チップの文字色。塗りが `bookshelfControlColor` なのでその反転色
    private var linkChipSelectedTextColor: Color {
        if isOverallAccount && colorScheme == .light { return .white }
        return .black
    }

    /// 絞り込み中だけ出る解除チップの行。ベタ塗り＝選択中、✕で解除。
    /// 解除しても口座モードには触れない（総合口座のまま・2026-08-12 オーナー確定）
    private var linkFilterChipRow: some View {
        HStack {
            if let linkFilter {
                Button(action: { bookshelfChromeState.linkFilter = nil }) {
                    HStack(spacing: 6) {
                        linkChipIcon()
                        Text(linkFilter.display)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(linkChipSelectedTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(bookshelfControlColor))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// 候補チップ（線のみ・件数つき）。タップでそのつながりの絞り込みへ切り替える
    private func linkSuggestionChip(_ link: MemoLinkIndex.Link, showsIcon: Bool) -> some View {
        Button(action: { applyLinkFilter(MemoLinkSelection(key: link.key, display: link.display)) }) {
            HStack(spacing: 6) {
                if showsIcon {
                    linkChipIcon()
                }
                Text(link.display)
                    .lineLimit(1)
                Text(link.bookCount.formatted())
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.7)
            }
            .font(.system(size: 13))
            .foregroundColor(bookshelfControlColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(bookshelfControlColor.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 一覧に最初から出すつながりの数（多い順の上位）。実際は数十件に収まる想定だが、
    /// 上限が無いと際限なく伸びるため区切る（2026-08-12 実機確認を受けたオーナー指示）
    private static let linkListDisplayLimit = 20

    /// 検索の入力前に出す、つながりの一覧（多い順・件数つき）。
    /// 全部のつながりを見られる場所で、表記ゆれ（[[京都]] と [[きょうと]]）に
    /// 気づく場所を兼ねる（設計メモ 4.1節）。つながりが1つも無ければ何も出ない。
    /// 上限を超えるぶんは「もっと見る」で全件に展開する
    @ViewBuilder
    private var linkListSection: some View {
        let links = linkIndex.links
        let visibleLinks = showsAllLinks ? links : Array(links.prefix(Self.linkListDisplayLimit))
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    linkChipIcon(size: 11)
                    Text("bookshelf.links.header")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(bookshelfControlColor.opacity(0.7))

                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(visibleLinks, id: \.key) { link in
                        linkSuggestionChip(link, showsIcon: false)
                    }

                    if links.count > visibleLinks.count {
                        showMoreLinksChip(remaining: links.count - visibleLinks.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    /// 一覧の続きを開くチップ（残り件数つき）。押すと全件に展開する
    private func showMoreLinksChip(remaining: Int) -> some View {
        Button(action: { showsAllLinks = true }) {
            HStack(spacing: 4) {
                Text(L10n.format("bookshelf.links.show_more", Int64(remaining)))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundColor(bookshelfControlColor.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                Capsule().strokeBorder(
                    bookshelfControlColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 検索語に一致するつながりのチップ（検索結果の上・決定事項3）。
    /// 一致は部分一致＋本棚内検索と同じ正規化、複数一致は多い順に横1行
    /// （2026-08-12 オーナー確定）。先頭のアイコンが「著者・タイトルの一致ではなく
    /// つながり」であることの見分けになる
    @ViewBuilder
    private var linkMatchRow: some View {
        let matches = linkIndex.links(matching: shelfSearchText)
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(matches, id: \.key) { link in
                        linkSuggestionChip(link, showsIcon: true)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 10)
        }
    }

    /// つながりの絞り込みへ切り替える。検索モード中なら検索文字をクリアして
    /// 通常表示へ戻す（決定事項3「押すと検索文字はクリアされ、絞り込みに切り替わる」）
    private func applyLinkFilter(_ selection: MemoLinkSelection) {
        bookshelfChromeState.linkFilter = selection
        if isSearching {
            exitShelfSearch()
        }
    }

    /// 検索モードに入る（フィールドを展開してフォーカス）。
    /// 検索モード中は右下の＋ボタンを隠すため、共有状態にも反映する
    /// （0件画面の「本を登録する」と重複するため・2026-08-12 オーナー確定）。
    /// つながり一覧は入り直すたびに畳んだ状態から始める
    private func enterShelfSearch() {
        showsAllLinks = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearching = true
        }
        bookshelfChromeState.isSearching = true
        isSearchFieldFocused = true
    }

    /// 検索モードを終了（テキストをクリアして通常のフィルター行へ戻す）
    private func exitShelfSearch() {
        isSearchFieldFocused = false
        shelfSearchText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearching = false
        }
        bookshelfChromeState.isSearching = false
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
    
    /// 書籍ストリームの初回値を受け取ったか。
    /// コールドスタートで `latestSnapshot` もまだ空の1フレームに空状態が瞬くのを防ぐ
    /// （`MainTabView.emptyStateView` と同じパターン・設計メモ 5.1節／レビュー S4-2）
    private var hasLoadedUserBooks: Bool {
        loadedUserBooks != nil || !repos.books.latestSnapshot.isEmpty
    }

    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
                if isShelfSearchActive {
                    searchEmptyState
                } else if linkFilter != nil {
                    // つながり絞り込みで0件（お気に入り等とのANDや、メモの書き換えで起こる）。
                    // 「本を登録しましょう」では誤解を招くため専用の文言を出す
                    linkFilterEmptyState
                } else if hasLoadedUserBooks {
                    VStack(spacing: 8) {
                        Text("bookshelf.register_prompt")
                            .font(.body)
                            .foregroundColor(bookshelfControlColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    // 未受信の1フレーム: 空状態を出さず、レイアウトが潰れないよう同じ場所を占有する
                    // （ステップ3レビュー6章のレイアウト1フレーム潰れの再発防止）
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 0)
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
    
    /// つながり絞り込みで0件のときの空状態
    private var linkFilterEmptyState: some View {
        Text("bookshelf.link_filter.empty")
            .font(.subheadline)
            .foregroundColor(bookshelfControlColor.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 40)
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
                        Text("book.register")
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
    .environment(AppShellState())
}
