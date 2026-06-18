//
//  AppMenuView.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI

/// アプリメニュー（テーマ切替・Unlimited・法務リンク）
struct AppMenuView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    var onDismiss: (() -> Void)?
    
    @State private var showUnlimitedPaywall = false
    @State private var safariLink: SafariLink?
    
    var body: some View {
        let _ = languageManager.currentLanguage
        let _ = currencyManager.displayCurrency

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 設定
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.section")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            NavigationLink {
                                AppearanceSettingsView()
                            } label: {
                                settingsNavigationRow(
                                    title: "settings.appearance",
                                    value: themeManager.currentTheme.titleKey
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Divider().padding(.leading, 20)
                            
                            NavigationLink {
                                LanguageSettingsView()
                            } label: {
                                settingsNavigationRow(
                                    title: "settings.language",
                                    value: languageMenuValue
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 20)

                            NavigationLink {
                                CurrencySettingsView()
                            } label: {
                                settingsNavigationRow(
                                    title: "settings.currency",
                                    value: Text(currencyManager.displayCurrency.code)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appCardBackground)
                        )
                        .padding(.horizontal, 16)
                    }

                    if showsSubscriptionSection {
                        subscriptionSection
                    }
                    
                    // サービス案内
                    VStack(alignment: .leading, spacing: 8) {
                        Text("service.section")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            menuLinkRow(titleKey: "service.terms") {
                                openInSafari("https://bookbank-share.vercel.app/terms")
                            }
                            Divider().padding(.leading, 20)
                            
                            menuLinkRow(titleKey: "service.privacy") {
                                openInSafari("https://bookbank-share.vercel.app/privacy")
                            }
                            Divider().padding(.leading, 20)
                            
                            menuLinkRow(titleKey: "service.about") {
                                openInSafari("https://ayame-inc.jp/products/bookbank")
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appCardBackground)
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("menu.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showUnlimitedPaywall) {
            UnlimitedPaywallView()
        }
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
    
    private var showsSubscriptionSection: Bool {
        !unlimitedManager.isUnlimited || unlimitedManager.hasActiveYearlySubscription
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("subscription.section")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                if !unlimitedManager.isUnlimited {
                    menuLinkRow(titleKey: "subscription.upgrade_unlimited") {
                        showUnlimitedPaywall = true
                    }
                }

                if unlimitedManager.isUnlimited && unlimitedManager.hasActiveYearlySubscription {
                    menuLinkRow(titleKey: "subscription.manage") {
                        openExternalURL("https://apps.apple.com/account/subscriptions")
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCardBackground)
            )
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var languageMenuValue: some View {
        if languageManager.currentLanguage == .system {
            Text("language.automatic")
        } else {
            Text(languageManager.currentLanguage.nativeDisplayName)
        }
    }
    
    private func settingsNavigationRow(title: LocalizedStringKey, value: some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            value
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
    
    private func settingsNavigationRow(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        settingsNavigationRow(title: title, value: Text(value))
    }
    
    private func menuLinkRow(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titleKey)
                    .font(.body)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func openInSafari(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        safariLink = SafariLink(url: url)
    }
    
    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        AppMenuView()
    }
    .environment(ThemeManager())
    .environment(LanguageManager())
    .environment(CurrencyManager())
    .environment(ExchangeRateService.shared)
}
