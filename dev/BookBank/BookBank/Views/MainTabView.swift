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
    @State private var passbookNavPath = NavigationPath()
    @State private var bookshelfNavPath = NavigationPath()
    @State private var statisticsNavPath = NavigationPath()
    
    /// 現在選択中のタブ
    @State private var selectedTab = 0
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 標準のTabView（通帳・本棚）
            TabView(selection: $selectedTab) {
                // 通帳タブ
                NavigationStack(path: $passbookNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else if selectedPassbook == nil {
                            // 総合口座（全体表示）
                            PassbookDetailView(passbook: nil, isOverall: true)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                }
                        } else {
                            // カスタム口座
                            PassbookDetailView(passbook: selectedPassbook, isOverall: false)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("通帳", systemImage: "list.bullet")
                }
                .tag(0)
                
                // 本棚タブ
                NavigationStack(path: $bookshelfNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else if selectedPassbook == nil {
                            // 総合口座（全体表示）
                            OverallBookshelfView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                }
                        } else {
                            // カスタム口座
                            BookshelfView(passbook: selectedPassbook!)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("本棚", systemImage: "books.vertical.fill")
                }
                .tag(1)

                // 集計タブ
                NavigationStack(path: $statisticsNavPath) {
                    Group {
                        if customPassbooks.isEmpty {
                            emptyStateView
                        } else {
                            StatisticsView(passbook: selectedPassbook)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        passbookSwitcherButton
                                    }
                                }
                        }
                    }
                    .navigationDestination(for: BookSearchDestination.self) { destination in
                        BookSearchView(passbook: destination.passbook, allowPassbookChange: true)
                    }
                }
                .tabItem {
                    Label("集計", systemImage: "chart.bar.fill")
                }
                .tag(2)
            }
            
            // 独立した登録ボタン（右下に配置、タブバーと高さを揃える）
            // ナビゲーション中は非表示
            if passbookNavPath.isEmpty && bookshelfNavPath.isEmpty && statisticsNavPath.isEmpty {
                Button(action: {
                    // 総合口座の場合は最初のカスタム口座に登録
                    if let targetPassbook = selectedPassbook ?? customPassbooks.first {
                        let destination = BookSearchDestination(passbook: targetPassbook)
                        // 現在のタブに応じてナビゲーション
                        switch selectedTab {
                        case 0:
                            passbookNavPath.append(destination)
                        case 1:
                            bookshelfNavPath.append(destination)
                        case 2:
                            statisticsNavPath.append(destination)
                        default:
                            passbookNavPath.append(destination)
                        }
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 8) // タブバーの高さと揃える
            }
        }
        .fullScreenCover(isPresented: $showPassbookSelector) {
            NavigationStack {
                PassbookSelectorView(selectedPassbook: $selectedPassbook)
            }
        }
        .onAppear {
            // 初回表示時は総合口座を表示（selectedPassbook = nil）
        }
    }
    
    // MARK: - Subviews
    
    /// 口座切り替えボタン
    private var passbookSwitcherButton: some View {
        Button(action: {
            showPassbookSelector = true
        }) {
            Text(selectedPassbook?.name ?? "総合口座")
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
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
