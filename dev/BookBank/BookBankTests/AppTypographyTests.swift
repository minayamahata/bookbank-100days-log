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
            let urls = bundle.urls(forResourcesWithExtension: font.fileExtension, subdirectory: nil) ?? []
            let matches = urls.filter { $0.lastPathComponent == "\(font.resource).\(font.fileExtension)" }
            seen[font.resource, default: 0] += matches.count
            #expect(matches.count == 1, "\(font.resource).\(font.fileExtension) が Bundle に1つだけある")
        }
        #expect(seen.count == 8)
        #expect(seen.values.allSatisfy { $0 == 1 })
        #expect(AppTypography.bundledFonts.contains { $0.resource == "LINESeedJP-Regular" })
        #expect(AppTypography.bundledFonts.contains { $0.resource == "LINESeedJP-Bold" })
        #expect(!AppTypography.bundledFonts.contains { $0.postScriptName.contains("LINESeedJPApp") })
        #expect(!AppTypography.bundledFonts.contains { $0.resource.contains("LINESeedJP_A") })
    }

    @Test func postScriptNamesCreateUIFonts() throws {
        for font in AppTypography.bundledFonts {
            let created = try #require(UIFont(name: font.postScriptName, size: 17))
            #expect(created.fontName == font.postScriptName)
        }
        let regular = try #require(UIFont(name: "LINESeedJP-Regular", size: 17))
        let bold = try #require(UIFont(name: "LINESeedJP-Bold", size: 17))
        #expect(regular.fontName == "LINESeedJP-Regular")
        #expect(bold.fontName == "LINESeedJP-Bold")
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
        #expect(AppTypography.jpRegularName == "LINESeedJP-Regular")
        #expect(AppTypography.jpBoldName == "LINESeedJP-Bold")
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

    @Test func oldWesternFontsAndAppOTFAreAbsent() {
        let bundle = AppTypography.resourceBundle
        let otfs = bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        let ttfs = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        let woffs = bundle.urls(forResourcesWithExtension: "woff", subdirectory: nil) ?? []
        let otfNames = otfs.map(\.lastPathComponent)
        let ttfNames = ttfs.map(\.lastPathComponent)
        #expect(!otfNames.contains("Inter-Regular.otf"))
        #expect(!otfNames.contains(where: { $0.localizedCaseInsensitiveContains("Fearlessly") }))
        #expect(!otfNames.contains("LINESeedJP_A_OTF_Rg.otf"))
        #expect(!otfNames.contains("LINESeedJP_A_OTF_Bd.otf"))
        #expect(ttfNames.contains("LINESeedJP-Regular.ttf"))
        #expect(ttfNames.contains("LINESeedJP-Bold.ttf"))
        #expect(ttfNames.count == 2)
        #expect(otfNames.count == 6)
        #expect(woffs.isEmpty)
    }

    @Test func japaneseLineHeightIsCompactAt17pt() {
        let regular = AppTypography.fixedUIFont(size: 17, weight: .regular, language: .japanese)
        let bold = AppTypography.fixedUIFont(size: 17, weight: .bold, language: .japanese)
        #expect(regular.fontName == AppTypography.jpRegularName)
        #expect(bold.fontName == AppTypography.jpBoldName)
        #expect(regular.lineHeight >= 18)
        #expect(regular.lineHeight <= 20.5)
        #expect(bold.lineHeight >= 18)
        #expect(bold.lineHeight <= 20.5)
        #expect(abs(regular.lineHeight - bold.lineHeight) < 1)
    }

    @Test func tightLeadingLogicIsWithdrawn() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BookBank/Utils/AppTypography.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(!text.contains("leading(.tight)"))
        #expect(!text.contains("usesTightLeading"))
        #expect(!text.contains("tight leading"))
    }

    @Test func interfaceLineSpacingIsOnePointOnlyForJapanese() {
        #expect(AppTypography.interfaceLineSpacing(for: .japanese) == 1)
        #expect(AppTypography.interfaceLineSpacing(for: .english) == 0)
        #expect(AppTypography.interfaceLineSpacing(for: .korean) == 0)
        #expect(AppTypography.interfaceLineSpacing(for: .traditionalChinese) == 0)
        #expect(AppTypography.interfaceLineSpacing(for: .simplifiedChinese) == 0)
        #expect(AppTypography.shareImageLineSpacing == 0)
        #expect(AppTypography.interfaceLineSpacing(for: .system) == AppTypography.interfaceLineSpacing(for: AppLanguage.inferred()))
        #expect(AppTypography.interfaceLineSpacing(for: AppLanguage.inferred(from: Locale(identifier: "ja"))) == 1)
        #expect(AppTypography.interfaceLineSpacing(for: AppLanguage.inferred(from: Locale(identifier: "en"))) == 0)
    }

    @Test func japaneseLineSpacingWidensTwoLinesOnly() {
        let width: CGFloat = 240
        let single = "あいうえお"
        let wrapped = "あいうえおかきくけこさしすせそたちつてとなにぬねの"
        let singleZero = measureTextHeight(single, lineSpacing: 0, width: width)
        let singleOne = measureTextHeight(single, lineSpacing: 1, width: width)
        #expect(abs(singleZero - singleOne) < 0.75)

        let twoZero = measureTextHeight(wrapped, lineSpacing: 0, width: width)
        let twoOne = measureTextHeight(wrapped, lineSpacing: 1, width: width)
        let twoTwo = measureTextHeight(wrapped, lineSpacing: 2, width: width)
        #expect(twoZero > singleZero)
        #expect(twoOne - twoZero >= 0.5)
        #expect(twoOne - twoZero <= 1.5)
        #expect(twoTwo - twoZero >= 1.5)
        #expect(twoTwo - twoZero <= 2.5)
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

    @MainActor
    private func measureTextHeight(_ text: String, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        let view = Text(text)
            .font(AppTypography.fixedFont(size: 17, language: .japanese))
            .lineSpacing(lineSpacing)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        let host = UIHostingController(rootView: view)
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: 400)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: 1000)).height
    }
}
