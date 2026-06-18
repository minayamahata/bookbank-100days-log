//
//  LanguageManager.swift
//  BookBank
//
//  Created on 2026/06/07
//

import Foundation

/// アプリの言語設定
enum AppLanguage: Int, CaseIterable {
    case system = 0
    case japanese = 1
    case english = 2
    case traditionalChinese = 3
    case simplifiedChinese = 4
    case korean = 5

    /// 言語ピッカー用の表示名（各言語のネイティブ表記）
    var nativeDisplayName: String {
        switch self {
        case .system: return ""
        case .japanese: return "日本語"
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "简体中文"
        case .korean: return "한국어"
        }
    }

    /// 固定 locale（system の場合は nil）
    var fixedLocale: Locale? {
        switch self {
        case .system: return nil
        case .japanese: return Locale(identifier: "ja")
        case .english: return Locale(identifier: "en")
        case .traditionalChinese: return Locale(identifier: "zh-Hant")
        case .simplifiedChinese: return Locale(identifier: "zh-Hans")
        case .korean: return Locale(identifier: "ko")
        }
    }

    /// 端末 locale から最も近い言語を推定
    static func inferred(from locale: Locale = .current) -> AppLanguage {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.contains("hant") || identifier.hasPrefix("zh-tw") || identifier.hasPrefix("zh-hk") || identifier.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("en") { return .english }
        return .japanese
    }
}

/// アプリ全体の言語を管理するクラス
@Observable
class LanguageManager {
    /// 現在の言語設定（UserDefaults に永続化）
    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: "appLanguage") != nil {
            let savedValue = UserDefaults.standard.integer(forKey: "appLanguage")
            self.currentLanguage = AppLanguage(rawValue: savedValue) ?? .system
        } else {
            self.currentLanguage = .system
        }
    }
}

// MARK: - 表示通貨

/// アプリでサポートする表示通貨（ISO 4217）
enum AppCurrency: String, CaseIterable, Identifiable {
    case jpy = "JPY"
    case usd = "USD"
    case twd = "TWD"
    case cny = "CNY"
    case krw = "KRW"

    var id: String { code }

    var code: String { rawValue }

    /// 設定画面用の表示名キー（String Catalog）
    var nameKey: String {
        switch self {
        case .jpy: return "currency.name.jpy"
        case .usd: return "currency.name.usd"
        case .twd: return "currency.name.twd"
        case .cny: return "currency.name.cny"
        case .krw: return "currency.name.krw"
        }
    }

    /// 端末 locale から初回デフォルト通貨を推定
    static func inferred(from locale: Locale = .current) -> AppCurrency {
        switch AppLanguage.inferred(from: locale) {
        case .japanese, .system:
            return .jpy
        case .english:
            return .usd
        case .traditionalChinese:
            return .twd
        case .simplifiedChinese:
            return .cny
        case .korean:
            return .krw
        }
    }

    init?(code: String?) {
        guard let code, let value = AppCurrency(rawValue: code.uppercased()) else {
            return nil
        }
        self = value
    }
}

/// アプリ全体の表示通貨を管理するクラス
@Observable
final class CurrencyManager {
    private static let storageKey = "appDisplayCurrency"

    /// 表示通貨（UserDefaults に永続化）
    var displayCurrency: AppCurrency {
        didSet {
            UserDefaults.standard.set(displayCurrency.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.storageKey),
           let currency = AppCurrency(rawValue: saved) {
            self.displayCurrency = currency
        } else {
            let inferred = AppCurrency.inferred()
            self.displayCurrency = inferred
            UserDefaults.standard.set(inferred.rawValue, forKey: Self.storageKey)
        }
    }

    /// View 外から参照する表示通貨
    static var currentDisplayCurrency: AppCurrency {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let currency = AppCurrency(rawValue: saved) {
            return currency
        }
        return AppCurrency.inferred()
    }
}

// MARK: - 価格表示

enum MoneyDisplay {
    /// 保存通貨から表示通貨へ換算してフォーマット
    @MainActor
    static func formattedPrice(
        amount: Int?,
        sourceCurrency: AppCurrency,
        displayCurrency: AppCurrency,
        exchangeRates: ExchangeRateService,
        locale: Locale
    ) -> String? {
        guard let amount else { return nil }
        let converted = exchangeRates.convert(amount, from: sourceCurrency, to: displayCurrency)
        return format(amount: converted, currency: displayCurrency, locale: locale)
    }

    static func format(amount: Int, currency: AppCurrency, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.locale = locale
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
