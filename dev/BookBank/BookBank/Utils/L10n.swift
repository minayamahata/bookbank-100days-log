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

    private static func bundle(for locale: Locale) -> Bundle {
        var candidates: [String] = [locale.identifier]
        if #available(iOS 16, *) {
            candidates.append(locale.language.minimalIdentifier)
            if let code = locale.language.languageCode?.identifier {
                candidates.append(code)
            }
        } else {
            candidates.append(locale.identifier.prefix(2).description)
        }

        for identifier in candidates {
            if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
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
