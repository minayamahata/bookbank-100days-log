//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI
import UIKit

/// 本棚画面
struct BookshelfView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nil = 総合口座）
    let passbook: PassbookDTO?

    /// 本棚タブのルートとして表示しているか（カレンダー時の戻るボタン制御を共有状態と同期する）
    let managesCalendarChrome: Bool

    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
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

    /// 本棚内検索モード（フィルター行が検索フィールドに変形）。
    /// UI一式は通帳ページと共通の `ShelfSearchView`（R4.6・2026-08-13で共通化）。
    /// クエリ・フォーカス・つながり一覧の開閉はコンポーネント内部の状態
    @State private var isSearching: Bool = false

    /// 検索の0件表示から開く登録画面（`ShelfSearchView` はコールバックしか持たないため、
    /// NavigationLink ではなくここで item ベースのpushにする）
    @State private var searchRegistrationTarget: BookSearchDestination?

    /// 月別メモとマンスリーログ共有は同じ `.sheet(item:)` から出す。
    /// 2つの sheet modifier を並べると、片方しか開かないことがあるため。
    @State private var calendarSheet: CalendarSheetRoute?

    /// 月別メモシートの対象
    private struct MonthlyMemoTarget: Identifiable {
        let year: Int
        let month: Int
        let text: String
        var id: String { "\(year)-\(month)" }
    }

    private enum CalendarSheetRoute: Identifiable {
        case monthlyMemo(MonthlyMemoTarget)
        case monthlyLogShare(MonthlyLogShareSession)

        var id: String {
            switch self {
            case .monthlyMemo(let target):
                return "memo-\(target.id)"
            case .monthlyLogShare(let session):
                return "share-\(session.id)"
            }
        }
    }

    /// 通常のNavigationStackから詳細をpushする対象の本。使い道は2つ:
    /// - カレンダーの同日複数冊一覧シートで選ばれた本（一覧シートのdismiss完了後にセット。
    ///   シート内へpushすると詳細を物理画面最上端まで展開できないため。D-4の後日変更・2026-08-13）
    /// - 検索結果グリッドで選ばれた本（`ShelfSearchView` のコールバック経由）
    @State private var selectedDetailBook: BookDTO?

    /// マンスリーログ共有の表紙準備（スクリーンショットまたは月ヘッダーの共有ボタン）
    @State private var monthlyLogSharePreparation = MonthlyLogSharePreparation()
    @State private var isCalendarInForeground = false
    @State private var visibleMonthCandidates: [MonthlyLogShareVisibleMonth.Candidate] = []
    @State private var calendarViewport: CGRect = .zero
    @State private var isDaySheetPresented = false
    
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

        // 本棚内検索のクエリ絞り込みは `ShelfSearchView` の内部で行う。
        // ここまでのフィルタ適用後を検索対象として渡すことで、従来どおりのAND合成になる

        return books
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
        _calendarSheet = State(initialValue: nil)
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
                        selectedDetailBook = book
                    },
                    onShareMonth: { year, month in
                        openMonthlyLogShare(year: year, month: month)
                    },
                    onDaySheetPresentedChange: { presented in
                        isDaySheetPresented = presented
                    },
                    onForegroundChange: { isFront in
                        isCalendarInForeground = isFront
                        if !isFront {
                            monthlyLogSharePreparation.cancel()
                        }
                    },
                    header: {
                        EmptyView()
                    }
                )
                .onPreferenceChange(MonthlyLogShareMonthFrameKey.self) { candidates in
                    visibleMonthCandidates = candidates
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { _, frame in
                    calendarViewport = frame
                }
            } else {
                // 本棚内検索（R4.6）は通常表示を残したまま上に重ねる。
                // 差し替え（作り直し）にすると閉じるたびにグリッドの再構築が走って
                // 引っかかるため（2026-08-14 オーナー指摘・通帳側と同じ方式）。
                // 裏側はヒットテストを切るので、検索中に裏のスクロールは効かない
                ScrollView {
                    VStack(spacing: 0) {
                        // フィルターセクション（通常のピル行）
                        normalFilterRow

                        // つながりで絞り込み中だけ出る解除チップ
                        if linkFilter != nil {
                            linkFilterChipRow
                        }

                        // 本棚グリッド
                        gridContent
                    }
                }
                .allowsHitTesting(!isSearching)
                .overlay {
                    if isSearching {
                        shelfSearchOverlay
                    }
                }
            }
        }
        .id(passbook?.id ?? "overall")
        .navigationDestination(item: $selectedDetailBook) { book in
            UserBookDetailView(book: book)
        }
        .navigationDestination(item: $searchRegistrationTarget) { destination in
            BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
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
        .navigationTitle(searchAwareNavigationTitle)
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
            } else {
                isCalendarInForeground = false
                monthlyLogSharePreparation.cancel()
            }
        }
        .onChange(of: bookshelfChromeState.isCalendar) { _, newValue in
            if managesCalendarChrome, showCalendarView != newValue {
                showCalendarView = newValue
            }
        }
        .onChange(of: bookshelfChromeState.isSearching) { _, newValue in
            // 右上ツールバーの虫眼鏡（MainTabView側・2026-08-14に入口を移設）からの
            // 検索開始を受け取る。自分発の変更（exitShelfSearch等）はguardで素通し
            guard newValue != isSearching else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearching = newValue
            }
        }
        .sheet(item: $calendarSheet) { route in
            switch route {
            case .monthlyMemo(let target):
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
            case .monthlyLogShare(let session):
                MonthlyLogShareView(session: session) {
                    calendarSheet = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { notification in
            handleScreenshot(notification)
        }
        .overlay {
            if monthlyLogSharePreparation.isPreparing {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("monthly_log_share.preparing")
                            .font(.app(.footnote))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .allowsHitTesting(true)
            }
        }
    }
    
    // MARK: - Shelf Search（本棚内検索・R4.6）

    /// ナビゲーションタイトル。検索中は通帳側と共通の「検索」
    ///（どのタブから入っても同じ画面のため・2026-08-14 オーナー確定）
    private var searchAwareNavigationTitle: LocalizedStringKey {
        if isSearching { return "bookshelf.search.title" }
        return showCalendarView ? "bookshelf.calendar_title" : "bookshelf.title"
    }

    /// 通常表示の上に重ねる検索UI一式（通帳ページと共通・R4.6）。
    /// 解除チップの行は検索バー直下のスロットへ差し込み、従来の並び順を保つ
    private var shelfSearchOverlay: some View {
        ScrollView {
            ShelfSearchView(
                books: userBooks,
                linkIndex: linkIndex,
                controlColor: bookshelfControlColor,
                onSelectBook: { book in
                    selectedDetailBook = book
                },
                onSelectLink: { selection in
                    applyLinkFilter(selection)
                },
                onRegisterBook: registrationPassbook.map { target in
                    { searchRegistrationTarget = BookSearchDestination(passbook: target) }
                }
            ) {
                // つながりで絞り込み中だけ出る解除チップ。
                // 検索とAND併用中も出したままにして、解除の口を失わない
                if linkFilter != nil {
                    linkFilterChipRow
                }
            } emptyFallback: {
                // 入力前に0冊（絞り込みやメモ書き換えで起こる）: 通常表示と同じ空状態
                emptyShelfState
            }
        }
        // スクロールでキーボードを閉じる（検索モード自体は維持・仕様3.5）
        .scrollDismissesKeyboard(.immediately)
        .background {
            // 下の通常表示が透けないよう、外側と同じ背景をもう一度敷く
            if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
        }
    }

    // MARK: - Filter Section

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

            // カレンダービューへ切り替え（グリッド表示時のみ表示）
            // 総合口座の通帳ビューの丸アクションボタンと同じグラススタイルにする。
            // 本棚内検索の虫眼鏡は右上ツールバーへ移設した（通帳と入口を統一・2026-08-14）
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

    // MARK: - Link Filter（つながり絞り込み・ステップ8'）

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
                        MemoLinkChipIcon()
                        Text(linkFilter.display)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.app(size: 13))
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

    /// つながりの絞り込みへ切り替える。検索モード中なら検索を閉じて
    /// 通常表示へ戻す（決定事項3「押すと検索文字はクリアされ、絞り込みに切り替わる」）
    private func applyLinkFilter(_ selection: MemoLinkSelection) {
        bookshelfChromeState.linkFilter = selection
        if isSearching {
            exitShelfSearch()
        }
    }

    /// 検索モードを終了（通常のフィルター行へ戻す。クエリはコンポーネントごと破棄される）。
    /// 開始は右上ツールバーの虫眼鏡が `bookshelfChromeState.isSearching` を立て、
    /// onChange で受け取る（入口は MainTabView 側・2026-08-14 通帳と統一）
    private func exitShelfSearch() {
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
                        .font(.app(size: 13, weight: isSelected ? .bold : .regular))

                    if alwaysShowCount || count > 0 {
                        Text(count.formatted())
                            .font(.app(size: 10))
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
                emptyShelfState
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

    /// 0冊のときの空状態（検索での0件は `ShelfSearchView` 側が担う）。
    /// 検索モードの入力前でも同じ表示を使う（`emptyFallback` として渡す）
    @ViewBuilder
    private var emptyShelfState: some View {
        if linkFilter != nil {
            // つながり絞り込みで0件（お気に入り等とのANDや、メモの書き換えで起こる）。
            // 「本を登録しましょう」では誤解を招くため専用の文言を出す
            linkFilterEmptyState
        } else if hasLoadedUserBooks {
            VStack(spacing: 8) {
                Text("bookshelf.register_prompt")
                    .font(.app(.body))
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
    }

    /// つながり絞り込みで0件のときの空状態
    private var linkFilterEmptyState: some View {
        Text("bookshelf.link_filter.empty")
            .font(.app(.subheadline))
            .foregroundColor(bookshelfControlColor.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 40)
    }

    // MARK: - Monthly Memo

    private var isMonthlyMemoPresented: Bool {
        if case .monthlyMemo = calendarSheet { return true }
        return false
    }

    private var isMonthlyLogSharePresented: Bool {
        if case .monthlyLogShare = calendarSheet { return true }
        return false
    }

    private var screenshotGate: MonthlyLogShareScreenshotGate {
        MonthlyLogShareScreenshotGate(
            isAppActive: scenePhase == .active,
            isCalendarVisible: showCalendarView,
            isCalendarInForeground: isCalendarInForeground,
            isSharePresented: isMonthlyLogSharePresented,
            isPreparing: monthlyLogSharePreparation.isPreparing,
            isMonthlyMemoPresented: isMonthlyMemoPresented,
            isDaySheetPresented: isDaySheetPresented,
            hasOtherCoveringModal: selectedDetailBook != nil || searchRegistrationTarget != nil
        )
    }

    private func handleScreenshot(_ notification: Notification) {
        guard MonthlyLogShareScreenshotRouting.shouldPresent(notification: notification, gate: screenshotGate) else {
            return
        }
        let selected = MonthlyLogShareVisibleMonth.select(
            candidates: visibleMonthCandidates,
            viewport: calendarViewport
        ) ?? MonthlyLogShareVisibleMonth.currentMonth(calendar: .current)
        openMonthlyLogShare(year: selected.year, month: selected.month)
    }

    private func openMonthlyLogShare(year: Int, month: Int) {
        let books = passbookBooks
        let currency = currencyManager.displayCurrency
        let locale = languageManager.resolvedLocale
        monthlyLogSharePreparation.start(
            shouldStart: MonthlyLogShareScreenshotRouting.shouldStartPreparation(gate: screenshotGate),
            prepare: {
                let snapshot = MonthlyLogShareSnapshot.make(
                    year: year,
                    month: month,
                    passbookBooks: books,
                    displayCurrency: currency,
                    exchangeRates: exchangeRates,
                    calendar: .current,
                    locale: locale
                )
                try Task.checkCancellation()
                let covers = await MonthlyLogShareCoverResolver.resolve(
                    books: snapshot.books,
                    loadLocalCover: { bookId in
                        await repos.books.loadCoverImage(bookId: bookId)
                    }
                )
                try Task.checkCancellation()
                return MonthlyLogShareSession(
                    year: year,
                    month: month,
                    snapshot: snapshot,
                    covers: covers
                )
            },
            canCommit: {
                MonthlyLogShareScreenshotRouting.canCommitPreparedSession(gate: screenshotGate)
            },
            commit: { session in
                calendarSheet = .monthlyLogShare(session)
            }
        )
    }

    private func openMonthlyMemo(year: Int, month: Int) {
        // observeMemo は購読開始時に現在値を即yieldするため、先頭値の取得＝現行fetchと同義
        Task {
            var text = ""
            for await memo in repos.monthlyMemos.observeMemo(year: year, month: month) {
                text = memo?.text ?? ""
                break
            }
            calendarSheet = .monthlyMemo(
                MonthlyMemoTarget(year: year, month: month, text: text)
            )
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
