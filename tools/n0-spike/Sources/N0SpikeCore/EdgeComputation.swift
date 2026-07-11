import Foundation

/// エッジ計算 E-B（設計書 5.2節）: 転置インデックス経由でスコア計算し、本ごとに上位kエッジを保持
public enum EdgeComputation {

    public struct Reason: Sendable, Equatable {
        public var type: String   // "series" | "author" | "keyword" | "memo"
        public var value: String
    }

    public struct Edge: Sendable {
        public var from: String
        public var to: String
        public var score: Double
        public var reasons: [Reason]
    }

    public struct GraphResult: Sendable {
        /// bookUUID → 上位kエッジ（スコア降順）
        public var edgesByBook: [String: [Edge]]
        /// 重複除去済みの全エッジ（from < to）
        public var uniqueEdges: [Edge]
    }

    public static func compute(
        books: [InputBook],
        series: SeriesClustering.Result,
        keywords: KeywordExtraction.ShelfResult,
        memos: [InputMemo],
        parameters: SpikeParameters
    ) -> GraphResult {
        let byUUID = Dictionary(uniqueKeysWithValues: books.map { ($0.uuid, $0) })

        // --- 転置インデックス ---
        var byAuthor: [String: [String]] = [:]
        for book in books {
            guard let author = book.author, !author.isEmpty else { continue }
            let key = Normalization.authorKey(author)
            guard !key.isEmpty else { continue }
            byAuthor[key, default: []].append(book.uuid)
        }
        var byKeyword: [String: [String]] = [:]
        for (uuid, entry) in keywords.byBook {
            for keyword in entry.keywords { byKeyword[keyword.word, default: []].append(uuid) }
        }
        // メモ月: 「その月に登録された本」＋メモtextは語としてkeyword側で拾われるため、
        // ここでは登録月一致のみを対象とする（設計書 前提N1の「緩い紐付き」・重み最小）
        var byMonth: [String: [String]] = [:]
        let memoMonths = Set(memos.map(\.monthKey))
        for book in books {
            if let month = book.registeredMonth, memoMonths.contains(month) {
                byMonth[month, default: []].append(book.uuid)
            }
        }

        // --- 候補ペアの収集（同じキーを共有するペアのみ照合） ---
        var candidatePairs: Set<PairKey> = []
        for (_, members) in series.members { addPairs(members, to: &candidatePairs) }
        for (_, members) in byAuthor { addPairs(members, to: &candidatePairs) }
        for (_, members) in byKeyword { addPairs(members, to: &candidatePairs) }
        for (_, members) in byMonth { addPairs(members, to: &candidatePairs) }

        // --- スコア計算 ---
        var uniqueEdges: [Edge] = []
        for pair in candidatePairs {
            guard let bookA = byUUID[pair.a], let bookB = byUUID[pair.b] else { continue }
            var score = 0.0
            var reasons: [Reason] = []

            // シリーズ
            if let clusterA = series.clusterByBook[pair.a],
               let clusterB = series.clusterByBook[pair.b], clusterA == clusterB {
                score += parameters.weightSeries
                let display = bookA.seriesName ?? bookB.seriesName
                    ?? VolumePatterns.strippingVolumeTokens(from: Normalization.normalize(bookA.title))
                reasons.append(Reason(type: "series", value: display))
            }
            // 著者（正規化キーが空になる著者名は一致判定しない: "" == "" の誤マッチ防止）
            if let authorA = bookA.author, let authorB = bookB.author {
                let keyA = Normalization.authorKey(authorA)
                let keyB = Normalization.authorKey(authorB)
                if !keyA.isEmpty, keyA == keyB {
                    score += parameters.weightAuthor
                    reasons.append(Reason(type: "author", value: authorA))
                }
            }
            // 共有キーワード（idf降順で上限3語）
            if let keywordsA = keywords.byBook[pair.a], let keywordsB = keywords.byBook[pair.b] {
                let idfA = Dictionary(uniqueKeysWithValues: keywordsA.keywords.map { ($0.word, $0.idf) })
                let shared = keywordsB.keywords
                    .filter { idfA[$0.word] != nil }
                    .sorted { $0.idf > $1.idf }
                    .prefix(parameters.keywordContributionLimit)
                for keyword in shared {
                    score += min(parameters.weightKeyword * keyword.idf, parameters.weightKeyword)
                    reasons.append(Reason(type: "keyword", value: keyword.word))
                }
            }
            // 同月メモ
            if let monthA = bookA.registeredMonth, let monthB = bookB.registeredMonth,
               monthA == monthB, memoMonths.contains(monthA) {
                score += parameters.weightMemoMonth
                reasons.append(Reason(type: "memo", value: monthA))
            }

            guard score >= parameters.scoreFloor else { continue }
            uniqueEdges.append(Edge(from: pair.a, to: pair.b, score: score, reasons: reasons))
        }

        // --- 本ごとの上位k制限 ---
        var edgesByBook: [String: [Edge]] = [:]
        for edge in uniqueEdges {
            edgesByBook[edge.from, default: []].append(edge)
            edgesByBook[edge.to, default: []].append(
                Edge(from: edge.to, to: edge.from, score: edge.score, reasons: edge.reasons)
            )
        }
        for (uuid, edges) in edgesByBook {
            edgesByBook[uuid] = Array(edges.sorted { $0.score > $1.score }.prefix(parameters.edgeLimitK))
        }
        // uniqueEdges も「少なくとも片側の上位kに残ったもの」に絞る（表示されないエッジを評価対象から外す）
        let survivingPairs: Set<PairKey> = Set(edgesByBook.flatMap { (_, edges) in
            edges.map { PairKey($0.from, $0.to) }
        })
        uniqueEdges = uniqueEdges.filter { survivingPairs.contains(PairKey($0.from, $0.to)) }

        return GraphResult(edgesByBook: edgesByBook, uniqueEdges: uniqueEdges)
    }

    struct PairKey: Hashable {
        let a: String
        let b: String
        init(_ x: String, _ y: String) {
            if x < y { a = x; b = y } else { a = y; b = x }
        }
    }

    static func addPairs(_ members: [String], to set: inout Set<PairKey>) {
        guard members.count >= 2 else { return }
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                set.insert(PairKey(members[i], members[j]))
            }
        }
    }
}
