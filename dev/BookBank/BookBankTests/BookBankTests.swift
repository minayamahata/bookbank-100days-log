//
//  BookBankTests.swift
//  BookBankTests
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import Foundation
import SwiftUI
import Testing
@testable import BookBank

struct BookBankTests {

    @Test @MainActor func exchangeRateResponseDecodesOpenERAPIFormat() throws {
        let json = """
        {"result":"success","base_code":"JPY","rates":{"JPY":1,"USD":0.0067,"KRW":9.2}}
        """.data(using: .utf8)!

        struct Wrapper: Decodable {
            let result: String
            let baseCode: String
            let rates: [String: Double]

            enum CodingKeys: String, CodingKey {
                case result
                case baseCode = "base_code"
                case rates
                case conversionRates = "conversion_rates"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                result = try container.decode(String.self, forKey: .result)
                baseCode = try container.decode(String.self, forKey: .baseCode)
                if let rates = try container.decodeIfPresent([String: Double].self, forKey: .rates) {
                    self.rates = rates
                } else if let conversionRates = try container.decodeIfPresent([String: Double].self, forKey: .conversionRates) {
                    self.rates = conversionRates
                } else {
                    throw DecodingError.keyNotFound(
                        CodingKeys.rates,
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing rates")
                    )
                }
            }
        }

        let response = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(response.rates["USD"] == 0.0067)
        #expect(response.rates["KRW"] == 9.2)
    }

    @Test func twdUsesNTDollarSymbol() {
        let parts = MoneyDisplay.formatParts(amount: 1500, currency: .twd, locale: Locale(identifier: "en_US"))
        #expect(parts.prefix == "NT$")
        #expect(parts.amount == "1,500")
    }

    @Test func cnyUsesDistinctSymbolFromJPY() {
        let jpy = MoneyDisplay.formatParts(amount: 1500, currency: .jpy, locale: Locale(identifier: "ja_JP"))
        let cny = MoneyDisplay.formatParts(amount: 1500, currency: .cny, locale: Locale(identifier: "ja_JP"))
        #expect(jpy.prefix == "¥")
        #expect(cny.prefix == "元")
        #expect(jpy.prefix != cny.prefix)
    }

    // MARK: - SearchResultDeduplicator（A-6: 追加読み込みの重複排除）

    /// テスト用の最小 RakutenBook を生成
    private func makeBook(
        title: String,
        author: String,
        isbn: String,
        salesDate: String = "2020年01月"
    ) -> RakutenBook {
        RakutenBook(
            title: title,
            author: author,
            publisherName: "テスト出版",
            isbn: isbn,
            itemPrice: nil,
            salesDate: salesDate,
            itemCaption: "",
            mediumImageUrl: nil,
            largeImageUrl: nil,
            size: nil,
            seriesName: nil,
            booksGenreId: nil
        )
    }

    @Test func dedupExcludesDuplicateISBN() {
        let existing = [makeBook(title: "A", author: "著者A", isbn: "9781111111111")]
        let incoming = [
            makeBook(title: "A（別表記）", author: "著者A", isbn: "9781111111111"), // ISBN一致→除外
            makeBook(title: "B", author: "著者B", isbn: "9782222222222")           // 新規→残る
        ]

        let result = SearchResultDeduplicator.newItems(from: incoming, notIn: existing)
        #expect(result.count == 1)
        #expect(result.first?.isbn == "9782222222222")
    }

    @Test func dedupExcludesISBNlessWithMatchingStableID() {
        // ISBN が無い本は title|author|salesDate の安定IDで判定される（A-6の核心）
        let existing = [makeBook(title: "無ISBN本", author: "著者X", isbn: "", salesDate: "2019年05月")]
        let incoming = [
            makeBook(title: "無ISBN本", author: "著者X", isbn: "", salesDate: "2019年05月") // 安定ID一致→除外
        ]

        let result = SearchResultDeduplicator.newItems(from: incoming, notIn: existing)
        #expect(result.isEmpty)
    }

    @Test func dedupKeepsISBNlessWithDifferentBibliography() {
        let existing = [makeBook(title: "無ISBN本", author: "著者X", isbn: "", salesDate: "2019年05月")]
        let incoming = [
            makeBook(title: "無ISBN本", author: "著者Y", isbn: "", salesDate: "2019年05月"), // 著者違い→残る
            makeBook(title: "無ISBN本", author: "著者X", isbn: "", salesDate: "2021年08月")  // 発売日違い→残る
        ]

        let result = SearchResultDeduplicator.newItems(from: incoming, notIn: existing)
        #expect(result.count == 2)
    }

