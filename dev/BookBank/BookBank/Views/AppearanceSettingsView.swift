//
//  AppearanceSettingsView.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI

/// 外観（ライト / ダーク）設定画面
struct AppearanceSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            themeManager.currentTheme = theme
                        }
                    } label: {
                        HStack {
                            Text(theme.titleKey)
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if themeManager.currentTheme == theme {
                                Image(systemName: "checkmark")
                                    .font(.body)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < AppTheme.allCases.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCardBackground)
            )
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("settings.appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environment(ThemeManager())
}
