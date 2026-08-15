//
//  MainTabView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI

@Observable
class AppShellState {
    var showAppMenu = false
    var onPassbookSelected: ((PassbookDTO) -> Void)?
    var onOverallSelected: (() -> Void)?
    var onShowBookshelf: (() -> Void)?
    var onShowCalendar: (() -> Void)?
    var onFilterBookshelfByLink: ((MemoLinkSelection) -> Void)?

    func selectPassbook(_ passbook: PassbookDTO) {
        onPassbookSelected?(passbook)
    }

    func selectOverall() {
        onOverallSelected?()
    }

    func showBookshelf() {
        onShowBookshelf?()
    }

    func showCalendar() {
        onShowCalendar?()
    }

    /// 詳細画面のつながりチップから、本棚をそのつながりで絞り込んだ状態で開く（ステップ8'）
    func filterBookshelf(by link: MemoLinkSelection) {
        onFilterBookshelfByLink?(link)
    }
}

@Observable
class FloatingButtonState {
    var isHidden = false
}

@Observable
class PassbookSheetChromeState {
    var isExpanded = false
}

@Observable
class BookshelfChromeState {
    /// 本棚タブがカレンダー表示中か
    var isCalendar = false

    /// 本棚内検索モード中か。検索モードのあいだは本棚タブの＋ボタンを隠す
    /// （0件画面の「本を登録する」と重複するため。キーボードの有無ではなく
    /// モードで判定する——キーボードを閉じても検索モードは続く・2026-08-12 オーナー確定）
    var isSearching = false

    /// つながりでの絞り込み（nil = 絞り込みなし・同時に選べるのは1つ）。
    /// `BookshelfView` のローカル状態ではなくここに置くのは、口座切替（`.id` による
    /// View再生成）をまたいで維持するため——絞り込んだまま口座を切り替えると
    /// 「口座 AND つながり」になる（2026-08-12 オーナー確定）
    var linkFilter: MemoLinkSelection?
}

private struct FloatingButtonStateKey: EnvironmentKey {
    static let defaultValue = FloatingButtonState()
}

extension EnvironmentValues {
    var floatingButtonState: FloatingButtonState {
        get { self[FloatingButtonStateKey.self] }
        set { self[FloatingButtonStateKey.self] = newValue }
    }
}

