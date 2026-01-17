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
    @State private var showBookSearch = false
    
    // 総合口座を取得
    private var overallPassbook: Passbook? {
        passbooks.first { $0.type == .overall }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 標準のTabView（ホームと本棚のみ）
            TabView {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }
                
                BookshelfView()
                    .tabItem {
                        Label("本棚", systemImage: "books.vertical.fill")
                    }
            }
            
            // 独立した登録ボタン（右下に配置、タブバーと高さを揃える）
            Button(action: {
                if overallPassbook != nil {
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
        .sheet(isPresented: $showBookSearch) {
            if let passbook = overallPassbook {
                BookSearchView(passbook: passbook)
            }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
