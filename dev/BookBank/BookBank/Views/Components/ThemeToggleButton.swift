//
//  ThemeToggleButton.swift
//  BookBank
//
//  Created on 2026/01/28
//

import SwiftUI

/// ナビゲーションバー用のテーマ切替メニューボタン
struct ThemeToggleButton: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Menu {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeManager.currentTheme = theme
                    }
                } label: {
                    Label {
                        Text(theme.displayName)
                    } icon: {
                        if themeManager.currentTheme == theme {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: themeManager.currentTheme.iconName)
                .font(.system(size: 10))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
