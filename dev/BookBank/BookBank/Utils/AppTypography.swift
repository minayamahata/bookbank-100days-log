//
//  AppTypography.swift
//  BookBank
//
//  アプリが所有する文字のフォント定義（docs/typography-design.md）。
//  View は PostScript 名を直接書かず、ここを通す。
//

import SwiftUI
import UIKit

enum AppTypography {
    /// Regular / Bold の2段階。存在しないウェイトは合成しない。
    enum Weight: Equatable, Sendable {
        case regular
        case bold

        init(_ weight: Font.Weight) {
            switch weight {
            case .ultraLight, .thin, .light, .regular, .medium:
                self = .regular
            default:
                self = .bold
            }
        }

        init(_ weight: UIFont.Weight) {
            self = weight <= .medium ? .regular : .bold
        }

        var uiFontWeight: UIFont.Weight {
            self == .bold ? .bold : .regular
        }

        var fontWeight: Font.Weight {
            self == .bold ? .bold : .regular
        }
    }

    /// 実測した PostScript 名。日本語 TTF はファイル名と一致し、他言語 OTF は一致しない。
    static let jpRegularName = "LINESeedJP-Regular"
    static let jpBoldName = "LINESeedJP-Bold"
    static let enRegularName = "LINESeedSansApp-Regular"
    static let enBoldName = "LINESeedSansApp-Bold"
    static let krRegularName = "LINESeedSansKR-Regular"
    static let krBoldName = "LINESeedSansKR-Bold"
    static let twRegularName = "LINESeedTW_OTF-Regular"
    static let twBoldName = "LINESeedTW_OTF-Bold"
    static let pingFangRegularName = "PingFangSC-Regular"
    static let pingFangBoldName = "PingFangSC-Semibold"

    /// バンドルへ入れるファイル（拡張子なし）と、拡張子・PostScript 名。
    static let bundledFonts: [(resource: String, fileExtension: String, postScriptName: String)] = [
        ("LINESeedJP-Regular", "ttf", jpRegularName),
        ("LINESeedJP-Bold", "ttf", jpBoldName),
        ("LINESeedSans_A_Rg", "otf", enRegularName),
        ("LINESeedSans_A_Bd", "otf", enBoldName),
        ("LINESeedKR-Rg", "otf", krRegularName),
        ("LINESeedKR-Bd", "otf", krBoldName),
        ("LINESeedTW_OTF_Rg", "otf", twRegularName),
        ("LINESeedTW_OTF_Bd", "otf", twBoldName)
    ]

    static func language(from locale: Locale) -> AppLanguage {
        AppLanguage.inferred(from: locale)
    }

    /// `system` は実効言語へ丸める。
    static func resolvedLanguage(_ language: AppLanguage? = nil) -> AppLanguage {
        let value = language ?? AppLanguage.effective
        return value == .system ? AppLanguage.inferred() : value
    }

    /// 日本語の通常 SwiftUI 画面だけ、複数行の行間へ足す値。1行の高さは変わらない。
    static let japaneseInterfaceLineSpacing: CGFloat = 1
    /// 共有 PNG は通常 UI の行間を継承しない。
    static let shareImageLineSpacing: CGFloat = 0

    /// 通常 SwiftUI 画面の行間。`system` は実効言語へ解決してから判定する。
    static func interfaceLineSpacing(for language: AppLanguage? = nil) -> CGFloat {
        resolvedLanguage(language) == .japanese ? japaneseInterfaceLineSpacing : 0
    }

    static func defaultWeight(for style: Font.TextStyle) -> Weight {
        style == .headline ? .bold : .regular
    }

    static func defaultWeight(for style: UIFont.TextStyle) -> Weight {
        style == .headline ? .bold : .regular
    }

