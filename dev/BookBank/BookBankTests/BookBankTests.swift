//
//  BookBankTests.swift
//  BookBankTests
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import Foundation
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

}
