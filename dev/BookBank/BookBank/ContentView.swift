//
//  ContentView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import SwiftUI

/// 口座一覧画面
/// ユーザーが作成した全ての口座（通帳）を表示
struct ContentView: View {
    
    // MARK: - Environment / State
    
    @Environment(AppRepositories.self) private var repos
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @State private var passbooks: [PassbookDTO] = []
    @State private var allBooks: [BookDTO] = []

    private func books(for passbook: PassbookDTO) -> [BookDTO] {
        allBooks.filter { $0.passbookId == passbook.id }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List(passbooks) { passbook in
                let books = books(for: passbook)
                NavigationLink(destination: PassbookDetailView(passbook: passbook)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // 口座名
                            Text(passbook.name)
                                .font(.app(.headline))
                            
                            // 登録書籍数
                            BooksCountText(count: books.count, font: .app(.subheadline))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 総額
                        DisplayCurrencyPriceText(
                            amount: books.totalDisplayAmount(
                                in: currencyManager.displayCurrency,
                                exchangeRates: exchangeRates
                            ),
                            font: .app(.title3)
                        )
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("account.title")
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
}

// MARK: - Preview

#Preview {
    ContentView()
        .bookBankPreviewEnvironment()
}
