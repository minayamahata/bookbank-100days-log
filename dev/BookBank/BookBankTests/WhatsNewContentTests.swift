import Foundation
import Testing
import UIKit
@testable import BookBank

/// 新機能のお知らせ コンテンツと画像のテスト（docs/whats-new-message-design.md 9章）
@MainActor
struct WhatsNewContentTests {
    @Test func hasExactlyFivePagesInFixedOrder() {
        let pages = WhatsNewMessage.pages
        #expect(pages.count == 5)
        #expect(pages.map(\.id) == ["01", "02", "03", "04", "05"], "順番は01〜05で固定")
    }

    @Test func pageKeysAndImageNamesMatchTheirNumbers() {
        for page in WhatsNewMessage.pages {
            #expect(page.titleKey == "whats_new.title.\(page.id)")
            #expect(page.descriptionKey == "whats_new.description.\(page.id)")
            #expect(page.imageName == "img_news-\(page.id)")
        }
    }

    @Test func allImagesLoadFromAppBundleAt900x700() throws {
        let bundle = AppTypography.resourceBundle
        for page in WhatsNewMessage.pages {
            let image = try #require(
                UIImage(named: page.imageName, in: bundle, compatibleWith: nil),
                "\(page.imageName) をアプリバンドルから読み込める"
            )
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            #expect(pixelWidth == 900, "\(page.imageName) の幅は900px")
            #expect(pixelHeight == 700, "\(page.imageName) の高さは700px")
        }
    }

    @Test func accessibilityStringsResolveInAllLanguages() {
        for identifier in ["ja", "en", "ko", "zh-Hans", "zh-Hant"] {
            let locale = Locale(identifier: identifier)

            let close = L10n.string(WhatsNewMessage.closeAccessibilityKey, locale: locale)
            #expect(!close.isEmpty)
            #expect(close != WhatsNewMessage.closeAccessibilityKey,
                    "\(identifier): 閉じるボタンのラベルが解決される")

            let page = L10n.format(
                WhatsNewMessage.pageIndicatorAccessibilityKey,
                locale: locale,
                Int64(1), Int64(4)
            )
            #expect(page.contains("1") && page.contains("4"),
                    "\(identifier): ページ番号の読み上げに現在ページと総数が入る")
            #expect(!page.contains("%lld"), "\(identifier): プレースホルダーが展開される")
        }
    }

    @Test func headerAndButtonStringsResolve() {
        let locale = Locale(identifier: "ja")
        #expect(L10n.format(WhatsNewMessage.headerKey, locale: locale, "01") == "新機能 01")
        #expect(L10n.string(WhatsNewMessage.nextKey, locale: locale) == "次へ")
        #expect(L10n.string(WhatsNewMessage.getStartedKey, locale: locale) == "はじめる")
    }
}