    static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }

    /// Dynamic Type の基準サイズ（コンテンツサイズ `.large`）。
    static func unscaledPointSize(for style: UIFont.TextStyle) -> CGFloat {
        UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
    }

    /// 実効言語に対する PostScript 名。簡体字は PingFang SC。
    static func postScriptName(weight: Weight, language: AppLanguage? = nil) -> String? {
        let resolved = resolvedLanguage(language)
        switch resolved {
        case .japanese:
            return weight == .bold ? jpBoldName : jpRegularName
        case .english, .system:
            return weight == .bold ? enBoldName : enRegularName
        case .korean:
            return weight == .bold ? krBoldName : krRegularName
        case .traditionalChinese:
            return weight == .bold ? twBoldName : twRegularName
        case .simplifiedChinese:
            return weight == .bold ? pingFangBoldName : pingFangRegularName
        }
    }

    static func font(
        _ style: Font.TextStyle,
        weight: Weight? = nil,
        language: AppLanguage? = nil
    ) -> Font {
        let resolvedWeight = weight ?? defaultWeight(for: style)
        let size = unscaledPointSize(for: uiTextStyle(for: style))
        return font(size: size, relativeTo: style, weight: resolvedWeight, language: language)
    }

    static func font(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: Weight = .regular,
        language: AppLanguage? = nil
    ) -> Font {
        if let name = registeredFontName(weight: weight, language: language) {
            return Font.custom(name, size: size, relativeTo: textStyle)
        }
        return Font.system(size: size, weight: weight.fontWeight, design: .default)
    }

    /// 共有画像など、Dynamic Type を掛けない固定サイズ。
    static func fixedFont(
        size: CGFloat,
        weight: Weight = .regular,
        language: AppLanguage
    ) -> Font {
        if let name = registeredFontName(weight: weight, language: language) {
            return Font.custom(name, size: size)
        }
        return Font.system(size: size, weight: weight.fontWeight, design: .default)
    }

    static func uiFont(
        _ style: UIFont.TextStyle,
        weight: Weight? = nil,
        language: AppLanguage? = nil,
        contentSizeCategory: UIContentSizeCategory? = nil
    ) -> UIFont {
        let resolvedWeight = weight ?? defaultWeight(for: style)
        let base = fixedUIFont(
            size: unscaledPointSize(for: style),
            weight: resolvedWeight,
            language: resolvedLanguage(language)
        )
        return scaled(base, textStyle: style, contentSizeCategory: contentSizeCategory)
    }

    static func uiFont(
        size: CGFloat,
        relativeTo textStyle: UIFont.TextStyle = .body,
        weight: Weight = .regular,
        language: AppLanguage? = nil,
        contentSizeCategory: UIContentSizeCategory? = nil
    ) -> UIFont {
        let base = fixedUIFont(
            size: size,
            weight: weight,
            language: resolvedLanguage(language)
        )
        return scaled(base, textStyle: textStyle, contentSizeCategory: contentSizeCategory)
    }

    static func fixedUIFont(
        size: CGFloat,
        weight: Weight = .regular,
        language: AppLanguage
    ) -> UIFont {
        if let name = registeredFontName(weight: weight, language: language),
           let font = UIFont(name: name, size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
    }

    /// テストとバンドル確認用。アプリ本体のバンドルを返す。
    static var resourceBundle: Bundle {
        Bundle(identifier: "ayame-inc.BookBank") ?? Bundle(for: BundleToken.self)
    }

    private static func registeredFontName(weight: Weight, language: AppLanguage?) -> String? {
        let name = postScriptName(weight: weight, language: language)
        guard let name, UIFont(name: name, size: 12) != nil else {
            return nil
        }
        return name
    }

    private static func scaled(
        _ font: UIFont,
        textStyle: UIFont.TextStyle,
        contentSizeCategory: UIContentSizeCategory?
    ) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let contentSizeCategory {
            return metrics.scaledFont(
                for: font,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            )
        }
        return metrics.scaledFont(for: font)
    }
}

private final class BundleToken: NSObject {}

extension Font {
    static func app(
        _ style: Font.TextStyle,
        weight: AppTypography.Weight? = nil,
        language: AppLanguage? = nil
    ) -> Font {
        AppTypography.font(style, weight: weight, language: language)
    }

    static func app(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: AppTypography.Weight = .regular,
        language: AppLanguage? = nil
    ) -> Font {
        AppTypography.font(size: size, relativeTo: textStyle, weight: weight, language: language)
    }

    static func appFixed(
        size: CGFloat,
        weight: AppTypography.Weight = .regular,
        language: AppLanguage
    ) -> Font {
        AppTypography.fixedFont(size: size, weight: weight, language: language)
    }
}
