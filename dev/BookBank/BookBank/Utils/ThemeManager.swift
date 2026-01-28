//
//  ThemeManager.swift
//  BookBank
//
//  Created on 2026/01/28
//

import SwiftUI
import UIKit

// MARK: - カスタム背景色（ダークモード時にダークグレーを使用）

extension Color {
    /// ページ背景色（ライト: #F2F2F7, ダーク: #1C1C1E）
    static let appGroupedBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)  // #1C1C1E
            : .systemGroupedBackground
    })

    /// カード・セクション背景色（ライト: #FFFFFF, ダーク: #2C2C2E）
    static let appCardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1)  // #2C2C2E
            : .systemBackground
    })
}

/// アプリのテーマ設定
enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    /// 表示名
    var displayName: String {
        switch self {
        case .system: return "システムモード"
        case .light: return "ライトモード"
        case .dark: return "ダークモード"
        }
    }

    /// SF Symbols アイコン名
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// SwiftUI の ColorScheme に変換（system の場合は nil）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// アプリ全体のテーマを管理するクラス
@Observable
class ThemeManager {
    /// 現在のテーマ設定（UserDefaults に永続化）
    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
        }
    }

    init() {
        let savedValue = UserDefaults.standard.integer(forKey: "appTheme")
        self.currentTheme = AppTheme(rawValue: savedValue) ?? .system
    }
}
