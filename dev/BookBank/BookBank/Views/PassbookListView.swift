//
//  PassbookListView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI

struct PassbookListView: View {
    @Environment(AppRepositories.self) private var repos
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @State private var passbooks: [PassbookDTO] = []
    @State private var allBooks: [BookDTO] = []
    @State private var showAddPassbook = false
    
    // カスタム口座を取得
    private var customPassbooks: [PassbookDTO] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }

    private func books(for passbook: PassbookDTO) -> [BookDTO] {
        allBooks.filter { $0.passbookId == passbook.id }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // カスタム口座
                Section {
                    ForEach(customPassbooks) { passbook in
                        let books = books(for: passbook)
                        NavigationLink(destination: PassbookDetailView(passbook: passbook)) {
                            PassbookRow(
                                name: passbook.name,
                                bookCount: books.count,
                                totalValue: books.totalDisplayAmount(
                                    in: currencyManager.displayCurrency,
                                    exchangeRates: exchangeRates
                                )
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
                            Text("account.add_new")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("account.title")
            .sheet(isPresented: $showAddPassbook) {
                AddPassbookView()
            }
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    passbooks = value
                }
            }
            .task {
                for await value in repos.books.observeBooks() {
                    allBooks = value
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func deletePassbooks(at offsets: IndexSet) {
        let targets = offsets.map { customPassbooks[$0] }
        Task {
            for passbook in targets {
                do {
                    try await repos.passbooks.deletePassbook(id: passbook.id)
                } catch {
                    #if DEBUG
                    print("❌ Error deleting passbook: \(error)")
                    #endif
                }
            }
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
                    .font(.app(.body))
                
                BooksCountText(count: bookCount, font: .app(.caption))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                DisplayCurrencyPriceText(amount: totalValue)
                
                Text("account.balance")
                    .font(.app(.caption2))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PassbookListView()
        .bookBankPreviewEnvironment()
}
