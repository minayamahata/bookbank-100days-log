import XCTest
@testable import N0SpikeCore

final class VolumePatternTests: XCTestCase {

    func testJapaneseVolumePatterns() {
        let cases: [(String, String)] = [
            ("ハリー・ポッターと賢者の石 第1巻", "ハリー・ポッターと賢者の石"),
            ("鬼滅の刃 (23)", "鬼滅の刃"),
            ("キングダム 65巻", "キングダム"),
            ("坂の上の雲 上", "坂の上の雲"),
            ("その後の話 前編", "その後の話"),
            ("ワンピース ①", "ワンピース")
        ]
        for (input, expected) in cases {
            let normalized = Normalization.normalize(input)
            XCTAssertEqual(
                VolumePatterns.strippingVolumeTokens(from: normalized),
                Normalization.normalize(expected),
                "input: \(input)"
            )
        }
    }

    func testEnglishKoreanChineseVolumePatterns() {
        let cases: [(String, String)] = [
            ("the lord of the rings vol. 2", "the lord of the rings"),
            ("harry potter #3", "harry potter"),
            ("dune part 2", "dune"),
            ("해리포터 3권", "해리포터"),
            ("三体 第2册", "三体"),
            ("三體 第三卷", "三體")
        ]
        for (input, expected) in cases {
            let normalized = Normalization.normalize(input)
            XCTAssertEqual(
                VolumePatterns.strippingVolumeTokens(from: normalized),
                Normalization.normalize(expected),
                "input: \(input)"
            )
        }
    }

    func testDoesNotStripMeaningfulNumbers() {
        // タイトル中間・タイトル自体が数字の場合は消さない
        XCTAssertEqual(VolumePatterns.strippingVolumeTokens(from: "1984"), "1984")
        XCTAssertEqual(
            VolumePatterns.strippingVolumeTokens(from: "20世紀少年の逆襲"),
            "20世紀少年の逆襲"
        )
    }
}

final class NormalizationTests: XCTestCase {

    func testAuthorKeyLatinVariants() {
        // 「姓, 名」→「名 姓」ゆれの吸収
        XCTAssertEqual(
            Normalization.authorKey("Rowling, J. K."),
            Normalization.authorKey("J. K. Rowling")
        )
        // ミドルネームイニシャルの正規化
        XCTAssertEqual(
            Normalization.authorKey("George R. R. Martin"),
            Normalization.authorKey("George Martin")
        )
    }

    func testAuthorKeyCJKStripsSpaces() {
        XCTAssertEqual(Normalization.authorKey("村上 春樹"), Normalization.authorKey("村上春樹"))
    }

    func testSeriesKeyNormalization() {
        XCTAssertEqual(
            Normalization.seriesKey("ハリー・ポッター 第1巻"),
            Normalization.seriesKey("ハリー・ポッター")
        )
    }
}

final class SeriesClusteringTests: XCTestCase {

    private func book(
        _ uuid: String, _ title: String, author: String?, series: String? = nil
    ) -> InputBook {
        InputBook(uuid: uuid, title: title, author: author, seriesName: series)
    }

    func testSeriesNameMatchSA() {
        let books = [
            book("1", "賢者の石", author: "J.K.ローリング", series: "ハリー・ポッター"),
            book("2", "秘密の部屋", author: "J.K.ローリング", series: "ハリー・ポッター (2)")
        ]
        let result = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        XCTAssertEqual(result.clusterByBook["1"], result.clusterByBook["2"])
        XCTAssertNotNil(result.clusterByBook["1"])
    }

    func testTitlePrefixClusteringSB() {
        let books = [
            book("1", "ハリー・ポッターと賢者の石", author: "J.K.ローリング"),
            book("2", "ハリー・ポッターと秘密の部屋", author: "J.K.ローリング")
        ]
        let result = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        XCTAssertEqual(result.clusterByBook["1"], result.clusterByBook["2"])
        XCTAssertNotNil(result.clusterByBook["1"])
    }

    func testAuthorMismatchPreventsClustering() {
        // 著者一致必須: タイトルが似ていても著者が違えばクラスタ化しない
        let books = [
            book("1", "ハリー・ポッターと賢者の石", author: "J.K.ローリング"),
            book("2", "ハリー・ポッターと呪いの子", author: "ジャック・ソーン")
        ]
        let result = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        XCTAssertTrue(result.members.isEmpty)
    }

    func testVolumeNumberVariants() {
        let books = [
            book("1", "キングダム 1", author: "原泰久"),
            book("2", "キングダム (2)", author: "原泰久"),
            book("3", "キングダム 65巻", author: "原泰久")
        ]
        let result = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        XCTAssertEqual(Set(result.members.values.first ?? []), ["1", "2", "3"])
    }

    func testShortCommonPrefixDoesNotCluster() {
        // 接頭辞が短い（4文字未満・60%未満）別作品はクラスタ化しない
        let books = [
            book("1", "海辺のカフカ", author: "村上春樹"),
            book("2", "海と毒薬についての考察と記録", author: "村上春樹")
        ]
        let result = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        XCTAssertTrue(result.members.isEmpty)
    }
}

final class KeywordExtractionTests: XCTestCase {

    func testNounExtractionJapanese() {
        let result = KeywordExtraction.nouns(in: "満洲事変と戦争の歴史")
        XCTAssertEqual(result.lang, "ja")
        XCTAssertTrue(result.words.contains("戦争"), "抽出結果: \(result.words)")
    }

