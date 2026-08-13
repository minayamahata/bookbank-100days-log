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

    // MARK: - MemoLinkParser（メモつながりT1: 3.2節のパース仕様）

    /// 抽出結果を正規化キーの配列で比べるための小道具
    private func linkKeys(_ text: String) -> [String] {
        MemoLinkParser.parse(text).map(\.key)
    }

    @Test func memoLinkExtractsLinksInOrder() {
        #expect(linkKeys("[[京都]] で買った [[古本]]") == ["京都", "古本"])
        #expect(linkKeys("旅の記録\n[[京都]]\n[[奈良]]") == ["京都", "奈良"])
        #expect(linkKeys("[[京都]][[奈良]]") == ["京都", "奈良"], "連続もそのまま読める")
    }

    @Test func memoLinkAcceptsFullwidthAndMixedBrackets() {
        // 日本語IMEでは全角括弧が出る。開始と終了で全角半角が混ざっていてもよい（前提9）
        #expect(linkKeys("［［京都］］") == ["京都"])
        #expect(linkKeys("[［京都]］") == ["京都"])
        #expect(linkKeys("［[京都］]") == ["京都"])
        #expect(linkKeys("[[京都］］") == ["京都"])
    }

    @Test func memoLinkAllowsArbitraryContent() {
        // 中身は任意の文字列。#記法の文字種制限（L*/M*/N*/_）は [[ ]] には無い
        #expect(linkKeys("[[SF小説 ベスト10]]") == ["sf小説 ベスト10"], "空白・数字混在も可")
        #expect(linkKeys("[[貸出: 田中さん]]") == ["貸出: 田中さん"], "句読点・記号も可")
        #expect(linkKeys("[[sci-fi]]") == ["sci-fi"], "#で終端だったハイフンも可")
        #expect(linkKeys("[[📚積読]]") == ["📚積読"], "絵文字も可")
        #expect(linkKeys("[[2026]]") == ["2026"], "数字のみも可（#の誤検出対策は [[ ]] には当たらない）")
    }

    @Test func memoLinkTrimsSurroundingWhitespace() {
        // 中身に空白を許した帰結として、前後の空白は同一視のためトリムする
        #expect(linkKeys("[[ 京都 ]]") == ["京都"])
        #expect(MemoLinkParser.parse("[[ 京都 ]]").first?.display == "京都", "表示もトリム後")
    }

    @Test func memoLinkRejectsEmptyAndWhitespaceOnly() {
        #expect(linkKeys("[[]]").isEmpty)
        #expect(linkKeys("[[ ]]").isEmpty)
        #expect(linkKeys("[[\u{3000}]]").isEmpty, "全角スペースのみも空と同じ")
        #expect(linkKeys("[[]] [[京都]]") == ["京都"], "不成立の後ろは通常どおり読む")
    }

    @Test func memoLinkRejectsContentSpanningLines() {
        // 行をまたぐと表示も崩れるため不成立（3.2節）
        #expect(linkKeys("[[京都\n奈良]]").isEmpty)
        #expect(linkKeys("[[京都\n[[奈良]]") == ["奈良"], "閉じ忘れの [[ が後続行の ]] と結合しない")
    }

    @Test func memoLinkRejectsOverlongLabelWithoutTruncating() {
        let thirty = String(repeating: "あ", count: 30)
        let thirtyOne = String(repeating: "あ", count: 31)
        #expect(linkKeys("[[\(thirty)]]") == [thirty])
        // 切り捨てて意図と違うラベルを作らない（前提3）
        #expect(linkKeys("[[\(thirtyOne)]]").isEmpty)
        #expect(linkKeys("[[\(thirtyOne)]] [[京都]]") == ["京都"])
    }

    @Test func memoLinkClosesAtFirstCloserWithoutNesting() {
        // 入れ子はなく、最初の ]] で閉じる（3.2節）
        #expect(linkKeys("[[a [[b]]") == ["a [[b"])
        #expect(linkKeys("[[a]]b]]") == ["a"], "余った ]] はただの文字")
    }

    @Test func memoLinkUnclosedIsInvalid() {
        #expect(linkKeys("[[京都").isEmpty)
        #expect(linkKeys("京都]]").isEmpty)
        #expect(linkKeys("[京都]").isEmpty, "括弧1重はつながりではない")
    }

    @Test func memoLinkNormalizesWithNFKCAndLowercase() {
        #expect(linkKeys("[[SF]]") == ["sf"])
        #expect(linkKeys("［［ＳＦ］］") == ["sf"], "全角英字はNFKCで半角へ")
        #expect(MemoLinkParser.parse("[[SF]]").first?.display == "SF", "表示は書かれたままの綴り")
    }

    @Test func memoLinkDoesNotFoldKanaUnlikeShelfSearch() {
        // 前提4の確定を固定する。検索は表記ゆれを吸収するのが目的、つながりはユーザーが
        // 書き分けたものを区別するのが目的なので、かな寄せは**しない**
        #expect(linkKeys("[[とうきょう]] [[トウキョウ]]") == ["とうきょう", "トウキョウ"])
        #expect(ShelfSearchMatcher.matches(fields: ["トウキョウ"], query: "とうきょう"))
    }

    @Test func memoLinkRangeCoversBrackets() throws {
        let text = "旅の記録 [[京都]] で買った"
        let link = try #require(MemoLinkParser.parse(text).first)
        #expect(String(text[link.range]) == "[[京都]]", "記号を隠すときに置き換える範囲は [[ ]] を含む")
    }

    @Test func memoLinkReturnsNothingForTextWithoutLinks() {
        #expect(MemoLinkParser.parse("").isEmpty)
        #expect(MemoLinkParser.parse("つながりのないメモ").isEmpty)
        #expect(MemoLinkParser.parse("#京都 は旧記法なので拾わない").isEmpty)
    }

    // MARK: - 中身が空の `[[ ]]`（編集画面では記号を出さない・4.6節）

    @Test func memoLinkFindsEmptyPairsToHide() {
        // 「つなぐ」を押した直後の形。つながりとしては不成立だが、記号を隠す範囲として必要
        let text = "ああ[[]]いい"
        let pairs = MemoLinkParser.emptyPairs(in: text)
        #expect(pairs.count == 1)
        #expect(pairs.first.map { String(text[$0]) } == "[[]]")
        #expect(MemoLinkParser.emptyPairs(in: "[[ ]]").count == 1, "空白のみも空と同じ")
        #expect(MemoLinkParser.emptyPairs(in: "［［］］").count == 1, "全角も同じ")
        #expect(MemoLinkParser.emptyPairs(in: "[[京都]]").isEmpty, "成立しているつながりは対象外")
        #expect(MemoLinkParser.emptyPairs(in: "[[").isEmpty, "閉じていなければ隠さない（本文の文字）")
    }

    @Test func memoLinkRemovesEmptyPairsOnSave() {
        // 書かずに閉じたものはメモにもエクスポートにも残さない（出典ページの `p.` と同じ扱い）
        #expect(MemoLinkParser.removingEmptyPairs(from: "旅の記録 [[]]") == "旅の記録 ")
        #expect(
            MemoLinkParser.removingEmptyPairs(from: "[[]]と[[ ]]と[[京都]]") == "とと[[京都]]",
            "成立しているつながりは残す"
        )
        #expect(MemoLinkParser.removingEmptyPairs(from: "[[京都]]") == "[[京都]]")
    }

    @Test func memoLinkFindsPairEnclosingCaret() throws {
        // 括弧の中でEnterを押したときの行き先（`]]` の先）を決めるのに使う
        let text = "ああ[[京都]]いい"
        let inside = text.index(text.startIndex, offsetBy: 5) // 「京」の直後
        let pair = try #require(MemoLinkParser.enclosingPair(in: text, at: inside))
        #expect(String(text[pair]) == "[[京都]]")
        #expect(text.distance(from: text.startIndex, to: pair.upperBound) == 8)

        let outside = text.index(text.startIndex, offsetBy: 8) // `]]` の直後
        #expect(MemoLinkParser.enclosingPair(in: text, at: outside) == nil)
        // 中身が空でも括弧の中にいる（押した直後にEnterでも抜けられる）
        let empty = "[[]]"
        let caret = empty.index(empty.startIndex, offsetBy: 2)
        #expect(MemoLinkParser.enclosingPair(in: empty, at: caret) != nil)

        // 31文字超は parse と同様に不成立——囲んでいるとみなさない（アクティブが光らない）
        let thirtyOne = String(repeating: "あ", count: 31)
        let overlong = "[[\(thirtyOne)]]"
        let overlongCaret = overlong.index(overlong.startIndex, offsetBy: 4)
        #expect(MemoLinkParser.enclosingPair(in: overlong, at: overlongCaret) == nil)
        #expect(MemoActiveFormats.at(overlongCaret, in: overlong).link == false)
    }

    // MARK: - MemoIMELinkStyling（日本語IMEまわり・設計メモ 4.6節）

    /// レビューで固定する測定3点——変換中の装飾が壊れない約束
    @Test func memoIMELinkStylingKeepsTheThreeIMEContracts() {
        // 1. つながりの中では打つ前にテーマ色を決める（typingAttributes）
        #expect(MemoIMELinkStyling.prefersLinkTypingAttributes(isInsideLink: true))
        #expect(!MemoIMELinkStyling.prefersLinkTypingAttributes(isInsideLink: false))

        // 2. 変換中は全体の装飾当て直しをしない（下線を消さない）
        #expect(MemoIMELinkStyling.shouldRefreshFullDecoration(hasMarkedText: false))
        #expect(!MemoIMELinkStyling.shouldRefreshFullDecoration(hasMarkedText: true))

        // 3. 再変換中の色付けは属性を足すだけ（つながりの中のとき）
        #expect(MemoIMELinkStyling.shouldAugmentMarkedText(isInsideLink: true))
        #expect(!MemoIMELinkStyling.shouldAugmentMarkedText(isInsideLink: false))
    }

    // MARK: - MemoHiddenMarkers / MemoFormatToggle（ツールバーの当て方・設計メモ 4.5節）

    /// 隠れている記号は選択範囲から外す（**2026-08-12 オーナー報告**——引用の行頭から
    /// 選んで「つなぐ」を押すと、見えていない `> ` まで囲まれて引用が解除されていた）
    @Test func memoHiddenMarkersLeaveTheSelectionToTheVisibleCharacters() {
        func trimmed(_ text: String, _ range: ClosedRange<Int>) -> String {
            let start = text.index(text.startIndex, offsetBy: range.lowerBound)
            let end = text.index(text.startIndex, offsetBy: range.upperBound)
            return String(text[MemoHiddenMarkers.trimming(start..<end, in: text)])
        }

        // 引用行を行頭から選ぶ（`> ` が入ってしまう）
        #expect(trimmed("> 引用の行", 0...4) == "引用")
        // 太字・つながりの記号も同じ。中に挟まった記号はそのまま（まとまりごと囲みたいはず）
        #expect(trimmed("**太字**のあと", 0...4) == "太字")
        #expect(trimmed("[[京都]]の話", 0...6) == "京都")
        // 記号しか選んでいなければ空になる（囲む文字が無い＝挿入と同じ扱い）
        #expect(trimmed("> 引用の行", 0...2).isEmpty)
    }

    /// 記号を取り除いた素のテキスト（本の編集画面のメモ欄プレビューに使う）
    @Test func memoHiddenMarkersCanBeStrippedForPlainPreviews() {
        #expect(
            MemoHiddenMarkers.strippingMarkers(from: "> 引用の行\n[[京都]]で**太字**を書く")
                == "引用の行\n京都で太字を書く"
        )
        // 記号が無ければそのまま。装飾として成立していない記号（片側だけの `**` など）も残す
        #expect(MemoHiddenMarkers.strippingMarkers(from: "ふつうの本文 p.42") == "ふつうの本文 p.42")
        #expect(MemoHiddenMarkers.strippingMarkers(from: "**閉じていない") == "**閉じていない")
    }

    /// 隠れた記号に触れた削除は、1文字でも範囲でもまとまりごと（設計メモ 4.6節）
    @Test func memoHiddenMarkersBulkDeleteKeepsMarkerPairsTogether() {
        let linked = "あ[[京都]]い"
        // `[[` の1文字目だけ消そうとしてもつながり全体
        #expect(
            MemoHiddenMarkers.bulkDeletionTargets(
                covering: NSRange(location: 1, length: 1), in: linked
            ) == [NSRange(location: 1, length: 6)]
        )

        // 範囲選択が開き括弧だけを含んでも、閉じ側を残さない
        let expanded = try! #require(
            MemoHiddenMarkers.bulkDeletionTargets(
                covering: NSRange(location: 0, length: 3), in: linked
            )
        )
        #expect(expanded == [NSRange(location: 0, length: 7)], "「あ」とつながり全体")

        // 中身だけなら通常削除（記号に触れていない）
        #expect(
            MemoHiddenMarkers.bulkDeletionTargets(
                covering: NSRange(location: 3, length: 2), in: linked
            ) == nil
        )

        // 太字は開き・閉じの両方
        let boldTargets = try! #require(
            MemoHiddenMarkers.bulkDeletionTargets(
                covering: NSRange(location: 0, length: 1), in: "**太**"
            )
        )
        #expect(Set(boldTargets.map(\.location)) == Set([0, 3]))
    }

    /// キャレットは隠れた記号の中に置かない（**2026-08-12 オーナー指示**——場面ごとの
    /// 個別対応をやめ、記号をまたぐときの振る舞いを1か所で決める）
    @Test func memoHiddenMarkersKeepTheCaretOutOfTheSymbols() {
        func snapped(_ text: String, _ offset: Int) -> Int {
            MemoHiddenMarkers.caretLocation(snapping: offset, in: text)
        }

        // 行頭の `> ` は「記号の前」も見た目が同じ位置なので、どちらから来ても文字の側へ送る
        #expect(snapped("> 引用", 0) == 2)
        #expect(snapped("> 引用", 1) == 2)
        #expect(snapped("> 引用", 3) == 3)
        // `[[ ]]` と `**` は記号の中にいるときだけ送る（記号の前は前の文字との境目＝正しい位置）
        #expect(snapped("ああ[[京都]]", 2) == 2)
        #expect(snapped("ああ[[京都]]", 3) == 4)
        #expect(snapped("ああ[[京都]]", 7) == 8)
        // 括弧のあいだ（「つなぐ」「太字」を押した直後にキャレットが立つ場所）は動かさない
        #expect(snapped("[[]]", 2) == 2)
        #expect(snapped("****", 2) == 2)

        // 行頭に記号が続くときは、送り先を装飾の**外側**にする（2026-08-12 オーナー報告A——
        // `> ` を飛ばした先がそのまま `[[` の中になり、行頭がつながりの内側だった）
        #expect(snapped("> [[京都]]は", 0) == 2)
        #expect(snapped("> [[京都]]は", 3) == 2)
        #expect(snapped("> [[京都]]は", 4) == 2, "`[[` の直後（つながりの中）も行頭へ戻す")
        #expect(snapped("> [[京都]]は", 5) == 5, "ラベルの中は動かさない（書き足せる）")
        #expect(snapped("[[京都]]は", 2) == 0, "引用でなくても行頭は同じ")
        #expect(snapped("> **太字**", 4) == 2)
        // 行頭でも、空の括弧のあいだは押した直後の入力位置なので動かさない
        #expect(snapped("> [[]]", 4) == 4)
        #expect(snapped("> ****", 4) == 4)
    }

    /// 引用のまとまりの先頭でだけ、上に行を足す口を開ける（2026-08-12 オーナー報告——
    /// メモの先頭が引用だと、その上に行を足せなかった）
    @Test func memoQuoteOpensALineAboveTheBlockHead() {
        let text = "> 一行目\n> 二行目\np."
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 2, in: text) == 0)
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 0, in: text) == 0)
        // 行の途中では開けない（引用の中の改行は出典ページへの移動）
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 4, in: text) == nil)
        // まとまりの途中の行の行頭でも開けない（囲みが割れる。上へは1つ上の行から行ける）
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 8, in: text) == nil)
        // 前に普通の行がある引用でも、先頭行なら開ける
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 8, in: "ふつうの行\n> 引用") == 6)
        #expect(MemoHiddenMarkers.quoteOpening(forReturnAt: 2, in: "ふつうの行") == nil)
    }

    /// メモの末尾が引用でも、その下に書く行を必ず用意しておく（出典ページの行の下の空行）
    @Test func memoEndingWithAQuoteKeepsALineBelow() {
        #expect(MemoQuotePage.preparedForEditing("> 引用") == "> 引用\np.\n")
        #expect(MemoQuotePage.preparedForEditing("> 引用\np.42") == "> 引用\np.42\n")
    }

    /// 押すたびに付いたり外れたりする（**2026-08-12 オーナー指示**——「つなぐ」の連打で
    /// `[[]]` が入れ子になり、記号が画面に出ていた）
    @Test func memoFormatTogglesRemoveTheFormatWhenTheCaretIsInside() {
        func edited(_ text: String, at offset: Int, _ toggle: (String, Range<String.Index>) -> MemoFormatToggle.Edit) -> String {
            let caret = text.index(text.startIndex, offsetBy: offset)
            let edit = toggle(text, caret..<caret)
            var result = text
            result.replaceSubrange(edit.replaced, with: edit.text)
            return result
        }

        // つながり: 中にいれば外す。空の括弧（押した直後の形）は跡形なく消える
        #expect(edited("ああ[[京都]]いい", at: 5, MemoFormatToggle.link) == "ああ京都いい")
        #expect(edited("[[]]", at: 2, MemoFormatToggle.link).isEmpty)
        // 外にいれば従来どおり挿す
        #expect(edited("ああ", at: 2, MemoFormatToggle.link) == "ああ[[]]")
        // 太字も同じ
        #expect(edited("ああ**太字**いい", at: 5, MemoFormatToggle.bold) == "ああ太字いい")
        #expect(edited("ああ", at: 2, MemoFormatToggle.bold) == "ああ****")
        // 引用は行ごと外す。空の出典ページの行は置き場を失うので一緒に落とす
        #expect(edited("> 引用の行\np.", at: 4, MemoFormatToggle.quote) == "引用の行")
        // 数字が入っている出典ページは残す（ユーザーが打ったものを消さない）
        #expect(edited("> 引用の行\np.42", at: 4, MemoFormatToggle.quote) == "引用の行\np.42")
    }

    /// ページ番号もトグル（**2026-08-12 オーナー指示**——光っているのにもう一度押すと
    /// `p.` が重なって入っていた）。外し方は他のトグルに揃えて記号だけ、ただし
    /// 数字未入力は押し間違いなので丸ごと、出典ページの行は数字だけ落とす
    @Test func memoPageToggleRemovesTheNumberAsAWhole() {
        func toggled(_ text: String, at offset: Int) -> (text: String, caret: Int)? {
            let caret = text.index(text.startIndex, offsetBy: offset)
            guard let edit = MemoFormatToggle.page(in: text, selecting: caret..<caret)
            else { return nil }
            var result = text
            result.replaceSubrange(edit.replaced, with: edit.text)
            let start = text.distance(from: text.startIndex, to: edit.replaced.lowerBound)
            return (result, start + edit.caretOffset)
        }

        // 中にいなければ挿す（従来どおり・キャレットは `p.` の直後）
        #expect(toggled("本文", at: 2)?.text == "本文p.")
        #expect(toggled("本文", at: 2)?.caret == 4)
        // 押した直後にもう一度押せば元に戻る（押し間違いの取り消し。
        // このために**テンキー中もツールバーを畳まない**・設計メモ 4.5節）
        let inserted = try! #require(toggled("本文", at: 2))
        #expect(toggled(inserted.text, at: inserted.caret)?.text == "本文")
        // 外す側は**数字ごと消す**（2026-08-12 オーナー指示——当初は記号だけ外していたが、
        // 数字だけが本文に取り残されて意味を成さない。ページ番号は `p.` と数字で1つの意味）
        #expect(toggled("本文p.42のところ", at: 5)?.text == "本文のところ")
        #expect(toggled("本文p.42のところ", at: 5)?.caret == 2, "消した場所に置く")
        #expect(toggled("本文p.", at: 4)?.text == "本文")
        #expect(toggled("p.42", at: 4)?.text == "")
        #expect(toggled("本文\np.42", at: 7)?.text == "本文\n")
        // 出典ページの行だけは数字を落として `p.` を残す——行そのものが引用に付随して
        // 自動で足し直されるため、丸ごと消しても同じ行がすぐ戻る
        #expect(toggled("> 引用\np.83\n", at: 8)?.text == "> 引用\np.\n")
        // 英数字の直後は解析でも不成立なので挿さない（区切りを補わずボタン無効側）
        #expect(toggled("stop", at: 4) == nil)
        #expect(MemoPageMarker.canInsert(at: "stop".endIndex, in: "stop") == false)
        #expect(MemoPageMarker.canInsert(at: "本文".endIndex, in: "本文"))
    }

    /// 引用の解除は「触れている行がすべて引用のとき」だけ。一部なら付ける側の操作
    @Test func memoQuoteToggleRemovesOnlyWhenEveryTouchedLineIsQuoted() {
        let text = "> 一行目\n> 二行目\nふつうの行"
        let start = text.index(text.startIndex, offsetBy: 2)
        let end = text.index(text.startIndex, offsetBy: 10)
        let removal = try! #require(MemoQuoteInsertion.removal(in: text, selecting: start..<end))
        #expect(removal.text == "一行目\n二行目")

        // ふつうの行までかかっていれば外さない
        let overflowing = text.index(text.startIndex, offsetBy: 13)
        #expect(MemoQuoteInsertion.removal(in: text, selecting: start..<overflowing) == nil)
    }

    // MARK: - MemoActiveFormats（ツールバーのアクティブ表示・設計メモ 4.5節）

    /// キャレットの位置から「いまどの装飾の中にいるか」を出す。記号を隠したぶん、
    /// これがユーザーにとって唯一の手がかりになる（2026-08-12 オーナー指示）
    @Test func memoActiveFormatsLightUpTheFormatUnderTheCaret() {
        func formats(_ text: String, at offset: Int) -> MemoActiveFormats {
            MemoActiveFormats.at(text.index(text.startIndex, offsetBy: offset), in: text)
        }

        // つながりの中（記号の上でも中と見なす）
        #expect(formats("ああ[[京都]]いい", at: 5).link)
        #expect(formats("ああ[[京都]]いい", at: 8).link == false)
        // 太字は中身の端も中——そこで打てば太字になる
        #expect(formats("ああ**太字**いい", at: 4).bold)
        #expect(formats("ああ**太字**いい", at: 6).bold)
        #expect(formats("ああ**太字**いい", at: 10).bold == false)
        // ペアが閉じていない `**` はただの文字なので光らない
        #expect(formats("ああ**太字いい", at: 5).bold == false)
        // 引用は行単位。行のどこにいても中で、次の行へ出れば外
        #expect(formats("> 引用の行\nふつうの行", at: 4).quote)
        #expect(formats("> 引用の行\nふつうの行", at: 8).quote == false)
        // 出典ページは `p.` の直後から数字の末尾まで（続けて数字を打てる位置）
        #expect(formats("p.42", at: 4).page)
        #expect(formats("p.42", at: 0).page == false)
        // 数字がまだ無い `p.` も中——ここで押したら外れる（トグルと同じ範囲で判定する）
        #expect(formats("本文p.", at: 4).page)
        #expect(formats("stop.", at: 5).page == false, "英数字に続く `p.` はページ番号ではない")
        // つながりのラベル内は表示と同じくページ番号とみなさない（設計メモ 4.5／4.6節）
        #expect(formats("[[p.5]]", at: 4).page == false)
        #expect(formats("[[p.5]]", at: 4).link)
        let inside = "[[p.5]]".index("[[p.5]]".startIndex, offsetBy: 4)
        #expect(
            MemoFormatToggle.page(in: "[[p.5]]", selecting: inside..<inside) == nil,
            "アクティブが消えているのにトグルだけページとして外す／挿す、が起きない"
        )
    }

    /// 装飾は重なる（引用の中のつながり・太字）。光るボタンも重なってよい
    @Test func memoActiveFormatsOverlapInsideAQuote() {
        let text = "> [[京都]]の**話**\np.42"
        func formats(at offset: Int) -> MemoActiveFormats {
            MemoActiveFormats.at(text.index(text.startIndex, offsetBy: offset), in: text)
        }

        let inLink = formats(at: 5)
        #expect(inLink.link && inLink.quote)
        let inBold = formats(at: 12)
        #expect(inBold.bold && inBold.quote)
        #expect(inBold.link == false)
        // 出典ページの行は引用の囲みの外（別の行として扱う）
        let inPage = formats(at: text.count)
        #expect(inPage.page && !inPage.quote)
    }

    // MARK: - MemoLinkIndex（本棚の絞り込みの土台・ステップ8'）

    /// 集計に必要なのは `id` と `memo` だけなので、他は既定値で埋める
    private func sampleLinkedBook(id: String, memo: String?) -> BookDTO {
        let now = Date()
        return BookDTO(
            id: id,
            title: "本\(id)",
            source: .manual,
            memo: memo,
            isFavorite: false,
            registeredAt: now,
            createdAt: now,
            updatedAt: now,
            hasCoverImage: false
        )
    }

    @Test func memoLinkIndexAggregatesLinksByBookCount() {
        let books = [
            sampleLinkedBook(id: "1", memo: "[[京都]] [[古本]]"),
            sampleLinkedBook(id: "2", memo: "[[京都]]"),
            sampleLinkedBook(id: "3", memo: "[[奈良]]"),
            sampleLinkedBook(id: "4", memo: nil)
        ]
        let index = MemoLinkIndex.build(from: books)

        #expect(index.links.map(\.key) == ["京都", "古本", "奈良"], "使う本の多い順、同数なら綴り順")
        #expect(index.links.first?.bookCount == 2)
    }

    @Test func memoLinkIndexCountsEachBookOnce() {
        let index = MemoLinkIndex.build(from: [sampleLinkedBook(id: "1", memo: "[[京都]] また [[京都]]")])
        #expect(index.links.map(\.bookCount) == [1], "同じ本に2回書いても1冊")
    }

    @Test func memoLinkIndexPicksMostWrittenSpelling() {
        let books = [
            sampleLinkedBook(id: "1", memo: "[[SF]]"),
            sampleLinkedBook(id: "2", memo: "[[SF]]"),
            sampleLinkedBook(id: "3", memo: "[[sf]]")
        ]
        let index = MemoLinkIndex.build(from: books)
        #expect(index.links.map(\.key) == ["sf"], "大小文字は同じつながり")
        #expect(index.links.first?.display == "SF", "表示は最も多く書かれた綴り")
    }

    @Test func memoLinkIndexKeepsSpellingVariantsApart() {
        // 表記ゆれは吸収しない（前提4）。絞り込みのチップに「京都」と「きょうと」が
        // 別々に並ぶことが、ユーザーがゆれに気づく場所になる（2026-08-12 オーナー確定・4.1節）
        let books = [
            sampleLinkedBook(id: "1", memo: "[[京都]]"),
            sampleLinkedBook(id: "2", memo: "[[きょうと]]")
        ]
        let index = MemoLinkIndex.build(from: books)
        #expect(index.links.map(\.key) == ["きょうと", "京都"], "同数なら綴り順に並ぶ")
    }

    @Test func memoLinkIndexReturnsBookIdsForFiltering() {
        let books = [
            sampleLinkedBook(id: "1", memo: "[[京都]] [[古本]]"),
            sampleLinkedBook(id: "2", memo: "[[京都]]"),
            sampleLinkedBook(id: "3", memo: "[[奈良]]")
        ]
        let index = MemoLinkIndex.build(from: books)

        #expect(index.bookIds(for: "京都") == ["1", "2"])
        #expect(index.bookIds(for: "存在しない") == [], "未知のキーは空")
    }

    @Test func memoLinkIndexMatchesQueryPartially() {
        // 検索語との一致は部分一致＋本棚内検索と同じ正規化（2026-08-12 オーナー確定）。
        // かな寄せで [[きょうと]] と [[キョウト]] が「きょうと」の両方に出るのは意図した挙動で、
        // 表記ゆれに気づく機会にもなる（つながりの同一性＝NFKC・かな寄せなしには触れない）
        let books = [
            sampleLinkedBook(id: "1", memo: "[[仕事]] [[仕事術]]"),
            sampleLinkedBook(id: "2", memo: "[[仕事]] [[きょうと]]"),
            sampleLinkedBook(id: "3", memo: "[[キョウト]]")
        ]
        let index = MemoLinkIndex.build(from: books)

        #expect(index.links(matching: "仕").map(\.key) == ["仕事", "仕事術"], "部分一致・多い順のまま")
        #expect(index.links(matching: "きょうと").map(\.key) == ["きょうと", "キョウト"], "かな寄せで両方見つかる")
        #expect(index.links(matching: "奈良").isEmpty, "一致なしは空")
        #expect(index.links(matching: "").map(\.key) == index.links.map(\.key), "空クエリは全件（入力前の一覧）")
    }

    @Test func memoLinkTextPrefersLinkAppearanceOverBold() throws {
        // 太字と重なってもつながりの見た目を優先（設計メモ 4.6節・2026-08-12 確定）
        let bold = Font.body.weight(MemoLinkText.boldWeight)
        let attributed = MemoLinkText.highlighted("**[[京都]]**", color: .blue, boldFont: bold)
        #expect(String(attributed.characters) == "京都")

        let run = try #require(attributed.runs.first)
        #expect(run.foregroundColor == .blue)
        #expect(run.font == Font.subheadline.weight(.semibold))
        #expect(run.font != bold, "太字の heavy よりつながりのセミボールドが勝つ")
    }

    @Test func memoLinkHighlightHidesBracketsAndKeepsRestIntact() {
        // 記号を隠すため表示文字列は原文と一致しない。不変条件は
        // 「解釈対象の記号以外の文字は一切加工しない」（設計メモ 4.6節）
        let cases: [(memo: String, rendered: String)] = [
            ("[[京都]] で買った古本", "京都 で買った古本"),
            ("つながりのないメモ", "つながりのないメモ"),
            ("[[京都]][[奈良]]", "京都奈良"),
            ("[[ 京都 ]]閉店", "京都閉店"),
            ("閉じ忘れ [[京都", "閉じ忘れ [[京都")
        ]
        for (memo, rendered) in cases {
            let attributed = MemoLinkText.highlighted(memo, color: .blue)
            #expect(String(attributed.characters) == rendered)
        }
    }

    @Test func memoLinkTextRendersBoldPairHidingMarkers() throws {
        // 太字は標準の太字より一段太いフォントを当てる（設計メモ 4.6節）
        let bold = Font.body.weight(MemoLinkText.boldWeight)
        let attributed = MemoLinkText.highlighted("**大事** なメモ", color: .blue, boldFont: bold)
        #expect(String(attributed.characters) == "大事 なメモ")

        let boldRuns = attributed.runs.filter { $0.font == bold }
        let boldRun = try #require(boldRuns.first)
        #expect(boldRuns.count == 1)
        #expect(String(attributed.characters[boldRun.range]) == "大事")
    }

    @Test func memoLinkTextLeavesUnpairedOrSpanningBoldMarkersAsLiterals() {
        // ペアが同じ行で閉じているときだけ太字。閉じない ** はただの文字として出す
        let bold = Font.body.weight(MemoLinkText.boldWeight)
        for memo in ["**閉じていない", "行を **またぐ\n太字** は解釈しない"] {
            let attributed = MemoLinkText.highlighted(memo, color: .blue, boldFont: bold)
            #expect(String(attributed.characters) == memo)
            #expect(!attributed.runs.contains { $0.font == bold })
        }
    }

    @Test func memoTextBlocksWrapQuoteLinesIntoBlocks() {
        // 行頭の `> `（ツールバーが挿入する形）だけを引用ブロックにする。
        // 表示は記号や縦線ではなく囲み（薄いグレー背景）——記号は一般ユーザーに伝わらない
        #expect(
            MemoTextBlocks.parse("> 引用したい一文\nふつうの行")
                == [.quote("引用したい一文"), .paragraph("ふつうの行")]
        )
        #expect(
            MemoTextBlocks.parse("> 1行目\n> 2行目") == [.quote("1行目\n2行目")],
            "連続する引用行はひとつの囲みにまとめる"
        )
        // `>` 単独・空白なし・行の途中は解釈しない
        #expect(
            MemoTextBlocks.parse(">空白なし\n文中の > は引用ではない")
                == [.paragraph(">空白なし\n文中の > は引用ではない")]
        )
    }

    @Test func memoQuoteBlockRangesMergeConsecutiveLines() {
        // 編集画面は囲みを自前で描くため、まとまりの文字範囲が要る（設計メモ 4.6節）
        let memo = "まえがき\n> 1行目\n> 2行目\nあとがき\n> 別のまとまり"
        let ranges = MemoTextBlocks.quoteBlockRanges(in: memo)
        let quoted = ranges.map { (memo as NSString).substring(with: $0) }

        #expect(quoted == ["> 1行目\n> 2行目", "> 別のまとまり"])
        #expect(
            MemoTextBlocks.quoteBlockRanges(in: "引用のない本文").isEmpty,
            "引用行が無ければ囲みは描かない"
        )
    }

    @Test func memoQuotePageLineBelongsToThePrecedingQuote() {
        // 引用には必ず出典ページがあるという前提で、囲みの直後の行に `p.42` だけを置く形にした。
        // 表示は囲みの枠外・右下（設計メモ 4.6節）
        #expect(
            MemoTextBlocks.parse("> 引用したい一文\np.42\n続きの本文")
                == [.quote("引用したい一文"), .quotePage("42"), .paragraph("続きの本文")]
        )
        #expect(
            MemoTextBlocks.parse("> 引用\np.") == [.quote("引用"), .quotePage("")],
            "数字が未入力の行も引用に属する（案内を出すため）"
        )
        #expect(
            MemoTextBlocks.parse("p.42\n> 引用") == [.paragraph("p.42"), .quote("引用")],
            "引用の直後でなければただの本文"
        )
        #expect(
            MemoTextBlocks.parse("> 引用\np.42ページ")
                == [.quote("引用"), .paragraph("p.42ページ")],
            "ページ番号だけの行でなければただの本文"
        )

        let memo = "> 引用\np.\nあとがき"
        let ranges = MemoTextBlocks.quotePageLineRanges(in: memo)
        #expect(ranges.map { (memo as NSString).substring(with: $0) } == ["p."])
    }

    /// 「引用」ボタンの差分。無選択の経路でページ行を足し忘れて実機で案内が出なかったので、
    /// 両方の経路をここで固定する
    @Test func memoQuoteButtonAddsThePageLineOnEveryPath() {
        func quoting(_ text: String, from: Int, to: Int) -> String {
            let lower = text.index(text.startIndex, offsetBy: from)
            let upper = text.index(text.startIndex, offsetBy: to)
            let result = MemoQuoteInsertion.make(in: text, selecting: lower..<upper)
            var applied = text
            applied.replaceSubrange(result.replaced, with: result.text)
            return applied
        }

        // 無選択（キャレットだけ）——行まるごとが引用になり、直後にページ行ができる
        #expect(quoting("引用したい一文", from: 3, to: 3) == "> 引用したい一文\np.")
        #expect(quoting("まえの行\n引用\nあとの行", from: 5, to: 5) == "まえの行\n> 引用\np.\nあとの行")
        // 行の一部を選択——その部分だけを切り出して引用にし、ページ行を挟む
        #expect(quoting("まえ引用あと", from: 2, to: 4) == "まえ\n> 引用\np.\nあと")
        // 複数行の選択——ひとつの囲みにまとめ、ページ行はまとまりの後ろに1つだけ
        #expect(quoting("1行目\n2行目", from: 0, to: 7) == "> 1行目\n> 2行目\np.")
        // すでにページ行がある引用には足さない（重複させない）
        #expect(quoting("> 引用\np.42\n本文", from: 8, to: 8) == "> 引用\n> p.42\np.\n本文")
        #expect(quoting("引用\np.42", from: 1, to: 1) == "> 引用\np.42")

        // キャレットは引用した文字の末尾＝ページ行の手前に残る
        let single = "引用したい一文"
        let caret = single.index(single.startIndex, offsetBy: 3)
        let result = MemoQuoteInsertion.make(in: single, selecting: caret..<caret)
        #expect(result.caretOffset == 5, "行頭に足した `> ` のぶんだけ後ろへ動く")
    }

    /// 案内の行は文字が幅ゼロなので、触った位置によっては `p` の手前にキャレットが入る。
    /// そのまま数字を打つと「21p.」の順になり、ページの行として成立しなくなった（実機で発覚）
    @Test func memoQuotePageKeepsTheCaretAfterTheMarker() {
        let text = "> 引用\np."          // `p.` は 5〜6 文字目
        #expect(MemoQuotePage.caretLocation(snapping: 5, in: text) == 7, "行頭に触っても数字の位置へ")
        #expect(MemoQuotePage.caretLocation(snapping: 6, in: text) == 7, "`p` と `.` のあいだも同じ")
        #expect(MemoQuotePage.caretLocation(snapping: 7, in: text) == 7, "すでに数字の位置なら動かさない")
        #expect(MemoQuotePage.caretLocation(snapping: 2, in: text) == 2, "引用の中は触らない")

        let filled = "> 引用\np.21"
        #expect(
            MemoQuotePage.caretLocation(snapping: 5, in: filled) == 7,
            "入力済みの行でも数字より前には入れない（`3p.21` のように壊れる）"
        )
        #expect(MemoQuotePage.caretLocation(snapping: 9, in: filled) == 9, "数字のあいだは自由に動ける")
        #expect(
            MemoQuotePage.caretLocation(snapping: 1, in: "p.42\n本文") == 1,
            "引用に属さない `p.42` はただの本文なので触らない"
        )
    }

    /// ツールバーの「書式クリア」。装飾は全部外す——ページ番号は数字ごと落とす
    /// （2026-08-11 オーナー指示。数字を残すと装飾が消えないため）
    @Test func memoPlainTextStripsEveryDecoration() {
        #expect(MemoPlainText.stripped(from: "**太い**ところ") == "太いところ")
        #expect(MemoPlainText.stripped(from: "[[つながり]] のメモ") == "つながり のメモ")
        #expect(
            MemoPlainText.stripped(from: "> 引用の一文\np.42\n本文") == "引用の一文\n本文",
            "ページ番号だけの行は行ごと落とす（空行を残さない）"
        )
        #expect(MemoPlainText.stripped(from: "本文\np.42") == "本文", "末尾の行なら手前の改行ごと")
        #expect(
            MemoPlainText.stripped(from: "ここ p.42 から") == "ここ  から",
            "文中のページ番号はその部分だけ（前後の空白はユーザーの文字なので触らない）"
        )
        #expect(
            MemoPlainText.stripped(from: "> 引用\np.\n本文") == "引用\n本文",
            "数字が入っていないページ行も落とす"
        )
        #expect(
            MemoPlainText.stripped(from: "> **太字**と[[つながり]]\n> 2行目")
                == "太字とつながり\n2行目",
            "入れ子も一度で外れる"
        )
        // ペアになっていない記号・不成立のつながりは触らない（本文の文字として残す）
        #expect(MemoPlainText.stripped(from: "**片方だけ") == "**片方だけ")
        #expect(MemoPlainText.stripped(from: "[[閉じていない") == "[[閉じていない")
        #expect(MemoPlainText.stripped(from: "装飾のないメモ") == "装飾のないメモ")
    }

    @Test func memoQuotePageDropsTheLineWhenNoPageWasEntered() {
        // ページの入力は任意。書かなかった `p.` を残すとメモ本文と書き出しに滲み出る
        #expect(
            MemoQuotePage.removingEmptyPageLines(from: "> 引用\np.\nあとがき") == "> 引用\nあとがき"
        )
        #expect(
            MemoQuotePage.removingEmptyPageLines(from: "> 引用\np.42") == "> 引用\np.42",
            "入力されたページは残す"
        )
        #expect(
            MemoQuotePage.removingEmptyPageLines(from: "p.\n本文") == "p.\n本文",
            "引用の直後でない `p.` はユーザーが書いた文字なので触らない"
        )
    }

    /// 編集画面は引用に出典ページの行を用意し続ける（2026-08-11 オーナー指示）——
    /// 一度消すと入力する場所そのものが無くなるため
    @Test func memoQuotePageIsRestoredWheneverItIsMissing() {
        #expect(
            MemoQuotePage.ensuringPageLines(in: "> 引用\nあとがき") == "> 引用\np.\nあとがき",
            "消された（あるいは最初から無い）引用にも案内を出す"
        )
        #expect(
            MemoQuotePage.ensuringPageLines(in: "> 引用") == "> 引用\np.",
            "引用が本文の末尾にある場合も足す"
        )
        #expect(
            MemoQuotePage.ensuringPageLines(in: "> 一行目\n> 二行目") == "> 一行目\n> 二行目\np.",
            "続く引用はひとつのまとまりなので、行ごとには足さない"
        )
        #expect(
            MemoQuotePage.ensuringPageLines(in: "> 引用\np.42") == "> 引用\np.42", "あるものは触らない"
        )
        #expect(
            MemoQuotePage.ensuringPageLines(in: "> 前\np.\n本文\n> 後") == "> 前\np.\n本文\n> 後\np.",
            "足りない引用にだけ足す"
        )
        #expect(MemoQuotePage.ensuringPageLines(in: "引用ではない本文") == "引用ではない本文")

        // キャレットをずらす量の計算に使うので、挿す位置（引用の行末＝改行の手前）も固定する
        #expect(MemoQuotePage.pageLineInsertions(in: "> 引用\nあとがき") == [4])
    }

    /// ページ行が本文の末尾にあると、キャレットが `p.` の後ろへ押し戻されるうえ、
    /// テンキーには改行キーも文字へ戻る鍵も無いので先へ進めない（2026-08-11 オーナー指摘）。
    /// 行き先の行を用意しておくことを固定する
    @Test func memoQuotePageLeavesARowToMoveOnTo() {
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "> 引用\np.42") == 9, "末尾なら足す位置を返す")
        #expect(
            MemoQuotePage.trailingBlankLineInsertion(in: "> 引用\np.42\nあとがき") == nil,
            "続きがあるなら足さない"
        )
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "ふつうの本文") == nil)

        // 文中のページ番号でも、末尾にあるなら行き先を用意する（2026-08-12 オーナー報告——
        // 末尾に入れた直後、同じ行を触っても行き先が無く、番号の中に留まって見えた）
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "本文p.42") == 6)
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "本文p.") == 4, "数字を打つ前でも足す")
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "本文p.42\n") == nil, "足したら止まる")
        #expect(MemoQuotePage.trailingBlankLineInsertion(in: "本文p.42のところ") == nil)

        #expect(MemoQuotePage.preparedForEditing("> 引用") == "> 引用\np.\n", "案内と行き先をまとめて用意")
        #expect(MemoQuotePage.preparedForEditing("> 引用\np.42\n本文") == "> 引用\np.42\n本文")
        #expect(MemoQuotePage.preparedForEditing("本文だけ") == "本文だけ", "引用が無ければ何も足さない")
    }

    /// 数字が未入力の案内は消せない。通すと足し直しとぶつかって `p` だけが残る
    @Test func memoQuotePageMarkerCannotBeDeletedWhileEmpty() {
        let empty = "> 引用\np."          // 改行は4文字目、`p.` は 5〜6 文字目
        #expect(MemoQuotePage.protectsDeletion(of: NSRange(location: 5, length: 1), in: empty))
        #expect(MemoQuotePage.protectsDeletion(of: NSRange(location: 4, length: 1), in: empty),
                "直前の改行も守る（消すと `p.` が引用の行に流れ込む）")
        #expect(!MemoQuotePage.protectsDeletion(of: NSRange(location: 2, length: 1), in: empty),
                "引用の中はふつうに消せる")

        let filled = "> 引用\np.42"
        #expect(!MemoQuotePage.protectsDeletion(of: NSRange(location: 8, length: 1), in: filled),
                "入力済みの数字はふつうに消せる（消し切れば案内に戻る）")
    }

    @Test func memoLinkTextDoesNotInterpretOtherMarkdown() {
        // 「ボタンで入れたものだけが装飾になる」（設計メモ 0.4節）。
        // 見出し・箇条書き・斜体・リンクは素通し
        for memo in ["# 見出し", "- 箇条書き", "*斜体* ではない", "[リンク](https://example.com)"] {
            let attributed = MemoLinkText.highlighted(memo, color: .blue)
            #expect(String(attributed.characters) == memo)
        }
    }

    @Test func memoQuoteBlockContentRendersBoldAndLink() {
        // 引用の中身はブロック分割後にインライン装飾へ渡る
        let blocks = MemoTextBlocks.parse("> **強調** と [[京都]]")
        #expect(blocks == [.quote("**強調** と [[京都]]")])
        let attributed = MemoLinkText.highlighted("**強調** と [[京都]]", color: .blue)
        #expect(String(attributed.characters) == "強調 と 京都")
    }

    @Test func memoPageMarkerDetectsPageTokens() {
        func tokens(_ text: String) -> [String] {
            MemoPageMarker.ranges(in: text).map { String(text[$0]) }
        }
        #expect(tokens("p.123") == ["p.123"])
        #expect(tokens("気になったのはp.42のくだり") == ["p.42"], "日本語は語間に空白が無いので英数字以外は境界")
        #expect(tokens("P.7 参照") == ["P.7"])
        #expect(tokens("(p.5)") == ["p.5"])
        // 直前が英数字・数字なし・`.` なしは不成立
        #expect(tokens("stop.123").isEmpty)
        #expect(tokens("map.9").isEmpty)
        #expect(tokens("p.").isEmpty)
        #expect(tokens("p123").isEmpty)
    }

    @Test func memoLinkTextStylesPageNumbersWithoutHidingThem() throws {
        // ページ番号は文字を隠さず、バッジ用の属性だけ付ける（設計メモ 4.6節）
        let attributed = MemoLinkText.highlighted("p.123 を参照", color: .blue)
        #expect(String(attributed.characters) == "p.123 を参照")

        let pageRuns = attributed.runs[\.memoPageNumber].filter { $0.0 == true }
        let pageRun = try #require(pageRuns.first)
        #expect(pageRuns.count == 1)
        #expect(String(attributed.characters[pageRun.1]) == "p.123")
    }

    @Test func memoLinkTextDoesNotStylePageNumbersInsideLinkLabels() {
        // [[ ]] の中身は任意の文字列であり、ページ番号として解釈しない
        let attributed = MemoLinkText.highlighted("[[p.5]]", color: .blue)
        #expect(String(attributed.characters) == "p.5")
        #expect(!attributed.runs[\.memoPageNumber].contains { $0.0 == true })
    }

    @Test func memoLinkTextDoesNotReadBoldMarkersInsideLinkLabel() {
        // [[ ]] の中身は任意の文字列であり、装飾記号として数えない
        let attributed = MemoLinkText.highlighted("[[a**b]] と **太字**", color: .blue)
        #expect(String(attributed.characters) == "a**b と 太字")
    }

}
