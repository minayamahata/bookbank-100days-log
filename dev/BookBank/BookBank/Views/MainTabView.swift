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
    @State private var showBookSearch = false
    @State private var showPassbookSelector = false
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 標準のTabView（通帳・本棚）
            TabView {
                // 通帳タブ
                NavigationStack {
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
                }
                .tabItem {
                    Label("通帳", systemImage: "list.bullet")
                }
                
                // 本棚タブ
                NavigationStack {
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
                }
                .tabItem {
                    Label("本棚", systemImage: "books.vertical.fill")
                }
            }
            
            // 独立した登録ボタン（右下に配置、タブバーと高さを揃える）
            if !showBookSearch {
                Button(action: {
                    // 総合口座の場合は最初のカスタム口座に登録
                    let targetPassbook = selectedPassbook ?? customPassbooks.first
                    if targetPassbook != nil {
                        showBookSearch = true
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
        .sheet(isPresented: $showBookSearch) {
            if let passbook = selectedPassbook ?? customPassbooks.first {
                NavigationStack {
                    BookSearchView(passbook: passbook, allowPassbookChange: true)
                }
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
            HStack(spacing: 4) {
                Text(selectedPassbook?.name ?? "総合口座")
                    .font(.headline)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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

#Preview {
    MainTabView()
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
