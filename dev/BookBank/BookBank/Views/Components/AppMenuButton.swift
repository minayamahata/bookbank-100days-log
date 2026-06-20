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
    /// 通貨記号用フォント（nil の場合は数字より小さめのサイズ）
    var symbolFont: Font?

    private var resolvedSymbolFont: Font {
        symbolFont ?? .caption.weight(fontWeight)
    }

    var body: some View {
        let displayCurrency = currencyManager.displayCurrency
        // 為替レート取得後に再描画して換算結果を反映する
        let _ = exchangeRates.lastUpdated
        let _ = exchangeRates.ratesFromJPY[displayCurrency.code]

        if let amount {
            let converted = exchangeRates.convert(amount, from: sourceCurrency, to: displayCurrency)
            let parts = MoneyDisplay.formatParts(
                amount: converted,
                currency: displayCurrency,
                locale: languageManager.resolvedLocale
            )

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if !parts.prefix.isEmpty {
                    Text(parts.prefix)
                        .font(resolvedSymbolFont)
                }
                Text(parts.amount)
                    .font(font)
                    .fontWeight(fontWeight)
                if !parts.suffix.isEmpty {
                    Text(parts.suffix)
                        .font(resolvedSymbolFont)
                }
            }
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
    /// 通貨記号用フォント（nil の場合は数字より小さめのサイズ）
    var symbolFont: Font?

    private var resolvedSymbolFont: Font {
        symbolFont ?? .caption.weight(fontWeight)
    }

    var body: some View {
        let _ = currencyManager.displayCurrency

        if let amount {
            let parts = MoneyDisplay.formatParts(
                amount: amount,
                currency: currencyManager.displayCurrency,
                locale: languageManager.resolvedLocale
            )

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if !parts.prefix.isEmpty {
                    Text(parts.prefix)
                        .font(resolvedSymbolFont)
                }
                Text(parts.amount)
                    .font(font)
                    .fontWeight(fontWeight)
                if !parts.suffix.isEmpty {
                    Text(parts.suffix)
                        .font(resolvedSymbolFont)
                }
            }
        }
    }
}

/// UserBook 用の価格表示
struct BookPriceText: View {
    let book: UserBook

    var font: Font = .body
    var fontWeight: Font.Weight = .regular
    var symbolFont: Font?

    var body: some View {
        FormattedPriceText(
            amount: book.priceAtRegistration,
            sourceCurrency: book.storedCurrency,
            font: font,
            fontWeight: fontWeight,
            symbolFont: symbolFont
        )
    }
}

/// 冊数表示（数字 + 小さめの単位）
struct BooksCountText: View {
    let count: Int

    @Environment(LanguageManager.self) private var languageManager

    var font: Font = .body
    var fontWeight: Font.Weight = .regular
    /// 単位用フォント（nil の場合は数字より小さめのサイズ）
    var unitFont: Font?
    var locale: Locale?

    private var resolvedLocale: Locale {
        locale ?? languageManager.resolvedLocale
    }

    private var resolvedUnitFont: Font {
        unitFont ?? .caption.weight(fontWeight)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(count.formatted())
                .font(font)
                .fontWeight(fontWeight)
            Text(L10n.string("common.books_count.unit", locale: resolvedLocale))
                .font(resolvedUnitFont)
        }
    }
}

/// 文字数表示（数字 + 小さめの単位）
struct CharacterCountText: View {
    let count: Int

    @Environment(LanguageManager.self) private var languageManager

    var font: Font = .body
    var fontWeight: Font.Weight = .regular
    var unitFont: Font?
    var locale: Locale?

    private var resolvedLocale: Locale {
        locale ?? languageManager.resolvedLocale
    }

    private var resolvedUnitFont: Font {
        unitFont ?? .caption.weight(fontWeight)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(count.formatted())
                .font(font)
                .fontWeight(fontWeight)
            Text(L10n.string("statistics.chars_unit", locale: resolvedLocale))
                .font(resolvedUnitFont)
        }
    }
}
