import Foundation

/// 表紙画像URLの判定（楽天APIの noimage プレースホルダー対応）
enum BookCoverImageURL {
    /// 楽天APIが返す「画像なし」プレースホルダーかどうか
    static func isRakutenPlaceholder(_ urlString: String?) -> Bool {
        guard let urlString, !urlString.isEmpty else { return false }
        return urlString.lowercased().contains("noimage")
    }

    /// 表示・保存に使える表紙URLかどうか
    static func isValid(_ urlString: String?) -> Bool {
        guard let urlString, !urlString.isEmpty,
              URL(string: urlString) != nil else {
            return false
        }
        return !isRakutenPlaceholder(urlString)
    }

    /// 有効な表紙URLのみ返す（プレースホルダーは nil）
    static func normalized(_ urlString: String?) -> String? {
        isValid(urlString) ? urlString : nil
    }
}
