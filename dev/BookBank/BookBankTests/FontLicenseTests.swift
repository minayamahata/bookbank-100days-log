import Foundation
import Testing
@testable import BookBank

@MainActor
struct FontLicenseTests {
    @Test func licenseFileIsBundledAndReadable() throws {
        let bundle = AppTypography.resourceBundle
        let url = try #require(
            bundle.url(
                forResource: FontLicense.resourceName,
                withExtension: FontLicense.resourceExtension
            ),
            "LINESeed-OFL.txt がアプリバンドルに含まれている"
        )
        let text = try #require(try? String(contentsOf: url, encoding: .utf8))
        #expect(!text.isEmpty)
    }

    @Test func licenseTextContainsCopyrightAndFullOFL() throws {
        let text = try #require(FontLicense.licenseText())
        // 冒頭の著作権表示
        #expect(text.contains("© LY Corporation"))
        // OFL 1.1 の主要条項が先頭から末尾まで揃っている（原文改変なし）
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007"))
        #expect(text.contains("PREAMBLE"))
        #expect(text.contains("PERMISSION & CONDITIONS"))
        #expect(text.contains("TERMINATION"))
        #expect(text.contains("OTHER DEALINGS IN THE FONT SOFTWARE."))
    }

    @Test func fontFamiliesCoverBundledFonts() {
        // 表示する4ファミリーが同梱フォント（EN/JP/KR/TW × Regular/Bold）と対応している
        #expect(FontLicense.fontFamilies == [
            "LINE Seed Sans",
            "LINE Seed JP",
            "LINE Seed KR",
            "LINE Seed TW"
        ])
        #expect(AppTypography.bundledFonts.count == FontLicense.fontFamilies.count * 2)
    }
}
