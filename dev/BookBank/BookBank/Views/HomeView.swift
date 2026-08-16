//
//  HomeView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI

struct HomeView: View {
    @Environment(AppRepositories.self) private var repos
    @State private var passbooks: [PassbookDTO] = []
    @State private var hasLoadedPassbooks = false
    
    // カスタム口座を取得
    private var customPassbooks: [PassbookDTO] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        Group {
            if !hasLoadedPassbooks {
                Color.clear
            } else if customPassbooks.isEmpty {
                // カスタム口座がない場合
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("account.empty")
                        .font(.app(.headline))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let firstPassbook = customPassbooks.first {
                // 最初のカスタム口座を表示
                PassbookDetailView(passbook: firstPassbook)
            }
        }
        .task {
            for await value in repos.passbooks.observePassbooks() {
                passbooks = value
                hasLoadedPassbooks = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .bookBankPreviewEnvironment()
}
