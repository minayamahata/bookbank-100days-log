//
//  PassbookListView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

struct PassbookListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    @State private var showAddPassbook = false
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // カスタム口座
                Section {
                    ForEach(customPassbooks) { passbook in
                        NavigationLink(destination: PassbookDetailView(passbook: passbook)) {
                            PassbookRow(
                                name: passbook.name,
                                bookCount: passbook.bookCount,
                                totalValue: passbook.totalValue
                            )
                        }
                    }
                    .onDelete(perform: deletePassbooks)
                }
                
                // 新しい口座を追加
                Section {
                    Button(action: {
                        showAddPassbook = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.primary)
                            Text("新しい口座を追加")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("口座")
            .sheet(isPresented: $showAddPassbook) {
                AddPassbookView()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func deletePassbooks(at offsets: IndexSet) {
        for index in offsets {
            let passbook = customPassbooks[index]
            context.delete(passbook)
        }
        
        do {
            try context.save()
        } catch {
            print("❌ Error deleting passbook: \(error)")
        }
    }
}

// MARK: - PassbookRow

struct PassbookRow: View {
    let name: String
    let bookCount: Int
    let totalValue: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                
                Text("\(bookCount)冊")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(totalValue.formatted())")
                        .font(.body)
                    Text("円")
                        .font(.caption)
                }
                
                Text("残高")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    // サンプルデータ
    let manga = Passbook(name: "漫画口座", type: .custom, sortOrder: 1)
    let work = Passbook(name: "仕事用口座", type: .custom, sortOrder: 2)
    
    container.mainContext.insert(manga)
    container.mainContext.insert(work)
    
    return PassbookListView()
        .modelContainer(container)
}
