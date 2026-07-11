import Foundation

/// 正規化（設計書 3.2節 手順1・2.2節のシリーズ名正規化）
public enum Normalization {

    /// テキスト共通の正規化: NFKC → 小文字化 → 前後空白除去
    public static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// シリーズ名の一致判定キー（S-A）: NFKC・小文字化・空白除去・巻数除去
    public static func seriesKey(_ seriesName: String) -> String {
        let stripped = VolumePatterns.strippingVolumeTokens(from: normalize(seriesName))
        return stripped.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }

    /// 著者名の正規化（設計書 4.2節）:
    /// - NFKC・小文字化
    /// - ラテン文字名は「姓, 名」→「名 姓」ゆれの吸収とミドルネームイニシャルの除去
    /// - 日本語名⇔ローマ字名の同定はスコープ外
    public static func authorKey(_ author: String) -> String {
        var name = normalize(author)
        // 複数著者の先頭のみ（区切り: 「/」「,」は姓名反転と衝突するため「/」「;」「・」のみ）
        if let first = name.split(whereSeparator: { "/;・".contains($0) }).first {
            name = String(first).trimmingCharacters(in: .whitespaces)
        }
        let isLatin = name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII || CharacterSet.whitespaces.contains(scalar)
                || CharacterSet(charactersIn: ",.-'").contains(scalar)
        }
        guard isLatin else {
            return name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        }
        // "rowling, j. k." → "j. k. rowling"
        if name.contains(",") {
            let parts = name.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 {
                name = "\(parts[1]) \(parts[0])"
            }
        }
        // ミドルネームイニシャル（"j. k." のような1文字+ピリオド）を除去し、語順を保った素の語列に
        let words = name.split(separator: " ").map(String.init).filter { word in
            let bare = word.replacingOccurrences(of: ".", with: "")
            return bare.count > 1
        }
        return words.joined(separator: " ")
    }
}
