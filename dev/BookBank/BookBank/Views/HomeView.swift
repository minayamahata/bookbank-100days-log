//
//  HomeView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    // 総合口座を取得
    private var overallPassbook: Passbook? {
        passbooks.first { $0.type == .overall }
    }
    
    var body: some View {
        Group {
            if let passbook = overallPassbook {
                PassbookDetailView(passbook: passbook)
            } else {
                // 総合口座がない場合
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
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook.createOverall()
    container.mainContext.insert(passbook)
    
    return NavigationStack {
        HomeView()
            .modelContainer(container)
    }
}
