import SwiftUI

extension Color {
    /// 成分を取得できなかったときの安全側の既定輝度（G-6）。
    /// 従来は取得失敗時に成分が 0 のまま＝輝度 0 となり、常に白字が選ばれていた。
    /// ここでは「明るい背景に黒字」を既定とする（`> 0.5` で黒字になる 0.5 より上に置く）。
    /// - Note: 通常はダイナミック/P3 でも下の `sRGBComponents` が値を取り出せるため、
    ///   この既定に落ちるのは色空間変換まで失敗する例外時のみ。
    static let fallbackLuminance: Double = 0.6

    /// 色の輝度（明るさ）を計算（0.0〜1.0）。
    /// 取得できない色空間（ダイナミック/P3 等）でも成分を取り直し、
    /// それでも失敗する場合は安全側の既定値を返す。
    var luminance: Double {
        guard let rgb = Color.sRGBComponents(from: UIColor(self)) else {
            return Color.fallbackLuminance
        }
        return Color.relativeLuminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// sRGB 成分（0〜1）から相対輝度を求める純関数（ITU-R BT.601）。
    static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// `UIColor` から sRGB の RGB 成分（0〜1）を取り出す。
    ///
    /// `getRed(_:green:blue:alpha:)` はダイナミックカラーや sRGB 以外の色空間（P3 など）で
    /// false を返し、成分が 0 のまま残ることがある（G-6 の原因）。その場合は
    /// 現在のトレイトで色を解決し、明示的に sRGB 色空間へ変換してから取り出す。
    /// - Returns: 取得できた成分。どの経路でも取り出せなければ nil。
    static func sRGBComponents(from uiColor: UIColor) -> (red: Double, green: Double, blue: Double)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // 1. まず素直に取得（多くの sRGB 色はここで成功）
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue))
        }

        // 2. ダイナミックカラー等は現在のトレイトで解決してから再取得
        let resolved = uiColor.resolvedColor(with: .current)
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue))
        }

        // 3. sRGB 色空間へ明示変換して成分を取り出す（P3 等の最終手段）
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = resolved.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        return (Double(components[0]), Double(components[1]), Double(components[2]))
    }

    var contrastingTextColor: Color {
        luminance > 0.5 ? .black : .white
    }
    
    var contrastingSecondaryTextColor: Color {
        luminance > 0.5 ? .black.opacity(0.6) : .white.opacity(0.7)
    }
}
