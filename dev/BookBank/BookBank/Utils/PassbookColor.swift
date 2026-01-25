//
//  PassbookColor.swift
//  BookBank
//
//  Created on 2026/01/24
//

import SwiftUI
import SwiftData

/// 口座のテーマカラーを管理するユーティリティ
struct PassbookColor {
    /// 利用可能なテーマカラー
    static let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint,
        .red, .yellow, .teal, .brown
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
