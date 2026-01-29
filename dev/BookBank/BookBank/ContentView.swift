//
//  ContentView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import SwiftUI
import SwiftData

/// 口座一覧画面
/// ユーザーが作成した全ての口座（通帳）を表示
struct ContentView: View {
    
    // MARK: - SwiftData Query
    
    /// 全ての口座を取得（sortOrder順）
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List(passbooks) { passbook in
                NavigationLink(destination: PassbookDetailView(passbook: passbook)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // 口座名
                            Text(passbook.name)
                                .font(.headline)
                            
                            // 登録書籍数
                            Text("\(passbook.bookCount)冊")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 総額
                        HStack(alignment: .lastTextBaseline, spacing: 1) {
                            Text("\(passbook.totalValue.formatted())")
                                .font(.title3)
                            Text("円")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("読書銀行")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