struct MainTabView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRateService
    @Environment(AppRepositories.self) private var repos
    @State private var passbooks: [PassbookDTO] = []
    /// ストリームの初回値を受け取ったか（初回bodyの空配列で空状態UIが瞬かないようにする＝設計メモ 5.1節）
    @State private var hasLoadedPassbooks = false
    /// 読了リスト。用途はリスト数の上限判定のみで、順序には依存しない
    @State private var loadedReadingLists: [ReadingListDTO]?
    private var readingLists: [ReadingListDTO] { loadedReadingLists ?? repos.readingLists.latestSnapshot }
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    /// 選択中の口座ID（uuid）。DTOのコピーではなくIDで保持し、名称・色の変更が
    /// ストリームの新値から常に反映されるようにする（@Model参照時代の自動反映と同じ見え方）
    @State private var selectedPassbookId: String?
    @State private var isOverallMode = true
    @State private var appShellState = AppShellState()
    @State private var showAddReadingList = false
    @State private var showUnlimitedPaywall = false
    @State private var floatingButtonState = FloatingButtonState()
    @State private var passbookSheetChromeState = PassbookSheetChromeState()
    @State private var bookshelfChromeState = BookshelfChromeState()
    
    /// 各タブのナビゲーションパス
    @State private var accountListNavPath = NavigationPath()
    @State private var passbookNavPath = NavigationPath()
    @State private var bookshelfNavPath = NavigationPath()
    @State private var readingListNavPath = NavigationPath()
    @State private var statisticsNavPath = NavigationPath()
    
    /// 現在選択中のタブ
    @State private var selectedTab = 1  // デフォルトは通帳タブ

    // MARK: 通帳からの本棚内検索（R4.6）

    /// 通帳タブが本棚内検索モードか。本棚と同じインライン切替
    /// （検索中は `PassbookDetailView` を検索ビューへ差し替える。シート提示にしないのは
    /// 入口と見え方を本棚と揃えるため・2026-08-14 オーナー確定）
    @State private var isPassbookSearching = false
    /// 通帳ページのキーボード前 top safe（ナビ＋ステータス）。キーボードで減っても検索の上端を戻す
    @State private var passbookSearchTopLock: CGFloat = 0
    /// 通帳ページの現在の top safe。キーボードで減った差分を検索の下 inset に足す
    @State private var passbookCurrentTopSafe: CGFloat = 0
    /// 検索結果から通帳タブのNavigationStackへpushする詳細の本
    @State private var passbookSearchDetailBook: BookDTO?
    
    // カスタム口座を取得
    private var customPassbooks: [PassbookDTO] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// 現在表示対象の口座（selectedPassbookIdがnil・不一致の場合は最初のカスタム口座）
    private var currentPassbook: PassbookDTO? {
        if let id = selectedPassbookId,
           let match = customPassbooks.first(where: { $0.id == id }) {
            return match
        }
        return customPassbooks.first
    }
    /// 通帳・本棚・集計に渡す口座（総合口座モード時は nil）
    private var displayPassbook: PassbookDTO? {
        isOverallMode ? nil : currentPassbook
    }
    
    /// 表示用の口座ID（View更新トリガー）
    private var displayPassbookID: String {
        if isOverallMode { return "overall" }
        return currentPassbook?.id ?? "none"
    }
    
    private var isNavigating: Bool {
        !accountListNavPath.isEmpty || !passbookNavPath.isEmpty || !bookshelfNavPath.isEmpty || !readingListNavPath.isEmpty || !statisticsNavPath.isEmpty
    }
    
    /// 現在の口座のテーマカラー
    private var currentThemeColor: Color {
        if isOverallMode { return PassbookColor.overallAccentColor }
        if let passbook = currentPassbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
    /// 現在の口座が黒テーマかどうか
    private var isBlackTheme: Bool {
        if isOverallMode { return false }
        guard let passbook = currentPassbook else { return false }
        return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
    }

    private var appMenuPresentation: Binding<Bool> {
        Binding(
            get: { appShellState.showAppMenu },
            set: { appShellState.showAppMenu = $0 }
        )
    }
    
    var body: some View {
        let _ = themeManager.currentTheme
        let _ = languageManager.currentLanguage
        let _ = currencyManager.displayCurrency

        mainTabContent
            .environment(appShellState)
            .environment(passbookSheetChromeState)
            .environment(bookshelfChromeState)
            .environment(\.floatingButtonState, floatingButtonState)
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    passbooks = value
                    hasLoadedPassbooks = true
                    // 口座削除後に選択状態が削除済み口座を参照し続けないようにする
                    validateSelectedPassbook()
                }
            }
            .task {
                for await value in repos.readingLists.observeReadingLists() {
                    loadedReadingLists = value
                }
            }
            .onAppear {
                appShellState.onPassbookSelected = { passbook in
                    isOverallMode = false
                    selectedPassbookId = passbook.id
                    selectedTab = 1
                    passbookNavPath = NavigationPath()
                    isPassbookSearching = false
                }
                appShellState.onOverallSelected = {
                    isOverallMode = true
                    selectedTab = 1
                    isPassbookSearching = false
                }
                // 本棚・カレンダーへの導線は「本棚タブに切り替える」ことで
                // ルート表示に統一する（戻るボタンを出さず、タブバーも本棚をアクティブにする）
                appShellState.onShowBookshelf = {
                    bookshelfNavPath = NavigationPath()
                    bookshelfChromeState.isCalendar = false
                    selectedTab = 2
                }
                appShellState.onShowCalendar = {
                    bookshelfNavPath = NavigationPath()
                    bookshelfChromeState.isCalendar = true
                    selectedTab = 2
                }
                // つながりチップ→本棚。総合口座モードへ切り替えて全冊から絞る
                // （2026-08-12 オーナー確定——つながりの価値は口座をまたいで本が出てくること。
                // 口座が切り替わったことは左上の口座セレクタの「総合口座」表示で分かる。
                // 絞り込みを解除しても総合のまま＝自動で元の口座へは戻さない）
                appShellState.onFilterBookshelfByLink = { link in
                    bookshelfChromeState.linkFilter = link
                    isOverallMode = true
                    resetContentNavigationPaths()
                    bookshelfChromeState.isCalendar = false
                    selectedTab = 2
                }
                validateSelectedPassbook()
            }
            .sheet(isPresented: $showAddReadingList) {
                AddReadingListView(themeColor: currentThemeColor) {
                    selectedTab = 1
                }
            }
            .sheet(isPresented: $showUnlimitedPaywall) {
                UnlimitedPaywallView()
            }
            .fullScreenCover(isPresented: appMenuPresentation) {
                NavigationStack {
                    AppMenuView(onDismiss: { appShellState.showAppMenu = false })
                }
                .environment(themeManager)
                .environment(languageManager)
                .environment(\.locale, languageManager.resolvedLocale)
                .environment(currencyManager)
                .environment(exchangeRateService)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
            }
    }
    
    /// タブ選択用バインディング。すでに選択中のタブを再タップしたら、そのタブの
    /// ナビゲーションをルートまで戻す（例：通帳タブ→通帳ページを必ず表示）
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    resetNavigation(for: newValue)
                }
                selectedTab = newValue
            }
        )
    }

    private func resetNavigation(for tab: Int) {
        switch tab {
        case 0: accountListNavPath = NavigationPath()
        case 1: passbookNavPath = NavigationPath()
        case 2: bookshelfNavPath = NavigationPath()
        case 3: statisticsNavPath = NavigationPath()
        case 4: readingListNavPath = NavigationPath()
        default: break
        }
    }

    private var mainTabContent: some View {
        ZStack(alignment: .bottom) {
            // 標準のTabView
            TabView(selection: tabSelection) {
                // 口座一覧タブ
                NavigationStack(path: $accountListNavPath) {
                    AccountListView(
                        onPassbookSelected: { passbook in
                            isOverallMode = false
                            selectedPassbookId = passbook.id
                            selectedTab = 1
                            passbookNavPath = NavigationPath()
                        },
                        onOverallSelected: {
                            isOverallMode = true
                            selectedTab = 1
                        }
                    )
                }
                .tabItem {
                    Label("tab.account", image: "icon-tab-account")
                }
                .tag(0)
                
                // 通帳タブ
                NavigationStack(path: $passbookNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else {
                            // 本棚内検索（R4.6）は通帳ページを残したまま上に重ねる。
                            // 差し替え（作り直し）にすると、閉じるたびに通帳の実測・表紙・シートの
                            // 再構築が一度に走って引っかかるため（2026-08-14 オーナー指摘）。
                            // 裏側はヒットテストを切るので、通帳シートのドラッグ・スクロールは効かない。
                            // 上端揃え＋背面だけキーボードセーフエリアを無視する。
                            // 通帳タブはキーボードで top safe が 116→85 に減る（隠しナビ＋下端無視の副作用）ので、
                            // 検索レイヤーは開いた時点の top を固定し、コンテナ上端だけ無視して戻す。
                            ZStack(alignment: .top) {
                                PassbookDetailView(
                                    passbook: displayPassbook,
                                    isSearchOverlayActive: isPassbookSearching
                                )
                                .id("passbook-\(displayPassbookID)")
                                .allowsHitTesting(!isPassbookSearching)
                                .ignoresSafeArea(.keyboard)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.safeAreaInsets.top
                                } action: { _, top in
                                    if passbookSearchTopLock == 0, top > 0 {
                                        passbookSearchTopLock = top
                                    }
                                    passbookCurrentTopSafe = top
                                }

                                if isPassbookSearching {
                                    PassbookShelfSearchView(
                                        passbook: displayPassbook,
                                        customPassbooks: customPassbooks,
                                        onSelectBook: { book in
                                            // シートではないので回避策なしで直接push
                                            //（検索状態は裏に残り、戻ると検索結果へ戻る）
                                            passbookSearchDetailBook = book
                                        },
                                        onSelectLink: { link in
                                            // 書籍詳細のつながりチップと同じ遷移
                                            //（総合口座へ切り替えて本棚を絞り込む）
                                            appShellState.filterBookshelf(by: link)
                                        },
                                        onRegisterBook: { passbook in
                                            passbookNavPath.append(BookSearchDestination(passbook: passbook))
                                        }
                                    )
                                    .id("passbook-search-\(displayPassbookID)")
                                    .padding(.top, passbookSearchTopLock)
                                    .padding(.bottom, max(0, passbookSearchTopLock - passbookCurrentTopSafe))
                                    .ignoresSafeArea(.container, edges: .top)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                    .navigationDestination(for: PassbookActionDestination.self) { destination in
                        switch destination {
                        case .accounts:
                            AccountListView()
                        }
                    }
                    // 本棚内検索の結果から開く詳細。インライン検索なのでシートのdismiss待ちは
                    // 不要（カレンダーの同日複数冊＝D-4後日変更の回避策はシートのままなので残る）
                    .navigationDestination(item: $passbookSearchDetailBook) { book in
                        UserBookDetailView(book: book)
                    }
                    .toolbar {
                        if !customPassbooks.isEmpty, !passbookSheetChromeState.isExpanded {
                            ToolbarItem(placement: .topBarLeading) {
                                passbookSwitcherButton
                            }
                        }
                        if !passbookSheetChromeState.isExpanded {
                            // 本棚内検索の入口（R4.6・本棚タブと同じ右上）。
                            // 検索中は虫眼鏡＋設定の代わりに✕（キャンセル）を同じ位置へ出す
                            if isPassbookSearching {
                                ToolbarItem(placement: .topBarTrailing) {
                                    searchCloseToolbarButton {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPassbookSearching = false
                                        }
                                    }
                                }
                                .sharedBackgroundVisibility(.hidden)
                            } else if !customPassbooks.isEmpty {
                                ToolbarItem(placement: .topBarTrailing) {
                                    searchAndMenuToolbarPair {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPassbookSearching = true
                                        }
                                    }
                                }
                                // 標準の共有カプセル（2ボタンが1つに束ねられる）を消し、
                                // 上のHStackの間隔と個別ガラス円をそのまま見せる
                                .sharedBackgroundVisibility(.hidden)
                            } else {
                                ToolbarItem(placement: .topBarTrailing) {
                                    AppMenuButton(isPresented: appMenuPresentation)
                                }
                            }
                        }
                    }
                }
                .tabItem {
                    Label("tab.passbook", image: "icon-tab-passbook")
                }
                .tag(1)
                
                // 本棚タブ
                NavigationStack(path: $bookshelfNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else {
                            BookshelfView(passbook: displayPassbook, managesCalendarChrome: true)
                                .id("bookshelf-\(displayPassbookID)")
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if bookshelfChromeState.isCalendar {
                                Button {
                                    bookshelfChromeState.isCalendar = false
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.primary)
                                }
                            } else if !customPassbooks.isEmpty {
                                passbookSwitcherButton
                            }
                        }
                        // 本棚内検索の入口（R4.6で通帳と統一——フィルター行の虫眼鏡から移設）。
                        // 検索中は虫眼鏡＋設定の代わりに✕（キャンセル）を同じ位置へ出す。
                        // カレンダー表示中は設定ボタンのみ
                        if bookshelfChromeState.isSearching, !bookshelfChromeState.isCalendar {
                            ToolbarItem(placement: .topBarTrailing) {
                                searchCloseToolbarButton {
                                    // BookshelfView 側が onChange で拾って検索モードを終える
                                    bookshelfChromeState.isSearching = false
                                }
                            }
                            .sharedBackgroundVisibility(.hidden)
                        } else if !customPassbooks.isEmpty, !bookshelfChromeState.isCalendar {
                            ToolbarItem(placement: .topBarTrailing) {
                                searchAndMenuToolbarPair {
                                    // BookshelfView 側が onChange で拾って検索モードへ入る
                                    bookshelfChromeState.isSearching = true
                                }
                            }
                            // 通帳タブと同じく共有カプセルを消して、間隔と個別ガラス円を見せる
                            .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .topBarTrailing) {
                                AppMenuButton(isPresented: appMenuPresentation)
                            }
                        }
                    }
                }
                .tabItem {
                    Label("tab.bookshelf", image: "icon-tab-bookshelf")
                }
                .tag(2)
                
                // 集計タブ
                NavigationStack(path: $statisticsNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else {
                            StatisticsView(passbook: displayPassbook)
                                .id("statistics-\(displayPassbookID)")
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                    .toolbar {
                        if !customPassbooks.isEmpty {
                            ToolbarItem(placement: .topBarLeading) {
                                passbookSwitcherButton
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            AppMenuButton(isPresented: appMenuPresentation)
                        }
                    }
                }
                .tabItem {
                    Label("tab.statistics", image: "icon-tab-statistics")
                }
                .tag(3)
                
                // Myリストタブ
                NavigationStack(path: $readingListNavPath) {
                    ReadingListView(themeColor: currentThemeColor) {
                        selectedTab = 1
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            AppMenuButton(isPresented: appMenuPresentation)
                        }
                    }
                }
                .tabItem {
                    Label("tab.mylist", image: "icon-tab-mylist")
                }
                .tag(4)
            }
            .tint(currentThemeColor)
            
            // プラスボタン（右下に配置、タブバーの上）- リキッドグラス風
            // 口座タブ(0)、ナビゲーション中、詳細画面表示中は非表示
            // 総合口座の通帳タブ(1)では丸アクションボタンに「本の追加」があるため非表示
            // 検索モード中の通帳(1)・本棚(2)も非表示（0件画面の「本を登録する」と重複するため）
            if !isNavigating && !floatingButtonState.isHidden && selectedTab != 0 && !passbookSheetChromeState.isExpanded && !(selectedTab == 1 && isOverallMode) && !(selectedTab == 1 && isPassbookSearching) && !(selectedTab == 2 && bookshelfChromeState.isSearching) {
                HStack {
                    Spacer()
                    
                    if selectedTab == 4 {
                        // Myリストタブの場合はMenu表示
                        Menu {
                            Button(action: {
                                if readingLists.count >= 3 && !unlimitedManager.isUnlimited {
                                    showUnlimitedPaywall = true
                                } else {
                                    showAddReadingList = true
                                }
                            }) {
                                Label {
                                    Text("readinglist.create")
                                } icon: {
                                    Image("icon-tab-mylist")
                                }
                            }
                            
                            Button(action: {
                                if let targetPassbook = currentPassbook {
                                    let destination = BookSearchDestination(passbook: targetPassbook)
                                    readingListNavPath.append(destination)
                                }
                            }) {
                                Label {
                                    Text("book.register")
                                } icon: {
                                    Image("icon-tab-bookshelf")
                                }
                            }
                        } label: {
                            LiquidGlassButton(color: currentThemeColor, isBlackTheme: isBlackTheme)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 70)
                    } else {
                        // 他のタブでは従来通りの動作
                        Button(action: {
                            if let targetPassbook = currentPassbook {
                                let destination = BookSearchDestination(passbook: targetPassbook)
                                switch selectedTab {
                                case 1:
                                    passbookNavPath.append(destination)
                                case 2:
                                    bookshelfNavPath.append(destination)
                                case 3:
                                    statisticsNavPath.append(destination)
                                default:
                                    passbookNavPath.append(destination)
                                }
                            }
                        }) {
                            LiquidGlassButton(color: currentThemeColor, isBlackTheme: isBlackTheme)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 70)
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews

    /// 右上の虫眼鏡＋設定ボタンの組（通帳タブ・本棚タブ共通）。
    /// `ToolbarSpacer(.fixed)` では2カプセル間の距離を調整できないため、
    /// 1つのツールバー項目に自前のガラス円2つを並べ、間隔を自分で決める
    /// （呼び出し側で共有背景を `.sharedBackgroundVisibility(.hidden)` で消すこと）
    private func searchAndMenuToolbarPair(onSearch: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: onSearch) {
                Image("icn_search")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
            .accessibilityLabel(Text("bookshelf.search.placeholder"))

            Button(action: { appShellState.showAppMenu = true }) {
                Image("icn_setting")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())
        }
    }

    /// 検索モード中に虫眼鏡＋設定の代わりへ出す✕ボタン（検索のキャンセルと同じ動作）。
    /// ボタンを消すだけだと右へ吸い込まれる退場アニメーションになるため、
    /// 同じ位置の項目を差し替えて「その場で入れ替わる」見え方にする（2026-08-14 オーナー指示）
    private func searchCloseToolbarButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive())
        .accessibilityLabel(Text("common.cancel"))
    }

    /// 口座切り替えボタン（Menu で総合口座＋登録口座を一覧表示）
    private var passbookSwitcherButton: some View {
        Menu {
            Button {
                switchToOverall()
            } label: {
                if isOverallMode {
                    Label("account.overall", systemImage: "checkmark")
                } else {
                    Text("account.overall")
                }
            }

            ForEach(customPassbooks) { passbook in
                Button {
                    switchToPassbook(passbook)
                } label: {
                    if !isOverallMode,
                       currentPassbook?.id == passbook.id {
                        Label(passbook.name, systemImage: "checkmark")
                    } else {
                        Text(passbook.name)
                    }
                }
            }

            Divider()

            // 口座一覧（口座タブ）への導線（2026-08-13 オーナー指示）
            Button {
                selectedTab = 0
            } label: {
                Label {
                    Text("account.list.title")
                } icon: {
                    Image("icon-tab-account")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Group {
                    if isOverallMode {
                        Text("account.overall")
                    } else {
                        Text(passbookSwitcherTitle)
                    }
                }
                .font(.caption)
                .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.primary)
        }
    }

    /// 総合口座へ切り替え
    private func switchToOverall() {
        isOverallMode = true
        resetContentNavigationPaths()
    }

    /// 指定のカスタム口座へ切り替え
    private func switchToPassbook(_ passbook: PassbookDTO) {
        isOverallMode = false
        selectedPassbookId = passbook.id
        resetContentNavigationPaths()
    }

    /// 口座に依存するタブのナビゲーションをルートへ戻す
    /// （切替前の口座で開いた検索画面などが残らないようにする）。
    /// 通帳のインライン検索も同じ理由で終了する（本棚が口座切替で検索を終える挙動と一致）
    private func resetContentNavigationPaths() {
        isPassbookSearching = false
        passbookNavPath = NavigationPath()
        bookshelfNavPath = NavigationPath()
        statisticsNavPath = NavigationPath()
    }

    /// 選択中の口座が削除されていたら、選択状態を総合口座モードへ戻す
    private func validateSelectedPassbook() {
        guard let selectedId = selectedPassbookId else { return }
        let stillExists = customPassbooks.contains { $0.id == selectedId }
        if !stillExists {
            selectedPassbookId = nil
            isOverallMode = true
            resetContentNavigationPaths()
        }
    }

    /// 英語は口座名のみ、他言語は「◯◯口座」形式
    private var passbookSwitcherTitle: String {
        let name = currentPassbook?.name ?? ""
        if isEnglishDisplay {
            return name
        }
        return L10n.format("account.passbook_suffix", locale: languageManager.resolvedLocale, name)
    }

    private var isEnglishDisplay: Bool {
        switch languageManager.currentLanguage {
        case .english:
            return true
        case .system:
            return AppLanguage.inferred() == .english
        default:
            return false
        }
    }
    
    /// 空状態ビュー
    /// - Note: ストリーム初回値の受信前（起動直後の1フレーム）は表示しない。
    ///   `@Query` 時代は初回bodyからデータが入っていたため空状態が瞬かなかった挙動を維持する（設計メモ 5.1節）
    @ViewBuilder
    private var emptyStateView: some View {
        if hasLoadedPassbooks {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("account.empty")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Navigation Destination

/// 本の検索画面へのナビゲーション用データ。
/// `passbook` DTOは初回フレーム用のシード（ストリーム未到達時のフォールバック）。
/// 等価判定・ハッシュは id のみ。選択状態の解決は `BookSearchView` 側で ID 保持＋ストリーム解決する（レビュー #8）。
struct BookSearchDestination: Hashable {
    let passbook: PassbookDTO
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(passbook.id)
    }
    
    static func == (lhs: BookSearchDestination, rhs: BookSearchDestination) -> Bool {
        lhs.passbook.id == rhs.passbook.id
    }
}

/// `navigationDestination(item:)` によるプログラム的なpush（検索0件からの登録導線）で使う
extension BookSearchDestination: Identifiable {
    var id: String { passbook.id }
}

/// 通帳ページのアクションボタンからの遷移先（値ベースナビゲーション）
enum PassbookActionDestination: Hashable {
    case accounts
}

// MARK: - Preview

#Preview("Light") {
    MainTabView()
        .bookBankPreviewEnvironment()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MainTabView()
        .bookBankPreviewEnvironment()
        .preferredColorScheme(.dark)
}
