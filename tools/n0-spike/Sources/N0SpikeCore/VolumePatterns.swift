import Foundation

/// 巻数パターン辞書（5言語・設計書 2.2節）。
/// タイトル・シリーズ名から巻数表現を除去して「基底タイトル」を作るために使う。
/// この初版はN0の評価対象であり、取りこぼしが見つかったら追記する（計画メモ 第7章）。
public enum VolumePatterns {

    /// 正規化済み（NFKC・小文字）テキストに適用する正規表現パターン。
    /// 末尾・括弧内の巻数表現を対象とし、タイトル中間の数字（例: 「1984」）は消さないよう
    /// 「末尾アンカー」または「区切り記号を伴う形」に限定する。
    static let patterns: [String] = [
        // 日本語
        #"第[0-9０-９一二三四五六七八九十百]+巻$"#,
        #"[0-9０-９]+巻$"#,
        #"（[0-9０-９一二三四五六七八九十]+）$"#,
        #"\([0-9０-９一二三四五六七八九十]+\)$"#,
        #"(上|中|下)巻?$"#,
        #"(前編|中編|後編|前篇|中篇|後篇)$"#,
        // 丸数字（①〜⑳）
        #"[①-⑳]$"#,
        // 英語
        #"vol\.?\s*[0-9]+$"#,
        #"volume\s*[0-9]+$"#,
        #"part\s*[0-9]+$"#,
        #"book\s*[0-9]+$"#,
        #"#[0-9]+$"#,
        // ローマ数字（末尾・空白区切り）
        #"\s[ivx]{1,5}$"#,
        // 韓国語
        #"[0-9]+권$"#,
        #"제[0-9]+권$"#,
        // 中国語（簡体字・繁体字）
        #"第[0-9一二三四五六七八九十百]+[册冊卷]$"#,
        // 共通: 末尾の裸数字（区切り: 空白 or 全角空白。「その1」型も拾う）
        #"[\s　][0-9０-９]{1,3}$"#,
        #"その[0-9０-９]{1,2}$"#
    ]

    static let compiled: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [])
    }

    /// 巻数トークンを繰り返し除去した文字列を返す（例: "ハリー・ポッター (3)" → "ハリー・ポッター"）。
    /// 入力は正規化済み（NFKC・小文字）であること。
    public static func strippingVolumeTokens(from normalizedText: String) -> String {
        var text = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for regex in compiled {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let swiftRange = Range(match.range, in: text) {
                    text.removeSubrange(swiftRange)
                    text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "-‐–—:：・、,　")))
                    changed = true
                }
            }
        }
        return text
    }
}