    @Test func dedupPreservesIncomingOrder() {
        let existing = [makeBook(title: "既存", author: "著者", isbn: "9780000000000")]
        let incoming = [
            makeBook(title: "1", author: "著者", isbn: "9781000000000"),
            makeBook(title: "2", author: "著者", isbn: "9780000000000"), // 除外
            makeBook(title: "3", author: "著者", isbn: "9783000000000")
        ]

        let result = SearchResultDeduplicator.newItems(from: incoming, notIn: existing)
        #expect(result.map(\.title) == ["1", "3"])
    }

    // MARK: - SearchPagination（A-5: 累積生件数 vs 総件数でのページ継続判定）

    @Test func pagingContinuesOnThinPageUnderTotal() {
        // 薄いページ（絞り込みで表示が減った）でも、累積生件数が総件数に未達なら継続する
        #expect(SearchPagination.canLoadMore(fetchedRawCount: 30, totalCount: 100, providerHasMorePages: true))
    }

    @Test func pagingStopsWhenReachedExactTotal() {
        // 総件数ちょうどに達したら停止（末尾ページ）
        #expect(!SearchPagination.canLoadMore(fetchedRawCount: 40, totalCount: 40, providerHasMorePages: true))
    }

    @Test func pagingStopsWhenExceededTotal() {
        // 総件数を超過していたら停止（総件数超過での止まらなすぎ防止・A-8相当）
        #expect(!SearchPagination.canLoadMore(fetchedRawCount: 45, totalCount: 40, providerHasMorePages: true))
    }

    @Test func pagingStopsOneShortOfTotalOnlyIfProviderAllows() {
        // 総件数まで残り1件でも、プロバイダに次ページがなければ停止
        #expect(SearchPagination.canLoadMore(fetchedRawCount: 39, totalCount: 40, providerHasMorePages: true))
        #expect(!SearchPagination.canLoadMore(fetchedRawCount: 39, totalCount: 40, providerHasMorePages: false))
    }

    @Test func pagingFallsBackToProviderWhenTotalUnknown() {
        // 総件数が不明ならプロバイダのページ判定に委ねる
        #expect(SearchPagination.canLoadMore(fetchedRawCount: 20, totalCount: nil, providerHasMorePages: true))
        #expect(!SearchPagination.canLoadMore(fetchedRawCount: 20, totalCount: nil, providerHasMorePages: false))
    }

    @Test func pagingStopsWhenProviderHasNoMorePages() {
        // NAVER のように構造的にページングできない場合は、総件数未達でも停止
        #expect(!SearchPagination.canLoadMore(fetchedRawCount: 20, totalCount: 1000, providerHasMorePages: false))
    }

    // MARK: - Google formattedSalesDate（G-1: タイムスタンプ形式の日付解析）

    private func googleVolume(publishedDate: String?) -> GoogleVolumeInfo {
        GoogleVolumeInfo(
            title: "t",
            authors: nil,
            publisher: nil,
            publishedDate: publishedDate,
            imageLinks: nil,
            industryIdentifiers: nil
        )
    }

    @Test func googleFormattedSalesDateStripsTimestamp() {
        // "2009-05-15T00:00:00Z" のタイムスタンプ形式でも日付部分だけを使う（G-1）
        #expect(googleVolume(publishedDate: "2009-05-15T00:00:00Z").formattedSalesDate == "2009年05月15日")
    }

    @Test func googleFormattedSalesDateHandlesPlainFormats() {
        #expect(googleVolume(publishedDate: "2020-01-15").formattedSalesDate == "2020年01月15日")
        #expect(googleVolume(publishedDate: "2020-01").formattedSalesDate == "2020年01月")
        #expect(googleVolume(publishedDate: "2020").formattedSalesDate == "2020年")
        #expect(googleVolume(publishedDate: nil).formattedSalesDate == "")
    }

    // MARK: - SalesDateParser.year（G-2: JST基準での年抽出）

    @Test func salesDateYearUsesJSTBoundary() {
        // JSTの元日は Date としては UTC で前年の大晦日になる。JST基準で年を取り出せていれば 2020。
        #expect(SalesDateParser.year(from: "2020年01月01日") == 2020)
        #expect(SalesDateParser.year(from: "2019年12月31日") == 2019)
        #expect(SalesDateParser.year(from: "2012年09月07日発売") == 2012)
        #expect(SalesDateParser.year(from: "不明") == nil)
    }

