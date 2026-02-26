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

/// 口座のテーマカラーを管理するユーティリティ
struct PassbookColor {
    /// 利用可能なテーマカラー（最初の色はライト/ダークモードで切り替わる）
    static let colors: [Color] = [
        // ライトモード: #292826（黒）、ダークモード: #FFFFFF（白）
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 1, blue: 1, alpha: 1)  // 白
                : UIColor(red: 0x29/255.0, green: 0x28/255.0, blue: 0x26/255.0, alpha: 1)  // 黒
        }),
        Color(hex: "e11717"),  // 赤
        Color(hex: "f87221"),  // オレンジ
        Color(hex: "ecd11e"),  // 黄色
        Color(hex: "85ca0d"),  // 緑
        Color(hex: "1cbcac"),  // シアン
        Color(hex: "0549d5"),  // 青
        Color(hex: "7317e3"),  // 紫
        Color(hex: "e748a0"),  // ピンク
    ]
    
    /// HEXカラー文字列（API送信用）
    static let hexStrings: [String] = [
        "#292826",  // デフォルト（黒）
        "#e11717",  // 赤
        "#f87221",  // オレンジ
        "#ecd11e",  // 黄色
        "#85ca0d",  // 緑
        "#1cbcac",  // シアン
        "#0549d5",  // 青
        "7317e3",  // 紫
        "#e748a0",  // ピンク
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
    
    /// 口座リスト内での位置に基づいて色を取得（colorIndexがある場合はそれを優先）
    static func color(for passbook: Passbook, in passbooks: [Passbook]) -> Color {
        // colorIndexが設定されている場合はそれを使用
        if let colorIndex = passbook.colorIndex {
            return color(for: colorIndex)
        }
        // そうでなければリスト内の位置で決定
        if let index = passbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return color(for: index)
        }
        return .gray
    }
    
    /// 口座が黒テーマ（最初の色）かどうかを判定
    static func isBlackTheme(for passbook: Passbook, in passbooks: [Passbook]) -> Bool {
        // colorIndexが設定されている場合
        if let colorIndex = passbook.colorIndex {
            return colorIndex == 0
        }
        // そうでなければリスト内の位置で判定
        if let index = passbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return index == 0
        }
        return false
    }
}