    func testShortTokensAreDropped() {
        let result = KeywordExtraction.nouns(in: "The Art of War")
        // 2文字以下のラテン語トークン（of等）は残らない
        XCTAssertFalse(result.words.contains("of"))
    }

    func testIDFSkippedForSmallShelf() {
        let books = (1...5).map {
            InputBook(uuid: "\($0)", title: "戦争と平和の物語\($0)", author: "著者")
        }
        let result = KeywordExtraction.extract(books: books, memos: [], parameters: SpikeParameters())
        XCTAssertFalse(result.idfApplied)
        XCTAssertTrue(result.dynamicallyExcluded.isEmpty)
    }

    func testIDFExcludesCommonWords() {
        var parameters = SpikeParameters()
        parameters.idfMinimumBookCount = 4
        // 「経済」が全冊に出る（df/N=1.0 > 0.25）→除外。個別語は残る
        let books = [
            InputBook(uuid: "1", title: "経済の思想", author: "a"),
            InputBook(uuid: "2", title: "経済と満洲", author: "b"),
            InputBook(uuid: "3", title: "経済の貨幣論", author: "c"),
            InputBook(uuid: "4", title: "経済と金融", author: "d")
        ]
        let result = KeywordExtraction.extract(books: books, memos: [], parameters: parameters)
        XCTAssertTrue(result.idfApplied)
        XCTAssertTrue(result.dynamicallyExcluded.contains("経済"), "除外: \(result.dynamicallyExcluded)")
        XCTAssertTrue(result.byBook["2"]?.keywords.contains { $0.word == "満洲" } ?? false)
    }
}

final class EdgeComputationTests: XCTestCase {

    func testSeriesEdgeIsStrongest() {
        let books = [
            InputBook(uuid: "1", title: "キングダム 1", author: "原泰久"),
            InputBook(uuid: "2", title: "キングダム 2", author: "原泰久"),
            InputBook(uuid: "3", title: "別の漫画論", author: "原泰久")
        ]
        let parameters = SpikeParameters()
        let series = SeriesClustering.cluster(books: books, parameters: parameters)
        let keywords = KeywordExtraction.extract(books: books, memos: [], parameters: parameters)
        let graph = EdgeComputation.compute(
            books: books, series: series, keywords: keywords, memos: [], parameters: parameters
        )
        let edges1 = graph.edgesByBook["1"] ?? []
        XCTAssertEqual(edges1.first?.to, "2", "シリーズエッジが最上位に来る")
        // シリーズ(1.0)+著者(0.6)以上のスコア
        XCTAssertGreaterThanOrEqual(edges1.first?.score ?? 0, 1.6)
        // 著者のみのエッジ（→3）はスコア0.6で下限0.15を超え存在する
        XCTAssertTrue(edges1.contains { $0.to == "3" })
    }

    func testScoreFloorExcludesWeakEdges() {
        var parameters = SpikeParameters()
        parameters.idfMinimumBookCount = 100  // IDFスキップ状態にして語を残す
        parameters.scoreFloor = 0.5           // 著者なし・語1〜3個では届かない下限
        let books = [
            InputBook(uuid: "1", title: "満洲の戦争", author: "a"),
            InputBook(uuid: "2", title: "満洲の鉄道", author: "b")
        ]
        let series = SeriesClustering.cluster(books: books, parameters: parameters)
        let keywords = KeywordExtraction.extract(books: books, memos: [], parameters: parameters)
        let graph = EdgeComputation.compute(
            books: books, series: series, keywords: keywords, memos: [], parameters: parameters
        )
        XCTAssertTrue(graph.uniqueEdges.isEmpty, "スコア下限未満のエッジは保存されない")
    }

    func testEdgeLimitK() {
        var parameters = SpikeParameters()
        parameters.edgeLimitK = 3
        // 同著者の本を10冊: 各本のエッジは3本まで
        let books = (1...10).map {
            InputBook(uuid: "\($0)", title: "随筆その\($0)", author: "同じ著者")
        }
        let series = SeriesClustering.cluster(books: books, parameters: parameters)
        let keywords = KeywordExtraction.extract(books: books, memos: [], parameters: parameters)
        let graph = EdgeComputation.compute(
            books: books, series: series, keywords: keywords, memos: [], parameters: parameters
        )
        for (_, edges) in graph.edgesByBook {
            XCTAssertLessThanOrEqual(edges.count, 3)
        }
    }
}

final class SeriesMetricsTests: XCTestCase {

    func testMetricsCountOnlyAuthorMatchedPairs() {
        // 著者表記ゆれで著者一致にならないペアは分母に入らない（計画メモ 4.2節の測定範囲限定）
        let books = [
            InputBook(uuid: "1", title: "ノルウェイの森 上", author: "村上春樹", expectedSeriesKey: "norway"),
            InputBook(uuid: "2", title: "ノルウェイの森 下", author: "村上春樹", expectedSeriesKey: "norway"),
            InputBook(uuid: "3", title: "norwegian wood", author: "Haruki Murakami", expectedSeriesKey: "norway")
        ]
        let series = SeriesClustering.cluster(books: books, parameters: SpikeParameters())
        let metrics = Report.seriesMetrics(books: books, series: series)
        // 正解ペアは (1,2)(1,3)(2,3) の3つだが、著者一致は (1,2) のみ → 分母1
        XCTAssertEqual(metrics.truthPairs, 1)
        XCTAssertEqual(metrics.missedPairs, 0)
        XCTAssertEqual(metrics.falsePairs, 0)
    }
}