    // MARK: - Color.luminance（G-6: 色空間に依存しない輝度計算）

    @Test func relativeLuminanceMatchesBT601() {
        #expect(abs(Color.relativeLuminance(red: 1, green: 1, blue: 1) - 1.0) < 0.0001)
        #expect(Color.relativeLuminance(red: 0, green: 0, blue: 0) == 0.0)
        // BT.601 の重み: 赤0.299 / 緑0.587 / 青0.114
        #expect(abs(Color.relativeLuminance(red: 1, green: 0, blue: 0) - 0.299) < 0.0001)
        #expect(abs(Color.relativeLuminance(red: 0, green: 1, blue: 0) - 0.587) < 0.0001)
        #expect(abs(Color.relativeLuminance(red: 0, green: 0, blue: 1) - 0.114) < 0.0001)
    }

    @Test @MainActor func luminanceResolvesBasicColors() {
        #expect(abs(Color.white.luminance - 1.0) < 0.01)
        #expect(Color.black.luminance < 0.01)
    }

    @Test @MainActor func luminanceResolvesDisplayP3Color() {
        // Display P3 の赤でも成分を取り出せ、既定フォールバック(0.6)に落ちないこと
        let p3Red = Color(UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))
        let value = p3Red.luminance
        #expect(value < 0.5)
        #expect(abs(value - Color.fallbackLuminance) > 0.0001)
    }

    @Test @MainActor func contrastingTextColorFollowsLuminance() {
        #expect(Color.white.contrastingTextColor == Color.black)
        #expect(Color.black.contrastingTextColor == Color.white)
    }

    // MARK: - L10n バンドル解決（G-4: アプリ内言語設定への追従）

    @Test func lprojCandidatesNormalizeUnderscoreToHyphen() {
        // Locale.identifier がアンダースコアでも .lproj 名（ハイフン）に正規化される
        #expect(L10n.lprojCandidates(for: Locale(identifier: "zh_Hant")).contains("zh-Hant"))
        #expect(L10n.lprojCandidates(for: Locale(identifier: "zh_Hans")).contains("zh-Hans"))
    }

    @Test func lprojCandidatesIncludeLanguageCodeFallback() {
        // 地域付き識別子でも言語コード単体が候補に含まれる
        #expect(L10n.lprojCandidates(for: Locale(identifier: "en_US")).contains("en"))
        #expect(L10n.lprojCandidates(for: Locale(identifier: "ko_KR")).contains("ko"))
        // 重複は除かれ順序が保たれる（先頭は元の識別子由来）
        let ja = L10n.lprojCandidates(for: Locale(identifier: "ja"))
        #expect(ja.first == "ja")
        #expect(Set(ja).count == ja.count)
    }

    @Test func bundleResolvesEachAppLanguageLproj() throws {
        // ホストにローカライズリソースがある環境でのみ検証（無い場合は素通り）
        guard Bundle.main.path(forResource: "en", ofType: "lproj") != nil else { return }
        let cases = ["ja", "en", "ko", "zh-Hans", "zh-Hant"]
        for expected in cases {
            let bundle = L10n.bundle(for: Locale(identifier: expected))
            #expect(bundle.bundlePath.hasSuffix("\(expected).lproj"))
        }
    }

    @Test func bundleFallsBackToJapaneseForUnknownLocale() throws {
        guard Bundle.main.path(forResource: "ja", ofType: "lproj") != nil else { return }
        // 未対応ロケールは端末言語依存の .main ではなく開発基準の ja へフォールバック
        let bundle = L10n.bundle(for: Locale(identifier: "xx-YY"))
        #expect(bundle.bundlePath.hasSuffix("ja.lproj"))
    }

    // MARK: - ShelfSearchMatcher（S: 本棚内検索の正規化・AND部分一致）

    @Test func shelfMatchIsCaseInsensitive() {
        #expect(ShelfSearchMatcher.matches(fields: ["Haruki Murakami"], query: "murakami"))
        #expect(ShelfSearchMatcher.matches(fields: ["Haruki Murakami"], query: "MURAKAMI"))
    }

    @Test func shelfMatchTreatsHiraganaAndKatakanaEqual() {
        // 「むらかみ」「ムラカミ」が同一書籍にヒットする
        #expect(ShelfSearchMatcher.matches(fields: ["ムラカミ"], query: "むらかみ"))
        #expect(ShelfSearchMatcher.matches(fields: ["むらかみ"], query: "ムラカミ"))
    }

    @Test func shelfMatchIsWidthInsensitive() {
        // 半角カナ・全角英数のゆれを吸収
        #expect(ShelfSearchMatcher.matches(fields: ["ハルキ"], query: "ﾊﾙｷ"))
        #expect(ShelfSearchMatcher.matches(fields: ["1Q84"], query: "１Ｑ８４"))
    }

    @Test func shelfMatchIsDiacriticInsensitive() {
        // 濁点・アクセントのゆれを吸収（可能な範囲）
        #expect(ShelfSearchMatcher.matches(fields: ["Café Society"], query: "cafe"))
    }

    @Test func shelfMatchAllTermsMustMatchAcrossFields() {
        // 複数語はAND・各語はフィールド横断のOR（タイトル＋著者）
        #expect(ShelfSearchMatcher.matches(fields: ["1Q84", "村上春樹"], query: "1q84 村上"))
        // いずれかの語がどのフィールドにも無ければ不一致
        #expect(!ShelfSearchMatcher.matches(fields: ["1Q84", "村上春樹"], query: "1q84 漱石"))
    }

    @Test func shelfMatchIsSpaceInsensitive() {
        // 著者名のスペース有無でヒットが変わらない（「東野圭吾」＝「東野 圭吾」）
        #expect(ShelfSearchMatcher.matches(fields: ["東野 圭吾"], query: "東野圭吾"))
        #expect(ShelfSearchMatcher.matches(fields: ["東野圭吾"], query: "東野 圭吾"))
        #expect(ShelfSearchMatcher.matches(fields: ["東野圭吾"], query: "東野圭吾"))
        #expect(ShelfSearchMatcher.matches(fields: ["東野 圭吾"], query: "東野 圭吾"))
    }

    @Test func shelfMatchEmptyQueryMatchesAll() {
        #expect(ShelfSearchMatcher.matches(fields: ["何か"], query: ""))
        #expect(ShelfSearchMatcher.matches(fields: ["何か"], query: "   "))
        #expect(ShelfSearchMatcher.matches(fields: ["何か"], query: "\u{3000}"))
    }

    @Test func shelfMatchIgnoresNilAndEmptyFields() {
        #expect(!ShelfSearchMatcher.matches(fields: [nil, ""], query: "abc"))
        #expect(ShelfSearchMatcher.matches(fields: [nil, "abc"], query: "abc"))
    }

    @Test func shelfMatchReturnsFalseWhenNoFieldContainsTerm() {
        #expect(!ShelfSearchMatcher.matches(fields: ["ABC"], query: "xyz"))
    }

    @Test func rakutenNoImagePlaceholderIsExcluded() {
        let placeholder = "https://thumbnail.image.rakuten.co.jp/@0_mall/book/cabinet/noimage_01.gif?_ex=200x200"
        let real = "https://thumbnail.image.rakuten.co.jp/@0_mall/book/cabinet/0247/9784839960247.jpg?_ex=200x200"

        #expect(BookCoverImageURL.isRakutenPlaceholder(placeholder))
        #expect(!BookCoverImageURL.isRakutenPlaceholder(real))
        #expect(BookCoverImageURL.isValid(placeholder) == false)
        #expect(BookCoverImageURL.isValid(real) == true)
        #expect(BookCoverImageURL.normalized(placeholder) == nil)
        #expect(BookCoverImageURL.normalized(real) == real)
    }

    // MARK: - MemoTagParser（メモタグT1: 3.2節のパース仕様）

    /// 抽出結果を正規化キーの配列で比べるための小道具
    private func tagKeys(_ text: String) -> [String] {
        MemoTagParser.parse(text).map(\.key)
    }

    @Test func memoTagExtractsTagsInOrder() {
        #expect(tagKeys("#京都 で買った #古本") == ["京都", "古本"])
        #expect(tagKeys("旅の記録\n#京都\n#奈良") == ["京都", "奈良"])
    }

    @Test func memoTagAcceptsFullwidthOpener() {
        // 日本語IMEのかな入力では全角＃が出る。ここを受けないと日本語ユーザーが打てない
        #expect(tagKeys("＃京都") == ["京都"])
        #expect(tagKeys("メモ ＃京都 と #奈良") == ["京都", "奈良"])
    }

    @Test func memoTagRequiresBoundaryBeforeOpener() {
        // 誤検出を潰すための厳しめの条件（3.2節）
        #expect(tagKeys("https://example.com/#section").isEmpty)
        #expect(tagKeys("C#の本を読んだ").isEmpty)
        #expect(tagKeys("あ#京都").isEmpty)
        // 行頭・空白・改行の直後は拾う
        #expect(tagKeys("#京都") == ["京都"])
        #expect(tagKeys("メモ #京都") == ["京都"])
        #expect(tagKeys("メモ\n#京都") == ["京都"])
        #expect(tagKeys("メモ\u{3000}#京都") == ["京都"], "全角スペースも境界として扱う")
    }

    @Test func memoTagAllowsConsecutiveTags() {
        // 連続タグは日本語圏のSNSで標準的な書き方なので、タグの直後だけ境界を復活させる
        #expect(tagKeys("#京都#奈良") == ["京都", "奈良"])
        #expect(tagKeys("#京都#奈良#大阪") == ["京都", "奈良", "大阪"])
        #expect(tagKeys("#京都 #奈良") == ["京都", "奈良"])
        // 緩和したのは「タグが成立した直後」だけで、誤検出の経路は塞がったまま
        #expect(tagKeys("https://example.com/#section").isEmpty)
        #expect(tagKeys("C#の本").isEmpty)
    }

    @Test func memoTagStopsAtNonBodyCharacters() {
        #expect(tagKeys("#京都、また行きたい") == ["京都"])
        #expect(tagKeys("#京都。") == ["京都"])
        #expect(tagKeys("#kyoto!") == ["kyoto"])
        #expect(tagKeys("#京都📚") == ["京都"], "絵文字は本体に含めない")
        #expect(tagKeys("#sci-fi") == ["sci"], "ハイフンは終端（前提2・取りこぼしは受け入れる）")
    }

    @Test func memoTagAcceptsLettersMarksNumbersAndUnderscore() {
        #expect(tagKeys("#ハードカバー") == ["ハードカバー"], "長音符は Lm なので本体に含む")
        #expect(tagKeys("#소설") == ["소설"])
        #expect(tagKeys("#科幻小説") == ["科幻小説"])
        #expect(tagKeys("#sci_fi") == ["sci_fi"])
        #expect(tagKeys("#1位") == ["1位"], "数字始まりでも文字を含めば有効（3.2節・許容で確定）")
    }

    @Test func memoTagRejectsEmptyAndDigitsOnly() {
        #expect(tagKeys("# 単体").isEmpty)
        #expect(tagKeys("##京都").isEmpty, "本体が空なら不成立。境界も復活しないので2つ目も開始記号にならない")
        #expect(tagKeys("#2026").isEmpty)
        #expect(tagKeys("#１").isEmpty, "全角数字も正規化後は数字のみ")
    }

    @Test func memoTagRejectsOverlongTagWithoutTruncating() {
        let thirty = String(repeating: "あ", count: 30)
        let thirtyOne = String(repeating: "あ", count: 31)
        #expect(tagKeys("#\(thirty)") == [thirty])
        // 切り捨てて意図と違うタグを作らない（前提3）
        #expect(tagKeys("#\(thirtyOne)").isEmpty)
        #expect(tagKeys("#\(thirtyOne) #京都") == ["京都"], "不成立のタグの後ろは通常どおり読む")
    }

    @Test func memoTagNormalizesWithNFKCAndLowercase() {
        #expect(tagKeys("#SF") == ["sf"])
        #expect(tagKeys("＃ＳＦ") == ["sf"], "全角英字はNFKCで半角へ")
        #expect(MemoTagParser.parse("#SF").first?.display == "SF", "表示は書かれたままの綴り")
    }

    @Test func memoTagDoesNotFoldKanaUnlikeShelfSearch() {
        // 前提4の確定を固定する。検索は表記ゆれを吸収するのが目的、タグはユーザーが
        // 書き分けたものを区別するのが目的なので、かな寄せは**しない**
        #expect(tagKeys("#とうきょう #トウキョウ") == ["とうきょう", "トウキョウ"])
        #expect(ShelfSearchMatcher.matches(fields: ["トウキョウ"], query: "とうきょう"))
    }

    @Test func memoTagRangeCoversOpenerAndBody() throws {
        let text = "旅の記録 #京都 で買った"
        let tag = try #require(MemoTagParser.parse(text).first)
        #expect(String(text[tag.range]) == "#京都", "ハイライト範囲は # を含む")
    }

    @Test func memoTagReturnsNothingForTextWithoutTags() {
        #expect(MemoTagParser.parse("").isEmpty)
        #expect(MemoTagParser.parse("タグのないメモ").isEmpty)
    }

}
