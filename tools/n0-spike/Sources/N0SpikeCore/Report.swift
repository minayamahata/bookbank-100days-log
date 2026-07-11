import Foundation

/// 出力レポート（計画メモ 第2章の(a)〜(d)＋正解ラベル用の候補一覧・テストデータ突合）
public enum Report {

    public static func generate(
        books: [InputBook],
        series: SeriesClustering.Result,
        keywords: KeywordExtraction.ShelfResult,
        graph: EdgeComputation.GraphResult,
        parameters: SpikeParameters
    ) -> String {
        let byUUID = Dictionary(uniqueKeysWithValues: books.map { ($0.uuid, $0) })
        func label(_ uuid: String) -> String {
            guard let book = byUUID[uuid] else { return uuid }
            return "\(book.title)（\(book.author ?? "著者不明")）"
        }

        var out = "# N0スパイク 計算レポート\n\n"
        out += "生成日時: \(ISO8601DateFormatter().string(from: Date()))\n"
        out += "対象: \(books.count)冊 / パラメータ: k=\(parameters.edgeLimitK), M=\(parameters.keywordLimitM), "
        out += "IDF閾値=\(parameters.idfThreshold), スコア下限=\(parameters.scoreFloor), "
        out += "接頭辞条件=\(Int(parameters.prefixRatio * 100))%・\(parameters.prefixMinChars)文字\n\n"

        // (d) 統計サマリー
        let edgeCount = graph.uniqueEdges.count
        let keywordOnlyEdges = graph.uniqueEdges.filter { edge in
            edge.reasons.allSatisfy { $0.type == "keyword" }
        }
        let isolated = books.filter { (graph.edgesByBook[$0.uuid] ?? []).isEmpty }
        let hubs = books.filter { uuidBook in
            let edges = graph.edgesByBook[uuidBook.uuid] ?? []
            return edges.count >= parameters.edgeLimitK
                && edges.allSatisfy { $0.reasons.allSatisfy { $0.type == "keyword" } }
        }
        var axisCounts: [String: Int] = [:]
        for edge in graph.uniqueEdges {
            for type in Set(edge.reasons.map(\.type)) { axisCounts[type, default: 0] += 1 }
        }
        out += "## 統計サマリー\n\n"
        out += "- エッジ総数（上位k適用後・重複除去）: \(edgeCount)\n"
        out += "- 軸別内訳（エッジが当該理由を含む数）: series=\(axisCounts["series"] ?? 0), "
        out += "author=\(axisCounts["author"] ?? 0), keyword=\(axisCounts["keyword"] ?? 0), memo=\(axisCounts["memo"] ?? 0)\n"
        let keywordOnlyRatio = edgeCount > 0 ? Double(keywordOnlyEdges.count) / Double(edgeCount) : 0
        out += "- 単語のみを理由とするエッジ: \(keywordOnlyEdges.count)（\(String(format: "%.1f", keywordOnlyRatio * 100))%・基準4=30%以下）\n"
        let keywordOnlySingle = keywordOnlyEdges.filter { $0.reasons.count == 1 }
        let singleRatio = edgeCount > 0 ? Double(keywordOnlySingle.count) / Double(edgeCount) : 0
        out += "- うち単語1語のみのエッジ: \(keywordOnlySingle.count)（\(String(format: "%.1f", singleRatio * 100))%）\n"
        out += "- 孤立ノード: \(isolated.count)冊（\(String(format: "%.1f", Double(isolated.count) / Double(max(books.count, 1)) * 100))%・基準6=参考値）\n"
        out += "- ハブ候補（k本すべて単語エッジ）: \(hubs.count)冊\n"
        out += "- IDF動的フィルタ: \(keywords.idfApplied ? "適用" : "スキップ（N<閾値冊数）") / 除外語数: \(keywords.dynamicallyExcluded.count)\n\n"

        // (a) シリーズクラスタ一覧
        out += "## シリーズクラスタ一覧（\(series.members.count)クラスタ）\n\n"
        for (cluster, members) in series.members.sorted(by: { $0.value.count > $1.value.count }) {
            let kind = cluster.hasPrefix("series:") ? "S-A" : "S-B"
            out += "- [\(kind)] \(cluster)（\(members.count)冊）\n"
            for uuid in members { out += "    - \(label(uuid))\n" }
        }
        out += "\n"

        // テストデータ突合（expectedSeriesKey がある場合のみ）
        let labeled = books.filter { $0.expectedSeriesKey != nil }
        if !labeled.isEmpty {
            out += "## テストデータ突合（正解ラベル付き \(labeled.count)冊）\n\n"
            let metrics = seriesMetrics(books: labeled, series: series)
            out += "- 誤結合ペア: \(metrics.falsePairs)（誤結合率 \(String(format: "%.1f", metrics.falseRate * 100))%・基準2=2%以下）\n"
            out += "- 取りこぼしペア: \(metrics.missedPairs) / 正解ペア\(metrics.truthPairs)（取りこぼし率 \(String(format: "%.1f", metrics.missRate * 100))%・基準3=25%以下）\n\n"
        }

        // 正解ラベル用: 著者一致ペア候補一覧（実本棚の手順5用）
        out += "## 著者一致ペア候補（シリーズ正解ラベル付け用・4.2節）\n\n"
        out += "同著者でクラスタ判定されなかったペアを含む全候補。同シリーズのものに印を付けてください。\n\n"
        var byAuthor: [String: [InputBook]] = [:]
        for book in books {
            guard let author = book.author, !author.isEmpty else { continue }
            byAuthor[Normalization.authorKey(author), default: []].append(book)
        }
        for (author, authorBooks) in byAuthor.sorted(by: { $0.value.count > $1.value.count })
        where authorBooks.count >= 2 {
            out += "- 著者: \(authorBooks[0].author ?? author)（\(authorBooks.count)冊）\n"
            for book in authorBooks {
                let cluster = series.clusterByBook[book.uuid].map { " → クラスタ: \($0)" } ?? ""
                out += "    - [ ] \(book.title)\(cluster)\n"
            }
        }
        out += "\n"

        // (c) 語の頻度表
        out += "## 語の頻度表（IDF評価用・4.3節）\n\n"
        out += "### 動的フィルタで除外された語（df/N > \(parameters.idfThreshold)）\n\n"
        let excludedSorted = keywords.dynamicallyExcluded.sorted {
            (keywords.documentFrequency[$0] ?? 0) > (keywords.documentFrequency[$1] ?? 0)
        }
        for word in excludedSorted {
            out += "- \(word)（\(keywords.documentFrequency[word] ?? 0)冊）\n"
        }
        out += "\n### 通過語の上位50（df降順）\n\n"
        let passed = keywords.documentFrequency
            .filter { !keywords.dynamicallyExcluded.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(50)
        for (word, count) in passed { out += "- \(word)（\(count)冊）\n" }
        out += "\n"

        // (b) 本ごとの上位kエッジ
        out += "## 本ごとのエッジ（reasons付き・目視評価用）\n\n"
        for book in books {
            let edges = graph.edgesByBook[book.uuid] ?? []
            guard !edges.isEmpty else { continue }
            out += "### \(label(book.uuid)) [lang=\(keywords.byBook[book.uuid]?.lang ?? "?")]\n\n"
            for edge in edges {
                let reasonText = edge.reasons.map { "\($0.type):\($0.value)" }.joined(separator: ", ")
                out += "- score \(String(format: "%.2f", edge.score)) → \(label(edge.to))  《\(reasonText)》\n"
            }
            out += "\n"
        }

        // 孤立ノード一覧
        if !isolated.isEmpty {
            out += "## 孤立ノード（エッジ0本・\(isolated.count)冊）\n\n"
            for book in isolated { out += "- \(label(book.uuid))\n" }
        }

        return out
    }

    /// テストデータ（正解ラベル付き）のシリーズ判定指標。
    /// 取りこぼし率の分母は「著者一致ペア内の正解ペア」のみ（計画メモ 4.2節の測定範囲限定）。
    public static func seriesMetrics(
        books: [InputBook],
        series: SeriesClustering.Result
    ) -> (truthPairs: Int, falsePairs: Int, missedPairs: Int, falseRate: Double, missRate: Double) {
        var truthPairs = 0
        var falsePairs = 0
        var missedPairs = 0
        var judgedPairs = 0
        for i in 0..<books.count {
            for j in (i + 1)..<books.count {
                let bookA = books[i], bookB = books[j]
                // 測定範囲の限定: 著者一致ペアのみ（4.2節）
                guard let authorA = bookA.author, let authorB = bookB.author,
                      Normalization.authorKey(authorA) == Normalization.authorKey(authorB) else { continue }
                let expectedSame = bookA.expectedSeriesKey != nil
                    && bookA.expectedSeriesKey == bookB.expectedSeriesKey
                let judgedSame = series.clusterByBook[bookA.uuid] != nil
                    && series.clusterByBook[bookA.uuid] == series.clusterByBook[bookB.uuid]
                if expectedSame { truthPairs += 1 }
                if judgedSame { judgedPairs += 1 }
                if judgedSame && !expectedSame { falsePairs += 1 }
                if expectedSame && !judgedSame { missedPairs += 1 }
            }
        }
        let falseRate = judgedPairs > 0 ? Double(falsePairs) / Double(judgedPairs) : 0
        let missRate = truthPairs > 0 ? Double(missedPairs) / Double(truthPairs) : 0
        return (truthPairs, falsePairs, missedPairs, falseRate, missRate)
    }
}
