//
//  FontLicense.swift
//  BookBank
//
//  同梱フォント（LINE Seed）のライセンス表示。本文は Fonts/LINESeed-OFL.txt
//  （SIL OFL 1.1 の英語原文＋© LY Corporation）をそのまま読む。原文は改変しない。
//

import Foundation

enum FontLicense {
    /// 同梱している LINE Seed ファミリー。正式名のまま表示し、翻訳しない。
    static let fontFamilies = [
        "LINE Seed Sans",
        "LINE Seed JP",
        "LINE Seed KR",
        "LINE Seed TW"
    ]

    static let copyrightNotice = "© LY Corporation"

    static let resourceName = "LINESeed-OFL"
    static let resourceExtension = "txt"

    /// バンドルからOFL本文（著作権表示を含む）を読む。オフラインで完結する。
    static func licenseText(in bundle: Bundle = AppTypography.resourceBundle) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
