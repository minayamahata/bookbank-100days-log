//
//  AppMenuButton.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI

/// ナビゲーションバー用のハンバーガーメニューボタン
struct AppMenuButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
        }
        .tint(.primary)
    }
}

// MARK: - 価格表示コンポーネント

/// 表示通貨に換算した価格テキスト
struct FormattedPriceText: View {
    let amount: Int?
    let sourceCurrency: AppCurrency

    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager

    var font: Font = .body
    var fontWeight: Font.Weight = .regular

    var body: some View {
        let _ = currencyManager.displayCurrency

        if let text = MoneyDisplay.formattedPrice(
            amount: amount,
            sourceCurrency: sourceCurrency,
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        ) {
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
        }
    }
}

/// 表示通貨に換算済みの金額テキスト（合計表示用）
struct DisplayCurrencyPriceText: View {
    let amount: Int?

    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(LanguageManager.self) private var languageManager

    var font: Font = .body
    var fontWeight: Font.Weight = .regular

    var body: some View {
        let _ = currencyManager.displayCurrency

        if let amount {
            Text(MoneyDisplay.format(
                amount: amount,
                currency: currencyManager.displayCurrency,
                locale: languageManager.resolvedLocale
            ))
            .font(font)
            .fontWeight(fontWeight)
        }
    }
}

/// UserBook 用の価格表示
struct BookPriceText: View {
    let book: UserBook

    var font: Font = .body
    var fontWeight: Font.Weight = .regular

    var body: some View {
        FormattedPriceText(
            amount: book.priceAtRegistration,
            sourceCurrency: book.storedCurrency,
            font: font,
            fontWeight: fontWeight
        )
    }
}
