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
        Color(hex: "fe2b2c"),  // 赤
        Color(hex: "fd8e0f"),  // オレンジ
        Color(hex: "fdd00e"),  // 黄色
        Color(hex: "30cd47"),  // 緑
        Color(hex: "33c6dd"),  // シアン
        Color(hex: "1398ff"),  // 青
        Color(hex: "b780ff"),  // 紫
        Color(hex: "fd82c3"),  // ピンク
    ]
    
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
}
