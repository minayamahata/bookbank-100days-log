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

    /// 通貨記号・桁区切り用 locale（UI 言語ではなく通貨に合わせる）
    var formattingLocale: Locale {
        switch self {
        case .jpy: return Locale(identifier: "ja_JP")
        case .usd: return Locale(identifier: "en_US")
        case .twd: return Locale(identifier: "zh_TW")
        case .cny: return Locale(identifier: "zh_CN")
        case .krw: return Locale(identifier: "ko_KR")
        }
    }

    /// 表示用通貨記号（NumberFormatter が UI locale で誤った記号を返すのを防ぐ）
    var displaySymbol: String {
        switch self {
        case .jpy: return "¥"
        case .usd: return "$"
        case .twd: return "NT$"
        case .cny: return "元"
        case .krw: return "₩"
        }
    }

    /// 小数桁数（例: USD/CNY は 2、JPY/KRW/TWD は 0）
    /// 金額はこの桁数に基づく「最小通貨単位（USD ならセント）」の整数で保存する
    var fractionDigits: Int {
        switch self {
        case .jpy, .twd, .krw: return 0
        case .usd, .cny: return 2
        }
    }

    /// メジャー単位 → 最小単位の倍率（10^fractionDigits）
    /// 例: USD は 100（$1 = 100 セント）、JPY は 1
    var minorUnitDivisor: Int {
        var result = 1
        for _ in 0..<fractionDigits { result *= 10 }
        return result
    }

    /// 入力文字列（メジャー単位の "12.99" など）を最小単位の整数へ変換
    /// - 小数点はロケール非依存で "." として解釈する
    func minorUnits(fromInput text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var scaled = value * Decimal(minorUnitDivisor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// 最小単位の整数を、入力欄に表示するメジャー単位の文字列へ変換
    /// 例: USD で 1299 → "12.99"、JPY で 500 → "500"
    func inputString(fromMinor minor: Int) -> String {
        guard fractionDigits > 0 else { return String(minor) }
        let value = Decimal(minor) / Decimal(minorUnitDivisor)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? String(minor)
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

    /// 金額（最小通貨単位の整数）を通貨表記の文字列へ
    static func format(amount: Int, currency: AppCurrency, locale: Locale) -> String {
        let currencyLocale = currency.formattingLocale
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.currencySymbol = currency.displaySymbol
        formatter.locale = currencyLocale
        formatter.maximumFractionDigits = currency.fractionDigits
        formatter.minimumFractionDigits = currency.fractionDigits
        let major = Decimal(amount) / Decimal(currency.minorUnitDivisor)
        return formatter.string(from: NSDecimalNumber(decimal: major)) ?? "\(currency.displaySymbol)\(amount)"
    }

    /// 通貨記号と金額を分離（記号のみ別フォントサイズにする用途）
    static func formatParts(amount: Int, currency: AppCurrency, locale: Locale) -> (prefix: String, amount: String, suffix: String) {
        let currencyLocale = currency.formattingLocale
        let major = Decimal(amount) / Decimal(currency.minorUnitDivisor)
        let majorNumber = NSDecimalNumber(decimal: major)

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencyCode = currency.code
        currencyFormatter.currencySymbol = currency.displaySymbol
        currencyFormatter.locale = currencyLocale
        currencyFormatter.maximumFractionDigits = currency.fractionDigits
        currencyFormatter.minimumFractionDigits = currency.fractionDigits

        let decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.locale = currencyLocale
        decimalFormatter.maximumFractionDigits = currency.fractionDigits
        decimalFormatter.minimumFractionDigits = currency.fractionDigits

        let amountText = decimalFormatter.string(from: majorNumber) ?? "\(major)"
        let symbol = currency.displaySymbol

        guard let fullText = currencyFormatter.string(from: majorNumber) else {
            return (symbol, amountText, "")
        }

        if fullText.hasPrefix(symbol) {
            return (symbol, amountText, "")
        }
        if fullText.hasSuffix(symbol) {
            return ("", amountText, symbol)
        }

        if fullText.hasPrefix(amountText) {
            let suffix = String(fullText.dropFirst(amountText.count)).trimmingCharacters(in: .whitespaces)
            return ("", amountText, suffix)
        }
        if fullText.hasSuffix(amountText) {
            let prefix = String(fullText.dropLast(amountText.count)).trimmingCharacters(in: .whitespaces)
            return (prefix, amountText, "")
        }

        return (symbol, amountText, "")
    }
}
