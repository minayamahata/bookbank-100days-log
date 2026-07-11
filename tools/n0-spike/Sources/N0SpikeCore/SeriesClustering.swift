import Foundation

/// シリーズ判定 S-A + S-B（設計書 2.2節）
public enum SeriesClustering {

    public struct Result: Sendable {
        /// bookUUID → シリーズクラスタID（クラスタなしの本は含まれない）
        public var clusterByBook: [String: String]
        /// クラスタID → 所属bookUUID（2冊以上のクラスタのみ）
        public var members: [String: [String]]
    }

    /// 全冊のシリーズクラスタを計算する。
    /// 1) S-A: seriesName の正規化一致
    /// 2) S-B: 著者一致を必須条件として、基底タイトル完全一致 or 最長共通接頭辞条件でクラスタ化
    public static func cluster(books: [InputBook], parameters: SpikeParameters) -> Result {
        var clusterByBook: [String: String] = [:]

        // --- S-A: seriesName 一致 ---
        for book in books {
            if let series = book.seriesName, !series.isEmpty {
                let key = Normalization.seriesKey(series)
                if !key.isEmpty {
                    clusterByBook[book.uuid] = "series:\(key)"
                }
            }
        }

        // --- S-B: 著者一致必須のタイトルクラスタリング（S-A未判定の本のみ） ---
        let remaining = books.filter { clusterByBook[$0.uuid] == nil }
        var byAuthor: [String: [InputBook]] = [:]
        for book in remaining {
            guard let author = book.author, !author.isEmpty else { continue }
            let authorKey = Normalization.authorKey(author)
            guard !authorKey.isEmpty else { continue }
            byAuthor[authorKey, default: []].append(book)
        }

        for (authorKey, authorBooks) in byAuthor where authorBooks.count >= 2 {
            // Union-Find で「基底タイトル一致 or 接頭辞条件」のペアを繋ぐ
            var parent = Array(0..<authorBooks.count)
            func find(_ i: Int) -> Int {
                var i = i
                while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
                return i
            }
            func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

            let baseTitles = authorBooks.map {
                VolumePatterns.strippingVolumeTokens(from: Normalization.normalize($0.title))
            }
            for i in 0..<authorBooks.count {
                for j in (i + 1)..<authorBooks.count {
                    if titlesBelongToSameSeries(
                        baseTitles[i], baseTitles[j], parameters: parameters
                    ) {
                        union(i, j)
                    }
                }
            }
            var groups: [Int: [Int]] = [:]
            for i in 0..<authorBooks.count {
                groups[find(i), default: []].append(i)
            }
            for (root, indices) in groups where indices.count >= 2 {
                let clusterID = "title:\(authorKey):\(baseTitles[root])"
                for index in indices {
                    clusterByBook[authorBooks[index].uuid] = clusterID
                }
            }
        }

        // members の構築（S-Aクラスタは1冊のみでも保持しない＝ペアが成立するもののみ）
        var members: [String: [String]] = [:]
        for (uuid, cluster) in clusterByBook {
            members[cluster, default: []].append(uuid)
        }
        for (cluster, uuids) in members where uuids.count < 2 {
            members.removeValue(forKey: cluster)
            for uuid in uuids { clusterByBook.removeValue(forKey: uuid) }
        }
        return Result(clusterByBook: clusterByBook, members: members)
    }

    /// S-B の判定条件（設計書 2.2節）:
    /// 基底タイトルの完全一致、または最長共通接頭辞が
    /// 「短い方のタイトルの60%以上 かつ 4文字（英語は2単語）以上」
    public static func titlesBelongToSameSeries(
        _ a: String, _ b: String, parameters: SpikeParameters
    ) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let prefix = commonPrefix(a, b)
        let shorter = min(a.count, b.count)
        guard Double(prefix.count) >= Double(shorter) * parameters.prefixRatio else { return false }
        let isLatin = prefix.unicodeScalars.allSatisfy {
            $0.isASCII || CharacterSet.whitespaces.contains($0)
        }
        if isLatin {
            let words = prefix.split(separator: " ").filter { !$0.isEmpty }
            return words.count >= parameters.prefixMinWordsEnglish
        }
        return prefix.count >= parameters.prefixMinChars
    }

    static func commonPrefix(_ a: String, _ b: String) -> String {
        String(zip(a, b).prefix(while: { $0 == $1 }).map(\.0))
            .trimmingCharacters(in: .whitespaces)
    }
}
