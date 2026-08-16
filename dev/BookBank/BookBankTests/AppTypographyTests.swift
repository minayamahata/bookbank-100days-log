import Foundation
import SwiftUI
import Testing
import UIKit
@testable import BookBank

@MainActor
struct AppTypographyTests {
    @Test func bundledFontFilesAreEachPresentOnce() throws {
        let bundle = AppTypography.resourceBundle
        var seen: [String: Int] = [:]
        for font in AppTypography.bundledFonts {
            let urls = bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
            let matches = urls.filter { $0.lastPathComponent == "\(font.resource).otf" }
            seen[font.resource, default: 0] += matches.count
            #expect(matches.count == 1, "\(font.resource).otf が Bundle に1つだけある")
        }
        #expect(seen.count == 8)
        #expect(seen.values.allSatisfy { $0 == 1 })
    }

    @Test func postScriptNamesCreateUIFonts() throws {
        for font in AppTypography.bundledFonts {
            let created = try #require(UIFont(name: font.postScriptName, size: 17))
            #expect(created.fontName == font.postScriptName)
        }
    }

    @Test func languageSelectsExpectedPostScriptNames() {
        #expect(
            AppTypography.postScriptName(weight: .regular, language: .japanese)
                == AppTypography.jpRegularName
        )
        #expect(
            AppTypography.postScriptName(weight: .bold, language: .japanese)
                == AppTypography.jpBoldName
        )
        #expect(
            AppTypography.postScriptName(weight: .regular, language: .english)
                == AppTypography.enRegularName
        )
        #expect(
            AppTypography.postScriptName(weight: .bold, language: .english)
                == AppTypography.enBoldName
        )
        #expect(
            AppTypography.postScriptName(weight: .regular, language: .korean)
                == AppTypography.krRegularName
        )
        #expect(
            AppTypography.postScriptName(weight: .bold, language: .korean)
                == AppTypography.krBoldName
        )
        #expect(
            AppTypography.postScriptName(weight: .regular, language: .traditionalChinese)
                == AppTypography.twRegularName
        )
        #expect(
            AppTypography.postScriptName(weight: .bold, language: .traditionalChinese)
                == AppTypography.twBoldName
        )
    }

    @Test func systemSettingUsesInferredLanguage() {
        let inferred = AppLanguage.inferred()
        #expect(AppTypography.resolvedLanguage(.system) == inferred)
        #expect(
            AppTypography.postScriptName(weight: .regular, language: .system)
                == AppTypography.postScriptName(weight: .regular, language: inferred)
        )
    }

    @Test func localeInferenceSelectsEachSupportedLanguage() {
        #expect(AppTypography.language(from: Locale(identifier: "ja")) == .japanese)
        #expect(AppTypography.language(from: Locale(identifier: "en")) == .english)
        #expect(AppTypography.language(from: Locale(identifier: "ko")) == .korean)
        #expect(AppTypography.language(from: Locale(identifier: "zh-Hant")) == .traditionalChinese)
        #expect(AppTypography.language(from: Locale(identifier: "zh-Hans")) == .simplifiedChinese)
    }

    @Test func weightMappingUsesOnlyRegularAndBold() {
        #expect(AppTypography.Weight(Font.Weight.thin) == .regular)
        #expect(AppTypography.Weight(Font.Weight.light) == .regular)
        #expect(AppTypography.Weight(Font.Weight.regular) == .regular)
        #expect(AppTypography.Weight(Font.Weight.medium) == .regular)
        #expect(AppTypography.Weight(Font.Weight.semibold) == .bold)
        #expect(AppTypography.Weight(Font.Weight.bold) == .bold)
        #expect(AppTypography.Weight(Font.Weight.heavy) == .bold)
        #expect(AppTypography.Weight(Font.Weight.black) == .bold)
        #expect(AppTypography.Weight(UIFont.Weight.light) == .regular)
        #expect(AppTypography.Weight(UIFont.Weight.medium) == .regular)
        #expect(AppTypography.Weight(UIFont.Weight.semibold) == .bold)
        #expect(AppTypography.Weight(UIFont.Weight.heavy) == .bold)
        #expect(AppTypography.defaultWeight(for: Font.TextStyle.headline) == .bold)
        #expect(AppTypography.defaultWeight(for: Font.TextStyle.body) == .regular)
    }

    @Test func simplifiedChineseDoesNotUseTaiwanLineSeed() {
        let regular = AppTypography.postScriptName(weight: .regular, language: .simplifiedChinese)
        let bold = AppTypography.postScriptName(weight: .bold, language: .simplifiedChinese)
        #expect(regular == AppTypography.pingFangRegularName)
        #expect(bold == AppTypography.pingFangBoldName)
        #expect(regular != AppTypography.twRegularName)
        #expect(bold != AppTypography.twBoldName)
        let font = AppTypography.fixedUIFont(size: 17, weight: .regular, language: .simplifiedChinese)
        #expect(!font.fontName.contains("LINESeedTW"))
    }

    @Test func oldWesternFontsAndWebFontsAreAbsent() {
        let bundle = AppTypography.resourceBundle
        let otfs = bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        let ttfs = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        let woffs = bundle.urls(forResourcesWithExtension: "woff", subdirectory: nil) ?? []
        let names = otfs.map(\.lastPathComponent)
        #expect(!names.contains("Inter-Regular.otf"))
        #expect(!names.contains(where: { $0.localizedCaseInsensitiveContains("Fearlessly") }))
        #expect(ttfs.isEmpty)
        #expect(woffs.isEmpty)
        #expect(names.count == 8)
    }

    @Test func dynamicTypeIncreasesBodySize() {
        let regular = AppTypography.uiFont(
            .body,
            language: .japanese,
            contentSizeCategory: .large
        )
        let xxxl = AppTypography.uiFont(
            .body,
            language: .japanese,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        #expect(xxxl.pointSize > regular.pointSize)
    }
}
