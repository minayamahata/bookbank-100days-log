//
//  MainTabView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    @State private var selectedPassbook: Passbook?
    @State private var showPassbookSelector = false
    
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
    
    /// ナビゲーション中かどうか
    private var isNavigating: Bool {
        !accountListNavPath.isEmpty || !passbookNavPath.isEmpty || !bookshelfNavPath.isEmpty || !readingListNavPath.isEmpty || !statisticsNavPath.isEmpty
    }
    
    /// 現在の口座のテーマカラー
    private var currentThemeColor: Color {
        if let passbook = currentPassbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 標準のTabView
            TabView(selection: $selectedTab) {
                // 口座一覧タブ
                NavigationStack(path: $accountListNavPath) {
                    AccountListView { passbook in
                        // 口座を選択して通帳タブに切り替え
                        selectedPassbook = passbook
                        selectedTab = 1
                    }
                }
                .tabItem {
                    Label("口座", image: "icon-tab-account")
                }
                .tag(0)
                
                // 通帳タブ
                NavigationStack(path: $passbookNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else if let passbook = currentPassbook {
                            PassbookDetailView(passbook: passbook)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                    ToolbarItem(placement: .topBarTrailing) {
                                        ThemeToggleButton()
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("通帳", image: "icon-tab-passbook")
                }
                .tag(1)
                
                // 本棚タブ
                NavigationStack(path: $bookshelfNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else if let passbook = currentPassbook {
                            BookshelfView(passbook: passbook)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                    ToolbarItem(placement: .topBarTrailing) {
                                        ThemeToggleButton()
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("本棚", image: "icon-tab-bookshelf")
                }
                .tag(2)
                
                // 集計タブ
                NavigationStack(path: $statisticsNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else {
                            StatisticsView(passbook: currentPassbook)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                    ToolbarItem(placement: .topBarTrailing) {
                                        ThemeToggleButton()
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("集計", image: "icon-tab-statistics")
                }
                .tag(3)
                
                // Myリストタブ
                NavigationStack(path: $readingListNavPath) {
                    ReadingListView()
                }
                .tabItem {
                    Label("読了リスト", systemImage: "list.bullet.rectangle")
                }
                .tag(4)
            }
            .tint(currentThemeColor)
            
            // プラスボタン（右下に配置、タブバーの上）- リキッドグラス風
            // 口座タブ(0)とMyリストタブ(4)では非表示
            if !isNavigating && selectedTab != 0 && selectedTab != 4 {
                HStack {
                    Spacer()
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
                        LiquidGlassButton(color: currentThemeColor)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 70)
                }
            }
        }
        .overlay {
            // 背景の暗幕（フェード）
            if showPassbookSelector {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showPassbookSelector = false
                        }
                    }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .leading) {
            // 左からスライドするモーダル（天地全画面）
            if showPassbookSelector {
                GeometryReader { geometry in
                    NavigationStack {
                        PassbookSelectorView(selectedPassbook: $selectedPassbook) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showPassbookSelector = false
                            }
                        }
                    }
                    .frame(width: geometry.size.width * 0.85)
                    .frame(maxHeight: .infinity)
                    .background(Color.appCardBackground)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 40,
                            topTrailingRadius: 40
                        )
                    )
                    .shadow(radius: 10)
                }
                .ignoresSafeArea()
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPassbookSelector)
    }
    
    // MARK: - Subviews
    
    /// 口座切り替えボタン
    private var passbookSwitcherButton: some View {
        Button(action: {
            showPassbookSelector = true
        }) {
            Text("\(currentPassbook?.name ?? "")口座")
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
    
    /// 空状態ビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("口座がありません")
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

#Preview {
    MainTabView()
        .environment(ThemeManager())
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
