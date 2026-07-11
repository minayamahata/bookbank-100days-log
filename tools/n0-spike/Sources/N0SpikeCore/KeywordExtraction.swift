import Foundation
import NaturalLanguage

/// 単語抽出 W-C（設計書 3.2節）: 正規化 → 言語判定 → 名詞抽出 → 静的ストップワード → 本棚内IDF
public enum KeywordExtraction {

    public struct BookKeywords: Sendable {
        public var bookUUID: String
        /// 主要言語（タイトルの判定結果）
        public var lang: String
        /// IDFフィルタ通過後の上位M語（語, idf正規化値）スコア降順
        public var keywords: [(word: String, idf: Double)]
        /// IDF適用前の名詞集合（レポートの頻度表用）
        public var rawNouns: Set<String>
    }

    public struct ShelfResult: Sendable {
        public var byBook: [String: BookKeywords]
        /// 語 → その語を含む本の数（document frequency）
        public var documentFrequency: [String: Int]
        /// IDFフィルタ（df/N > 閾値）で除外された語
        public var dynamicallyExcluded: Set<String>
        /// IDFフィルタを適用したか（N >= idfMinimumBookCount）
        public var idfApplied: Bool
    }

    /// 本棚全体のキーワード抽出を行う。
    public static func extract(
        books: [InputBook],
        memos: [InputMemo],
        parameters: SpikeParameters
    ) -> ShelfResult {
        // 本ごとのテキスト = title + seriesName + memo（設計書 前提N1）
        var nounsByBook: [String: Set<String>] = [:]
        var langByBook: [String: String] = [:]

        for book in books {
            let titleNouns = nouns(in: book.title)
            let seriesNouns = book.seriesName.map { nouns(in: $0) } ?? (lang: nil, words: [])
            let memoNouns = book.memo.map { nouns(in: $0) } ?? (lang: nil, words: [])
            let lang = titleNouns.lang ?? memoNouns.lang ?? "und"
            langByBook[book.uuid] = lang

            var all = Set(titleNouns.words).union(seriesNouns.words).union(memoNouns.words)
            // 静的ストップワード（テキストごとの言語で除外。混在に備え全言語辞書の和も除く）
            let stop = Stopwords.forLanguage(lang)
            all = all.filter { !stop.contains($0) && !isStopwordInAnyLanguage($0) }
            nounsByBook[book.uuid] = all
        }

        // document frequency
        var df: [String: Int] = [:]
        for (_, words) in nounsByBook {
            for word in words { df[word, default: 0] += 1 }
        }

        let bookCount = books.count
        let idfApplied = bookCount >= parameters.idfMinimumBookCount
        var excluded: Set<String> = []
        if idfApplied {
            for (word, count) in df where Double(count) / Double(bookCount) > parameters.idfThreshold {
                excluded.insert(word)
            }
        }

        // idf(w) = log(N / df(w)) を 0..1 に正規化（最大は df=1 の log(N)）
        let maxIDF = log(Double(max(bookCount, 2)))
        var byBook: [String: BookKeywords] = [:]
        for book in books {
            let raw = nounsByBook[book.uuid] ?? []
            let filtered = raw.subtracting(excluded)
            let scored = filtered.map { word -> (String, Double) in
                let idf = log(Double(bookCount) / Double(df[word] ?? 1)) / maxIDF
                return (word, min(max(idf, 0), 1))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(parameters.keywordLimitM)
            byBook[book.uuid] = BookKeywords(
                bookUUID: book.uuid,
                lang: langByBook[book.uuid] ?? "und",
                keywords: scored.map { (word: $0.0, idf: $0.1) },
                rawNouns: raw
            )
        }

        return ShelfResult(
            byBook: byBook,
            documentFrequency: df,
            dynamicallyExcluded: excluded,
            idfApplied: idfApplied
        )
    }

    static func isStopwordInAnyLanguage(_ word: String) -> Bool {
        Stopwords.japanese.contains(word) || Stopwords.english.contains(word)
            || Stopwords.korean.contains(word) || Stopwords.simplifiedChinese.contains(word)
            || Stopwords.traditionalChinese.contains(word)
    }

    /// 品詞タグ（lexicalClass）がその言語で利用可能か。
    /// 【N0での実測（2026-07-11）】日本語・韓国語は lexicalClass 非対応（全トークンが OtherWord になる）。
    /// 英語・中国語（簡体字）は対応。非対応言語は設計書 4.2節のフォールバック
    /// 「名詞抽出を諦め、単語分割＋ストップワード＋IDFのみ」を適用する。
    public static func lexicalClassAvailable(for language: NLLanguage) -> Bool {
        NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass)
    }

    /// テキスト1件から語を抽出する（言語判定つき）。
    /// - 品詞タグ対応言語: 名詞・固有名詞のみ残す（設計書 3.2節 手順3）
    /// - 非対応言語（ja/ko等）: 単語分割の全トークン（フォールバック・ストップワードとIDFで濾す）
    /// - 1文字の語（CJK）・2文字以下の語（ラテン）は捨てる
    /// - 記号・数字のみのトークンは捨てる
    public static func nouns(in text: String) -> (lang: String?, words: [String]) {
        let normalized = text.precomposedStringWithCompatibilityMapping
        guard !normalized.isEmpty else { return (nil, []) }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        let lang = recognizer.dominantLanguage
        let langCode = lang.map { mapLanguageCode($0) }
        let usePOS = lang.map { lexicalClassAvailable(for: $0) } ?? false

        let tagger = NLTagger(tagSchemes: usePOS ? [.lexicalClass] : [.tokenType])
        tagger.string = normalized
        if let lang { tagger.setLanguage(lang, range: normalized.startIndex..<normalized.endIndex) }

        var words: [String] = []
        tagger.enumerateTags(
            in: normalized.startIndex..<normalized.endIndex,
            unit: .word,
            scheme: usePOS ? .lexicalClass : .tokenType,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if usePOS {
                guard tag == .noun || tag == .personalName || tag == .placeName
                    || tag == .organizationName else { return true }
            } else {
                guard tag == .word else { return true }
            }
            let token = Normalization.normalize(String(normalized[range]))
            guard !token.isEmpty else { return true }
            // 記号・数字のみは捨てる
            guard token.rangeOfCharacter(from: .letters) != nil else { return true }
            // 短語の除去: ラテンは2文字以下、CJKは1文字を捨てる
            let isLatin = token.unicodeScalars.allSatisfy { $0.isASCII }
            if isLatin {
                guard token.count > 2 else { return true }
            } else {
                guard token.count > 1 else { return true }
            }
            words.append(token)
            return true
        }
        return (langCode, words)
    }

    /// NLLanguage → アプリの言語コード（"ja" / "en" / "ko" / "zh-Hans" / "zh-Hant" / その他はrawValue）
    static func mapLanguageCode(_ language: NLLanguage) -> String {
        switch language {
        case .japanese: return "ja"
        case .english: return "en"
        case .korean: return "ko"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        default: return language.rawValue
        }
    }
}
