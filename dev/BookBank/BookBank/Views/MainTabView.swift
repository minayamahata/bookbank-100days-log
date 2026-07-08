//
//  MainTabView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData

@Observable
class AppShellState {
    var showAppMenu = false
    var onPassbookSelected: ((Passbook) -> Void)?
    var onOverallSelected: (() -> Void)?
    var onShowBookshelf: (() -> Void)?
    var onShowCalendar: (() -> Void)?

    func selectPassbook(_ passbook: Passbook) {
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
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    @Query(sort: \ReadingList.updatedAt) private var readingLists: [ReadingList]
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    @State private var selectedPassbook: Passbook?
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
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// 現在表示対象の口座（selectedPassbookがnilの場合は最初のカスタム口座）
    private var currentPassbook: Passbook? {
        selectedPassbook ?? customPassbooks.first
    }
    /// 通帳・本棚・集計に渡す口座（総合口座モード時は nil）
    private var displayPassbook: Passbook? {
        isOverallMode ? nil : currentPassbook
    }
    
    /// 表示用の口座ID（View更新トリガー）
    private var displayPassbookID: String {
        if isOverallMode { return "overall" }
        return currentPassbook?.persistentModelID.hashValue.description ?? "none"
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
            .onAppear {
                appShellState.onPassbookSelected = { passbook in
                    isOverallMode = false
                    selectedPassbook = passbook
                    selectedTab = 1
                    passbookNavPath = NavigationPath()
                }
                appShellState.onOverallSelected = {
                    isOverallMode = true
                    selectedTab = 1
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
                validateSelectedPassbook()
            }
            .onChange(of: customPassbooks) {
                // 口座削除後に選択状態が削除済みモデルを参照し続けないようにする
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
                            selectedPassbook = passbook
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
                            PassbookDetailView(passbook: displayPassbook)
                                .id("passbook-\(displayPassbookID)")
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
                    .toolbar {
                        if !customPassbooks.isEmpty, !passbookSheetChromeState.isExpanded {
                            ToolbarItem(placement: .topBarLeading) {
                                passbookSwitcherButton
                            }
                        }
                        if !passbookSheetChromeState.isExpanded {
                            ToolbarItem(placement: .topBarTrailing) {
                                AppMenuButton(isPresented: appMenuPresentation)
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
                        ToolbarItem(placement: .topBarTrailing) {
                            AppMenuButton(isPresented: appMenuPresentation)
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
            if !isNavigating && !floatingButtonState.isHidden && selectedTab != 0 && !passbookSheetChromeState.isExpanded && !(selectedTab == 1 && isOverallMode) {
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
                       currentPassbook?.persistentModelID == passbook.persistentModelID {
                        Label(passbook.name, systemImage: "checkmark")
                    } else {
                        Text(passbook.name)
                    }
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
    private func switchToPassbook(_ passbook: Passbook) {
        isOverallMode = false
        selectedPassbook = passbook
        resetContentNavigationPaths()
    }

    /// 口座に依存するタブのナビゲーションをルートへ戻す
    /// （切替前の口座で開いた検索画面などが残らないようにする）
    private func resetContentNavigationPaths() {
        passbookNavPath = NavigationPath()
        bookshelfNavPath = NavigationPath()
        statisticsNavPath = NavigationPath()
    }

    /// 選択中の口座が削除されていたら、選択状態を総合口座モードへ戻す
    private func validateSelectedPassbook() {
        guard let selected = selectedPassbook else { return }
        let stillExists = customPassbooks.contains {
            $0.persistentModelID == selected.persistentModelID
        }
        if !stillExists {
            selectedPassbook = nil
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
    private var emptyStateView: some View {
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

// MARK: - Navigation Destination

/// 本の検索画面へのナビゲーション用データ
struct BookSearchDestination: Hashable {
    let passbook: Passbook
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(passbook.persistentModelID)
    }
    
    static func == (lhs: BookSearchDestination, rhs: BookSearchDestination) -> Bool {
        lhs.passbook.persistentModelID == rhs.passbook.persistentModelID
    }
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
