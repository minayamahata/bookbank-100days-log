//
//  LanguageSettingsView.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI

/// 言語設定画面
struct LanguageSettingsView: View {
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                    Button {
                        languageManager.currentLanguage = language
                    } label: {
                        HStack {
                            if language == .system {
                                Text("language.automatic")
                                    .font(.body)
                                    .foregroundColor(.primary)
                            } else {
                                Text(language.nativeDisplayName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            if languageManager.currentLanguage == language {
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

                    if index < AppLanguage.allCases.count - 1 {
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
        .navigationTitle("settings.language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 表示通貨設定画面
struct CurrencySettingsView: View {
    @Environment(CurrencyManager.self) private var currencyManager

    @State private var pendingCurrency: AppCurrency?
    @State private var showChangeAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(AppCurrency.allCases.enumerated()), id: \.element.id) { index, currency in
                    Button {
                        selectCurrency(currency)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(currency.nameKey))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(currency.code)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if currencyManager.displayCurrency == currency {
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

                    if index < AppCurrency.allCases.count - 1 {
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
        .navigationTitle("settings.currency")
        .navigationBarTitleDisplayMode(.inline)
        .alert("currency.change.title", isPresented: $showChangeAlert) {
            Button("common.cancel", role: .cancel) {
                pendingCurrency = nil
            }
            Button("currency.change.confirm") {
                if let pendingCurrency {
                    currencyManager.displayCurrency = pendingCurrency
                }
                pendingCurrency = nil
            }
        } message: {
            Text("currency.change.message")
        }
    }

    private func selectCurrency(_ currency: AppCurrency) {
        guard currency != currencyManager.displayCurrency else { return }
        pendingCurrency = currency
        showChangeAlert = true
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
    .environment(LanguageManager())
}
