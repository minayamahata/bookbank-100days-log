//
//  L10n.swift
//  BookBank
//
//  Created on 2026/06/07
//

import Foundation

/// String Catalog のプレースホルダー付き文字列を正しく展開するヘルパー
enum L10n {
    static func format(
        _ key: String,
        locale: Locale? = nil,
        _ args: CVarArg...
    ) -> String {
        let resolved = locale ?? LanguageManager.resolvedLocaleForFormatting
        let formatString = localizedString(forKey: key, locale: resolved)
        return String(format: formatString, locale: resolved, arguments: args)
    }

    /// プレースホルダーなしの文字列を取得
    static func string(_ key: String, locale: Locale? = nil) -> String {
        let resolved = locale ?? LanguageManager.resolvedLocaleForFormatting
        return localizedString(forKey: key, locale: resolved)
    }

    private static func localizedString(forKey key: String, locale: Locale) -> String {
        let bundle = bundle(for: locale)
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 真に解決できないときのフォールバック言語（開発基準）。
    /// 端末言語依存の `.main` に落とすとアプリ内言語設定が効かないため、`ja` の lproj を使う（G-4）。
    static let fallbackLanguageCode = "ja"

    /// locale から `.lproj` 探索に使う候補識別子を優先順に生成する純関数。
    /// - Note: `Locale.identifier` はアンダースコア区切り（例: `zh_Hant`）になり得るが、
    ///   `.lproj` フォルダ名はハイフン区切り（例: `zh-Hant.lproj`）のため正規化する（G-4）。
    static func lprojCandidates(for locale: Locale) -> [String] {
        var raw: [String] = [locale.identifier]
        if #available(iOS 16, *) {
            raw.append(locale.language.minimalIdentifier)
            if let code = locale.language.languageCode?.identifier {
                if let script = locale.language.script?.identifier {
                    raw.append("\(code)-\(script)")
                }
                raw.append(code)
            }
        } else {
            raw.append(String(locale.identifier.prefix(2)))
        }

        // アンダースコアをハイフンへ正規化し、空・重複を除いて順序を保つ
        var seen = Set<String>()
        var candidates: [String] = []
        for identifier in raw {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            candidates.append(normalized)
        }
        return candidates
    }

    static func bundle(for locale: Locale) -> Bundle {
        for identifier in lprojCandidates(for: locale) {
            if let bundle = lprojBundle(named: identifier) {
                return bundle
            }
        }
        // 端末言語依存の .main には落とさず、開発基準言語の lproj へフォールバックする（G-4）
        if let fallback = lprojBundle(named: fallbackLanguageCode) {
            return fallback
        }
        return .main
    }

    private static func lprojBundle(named identifier: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
    }
}

/// 日付の表示フォーマット（言語に応じて表記を切り替える）
/// - 英語: "June 20, 2026"（英語らしい表記）
/// - それ以外（日本語・韓国語・中国語など）: "2026.06.20"
enum AppDateFormat {
    /// 表示用の日付文字列を返す
    /// - Parameter locale: 省略時はアプリの言語設定から解決
    static func display(_ date: Date, locale: Locale? = nil) -> String {
        let resolved = locale ?? LanguageManager.resolvedLocaleForFormatting
        let isEnglish = resolved.language.languageCode?.identifier == "en"

        let formatter = DateFormatter()
        if isEnglish {
            // 例: June 20, 2026
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
        } else {
            // 例: 2026.06.20
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy.MM.dd"
        }
        return formatter.string(from: date)
    }
}

extension LanguageManager {
    /// View 外（エクスポート等）でも使える locale 解決
    static var resolvedLocaleForFormatting: Locale {
        if UserDefaults.standard.object(forKey: "appLanguage") != nil {
            let savedValue = UserDefaults.standard.integer(forKey: "appLanguage")
            let language = AppLanguage(rawValue: savedValue) ?? .system
            return locale(for: language)
        }
        return locale(for: .system)
    }

    /// UI 表示に使う locale
    var resolvedLocale: Locale {
        Self.locale(for: currentLanguage)
    }

    fileprivate static func locale(for language: AppLanguage) -> Locale {
        if let fixedLocale = language.fixedLocale {
            return fixedLocale
        }
        return AppLanguage.inferred().fixedLocale ?? Locale(identifier: "ja")
    }
}
