//
//  PassbookColor.swift
//  BookBank
//
//  Created on 2026/01/24
//

import SwiftUI
import SwiftData

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

/// 吹き出し用の三角形シェイプ
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 口座のテーマカラーを管理するユーティリティ
struct PassbookColor {
    /// 利用可能なテーマカラー（黒は最後に配置）
    static let colors: [Color] = [
        Color(hex: "D23823"),  // 赤
        Color(hex: "E88759"),  // オレンジ
        Color(hex: "DDC214"),  // 黄色
        Color(hex: "85ca0d"),  // 黄緑
        Color(hex: "1cbcac"),  // シアン
        Color(hex: "38b844"),  // 緑
        Color(hex: "0549d5"),  // 青
        Color(hex: "7F5CCF"),  // 紫
        Color(hex: "ec759c"),  // ピンク
        // ライトモード: #292826（黒）、ダークモード: #FFFFFF（白）
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 1, blue: 1, alpha: 1)  // 白
                : UIColor(red: 0x29/255.0, green: 0x28/255.0, blue: 0x26/255.0, alpha: 1)  // 黒
        }),
        Color(hex: "918658"),  // ゴールド
    ]
    
    /// HEXカラー文字列（API送信用）
    static let hexStrings: [String] = [
        "#D23823",  // 赤
        "#E88759",  // オレンジ
        "#DDC214",  // 黄色
        "#85ca0d",  // 黄緑
        "#1cbcac",  // シアン
        "#38b844",  // 緑
        "#0549d5",  // 青
        "#7F5CCF",  // 紫
        "#ec759c",  // ピンク
        "#292826",  // 黒
        "#918658",  // ゴールド
    ]
    
    /// インデックスに対応するHEXカラー文字列を取得
    static func hexString(for index: Int) -> String {
        hexStrings[index % hexStrings.count]
    }
    
    /// カラーの数
    static var count: Int {
        colors.count
    }
    
    /// 口座のインデックスに基づいて色を取得
    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
    
    /// 口座のsortOrderに基づいて色を取得
    static func color(for passbook: Passbook) -> Color {
        color(for: passbook.sortOrder)
    }
    
    /// 口座リスト内での位置に基づいて色を取得（customColorHex → colorIndex → リスト位置の優先順）
    static func color(for passbook: Passbook, in passbooks: [Passbook]) -> Color {
        if let hex = passbook.customColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        if let colorIndex = passbook.colorIndex {
            return color(for: colorIndex)
        }
        if let index = passbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return color(for: index)
        }
        return .gray
    }
    
    /// 黒テーマのインデックス（ピンクの次、ゴールドの前）
    static let blackThemeIndex: Int = 9
    
    /// 口座が黒テーマかどうかを判定
    static func isBlackTheme(for passbook: Passbook, in passbooks: [Passbook]) -> Bool {
        if passbook.customColorHex != nil {
            return false
        }
        if let colorIndex = passbook.colorIndex {
            return colorIndex == blackThemeIndex
        }
        if let index = passbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return (index % colors.count) == blackThemeIndex
        }
        return false
    }
    
    /// Color → HEX文字列に変換
    static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
