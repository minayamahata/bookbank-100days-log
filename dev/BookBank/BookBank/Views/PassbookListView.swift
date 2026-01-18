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
    
    // すべてのカスタム口座の合計値
    private var totalBooks: Int {
        customPassbooks.reduce(0) { $0 + $1.bookCount }
    }
    
    private var totalValue: Int {
        customPassbooks.reduce(0) { $0 + $1.totalValue }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 総合口座（仮想）
                Section {
                    NavigationLink(destination: PassbookDetailView(passbook: nil, isOverall: true)) {
                        PassbookRow(
                            name: "総合口座",
                            bookCount: totalBooks,
                            totalValue: totalValue,
                            isOverall: true
                        )
                    }
                }
                
                // カスタム口座
                Section {
                    ForEach(customPassbooks) { passbook in
                        NavigationLink(destination: PassbookDetailView(passbook: passbook, isOverall: false)) {
                            PassbookRow(
                                name: passbook.name,
                                bookCount: passbook.bookCount,
                                totalValue: passbook.totalValue,
                                isOverall: false
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
                                .foregroundColor(.blue)
                            Text("新しい口座を追加")
                                .foregroundColor(.blue)
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
            
            // 本がある場合は削除できないようにアラートを出すべきだが、
            // まずはシンプルに削除（本も一緒に削除される）
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
    let isOverall: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(isOverall ? .headline : .body)
                        .fontWeight(isOverall ? .bold : .regular)
                    
                    if isOverall {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
                
                Text("\(bookCount)冊")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("¥\(totalValue.formatted())")
                    .font(isOverall ? .headline : .body)
                    .fontWeight(isOverall ? .bold : .semibold)
                    .foregroundColor(isOverall ? .blue : .primary)
                
                if !isOverall {
                    Text("残高")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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
