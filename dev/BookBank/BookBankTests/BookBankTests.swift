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

    // MARK: - MemoLinkParser.draftLink / MemoLinkIndex（入力サジェストの土台）

    /// キャレットを文字列末尾に置いて入力途中のつながりを取る（実際の編集も多くはこの形）
    private func draftAtEnd(_ text: String) -> MemoDraftLink? {
        MemoLinkParser.draftLink(in: text, before: text.endIndex)
    }

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

    @Test func memoDraftLinkDetectsPartialInput() {
        #expect(draftAtEnd("旅の記録 [[京")?.partialKey == "京")
        #expect(draftAtEnd("[[KYO")?.partialKey == "kyo", "候補の突合は正規化キーで行う")
        #expect(draftAtEnd("[[京都]] [[奈")?.partialKey == "奈", "閉じたつながりの後ろも入力途中と見なす")
    }

    @Test func memoDraftLinkDetectsBareOpener() {
        // `[[` を打った瞬間が、既存のつながりを全部出せる最も役に立つ瞬間
        #expect(draftAtEnd("[[")?.partialKey == "")
        #expect(draftAtEnd("旅の記録 [[")?.partialKey == "")
        #expect(draftAtEnd("［［")?.partialKey == "", "全角括弧の手打ちも受ける")
    }

    @Test func memoDraftLinkCoversTrailingCloser() throws {
        // ツールバーの「つなぐ」は [[]] を挿入してキャレットを括弧の中に置く（4.5節）。
        // その状態で候補をタップしたら、後ろの ]] ごと丸ごと置き換わらなければならない
        var text = "[[]]"
        var caret = text.index(text.startIndex, offsetBy: 2)
        var draft = try #require(MemoLinkParser.draftLink(in: text, before: caret))
        #expect(draft.partialKey == "")
        #expect(String(text[draft.range]) == "[[]]")

        // 既存のつながりの中身を編集し直す形も同じ
        text = "[[京都]] のメモ"
        caret = text.index(text.startIndex, offsetBy: 3) // 「京」の直後
        draft = try #require(MemoLinkParser.draftLink(in: text, before: caret))
        #expect(draft.partialKey == "京")
        #expect(String(text[draft.range]) == "[[京都]]")
    }

    @Test func memoDraftLinkRejectsPositionsThatAreNotLinks() {
        #expect(draftAtEnd("つながりのないメモ") == nil)
        #expect(draftAtEnd("[") == nil, "括弧1つでは開かない")
        #expect(draftAtEnd("[[京都]] のあと") == nil, "キャレットの手前で閉じていれば対象外")
        #expect(draftAtEnd("[[京都\n") == nil, "行をまたいだら開いていない扱い（改行不成立と同じ）")
        #expect(draftAtEnd("[[\(String(repeating: "あ", count: 31))") == nil, "上限超過は候補も出さない")
    }

    @Test func memoDraftLinkRangeCoversWhatWillBeReplaced() throws {
        let text = "旅の記録 [[京"
        let draft = try #require(draftAtEnd(text))
        #expect(String(text[draft.range]) == "[[京")
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

    @Test func memoLinkIndexSuggestsByPrefixExcludingWrittenLinks() {
        let books = [
            sampleLinkedBook(id: "1", memo: "[[京都]] [[京都駅]]"),
            sampleLinkedBook(id: "2", memo: "[[奈良]]")
        ]
        let index = MemoLinkIndex.build(from: books)

        #expect(index.suggestions(matching: "京", excluding: []).map(\.key) == ["京都", "京都駅"])
        #expect(index.suggestions(matching: "", excluding: []).count == 3, "[[ だけなら全部出す")
        #expect(
            index.suggestions(matching: "京", excluding: ["京都"]).map(\.key) == ["京都駅"],
            "編集中のメモに既に書かれているつながりは候補から外す"
        )
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

}
