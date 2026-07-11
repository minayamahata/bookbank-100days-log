//
//  AppMenuView.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI
#if DEBUG
import UniformTypeIdentifiers
#endif

/// アプリメニュー（テーマ切替・Unlimited・法務リンク）
struct AppMenuView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }

    var onDismiss: (() -> Void)?
    
    @State private var showUnlimitedPaywall = false
    @State private var safariLink: SafariLink?

    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    @State private var showN0Exporter = false
    @State private var n0ExportDocument = N0SpikeJSONDocument(text: "")
    @State private var showN0ExportError = false
    @State private var n0ExportErrorMessage = ""
    #endif
    
    var body: some View {
        let _ = themeManager.currentTheme
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
                                settingsNavigationRow(title: "settings.appearance")
                            }
                            .buttonStyle(.plain)
                            
                            Divider().padding(.leading, 20)
                            
                            NavigationLink {
                                LanguageSettingsView()
                            } label: {
                                settingsNavigationRow(title: "settings.language")
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 20)

                            NavigationLink {
                                CurrencySettingsView()
                            } label: {
                                settingsNavigationRow(title: "settings.currency")
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 20)

                            NavigationLink {
                                SearchDatabaseSettingsView()
                            } label: {
                                settingsNavigationRow(title: "settings.search_database")
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
                                openInSafari(LegalLink.terms.absoluteString)
                            }
                            Divider().padding(.leading, 20)
                            
                            menuLinkRow(titleKey: "service.privacy") {
                                openInSafari(LegalLink.privacy.absoluteString)
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

                    // レビューを書く（App Store のレビュー投稿ページを開く）
                    VStack(spacing: 0) {
                        menuLinkRow(titleKey: "service.write_review") {
                            openExternalURL("https://apps.apple.com/app/id6759006906?action=write-review")
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appCardBackground)
                    )
                    .padding(.horizontal, 16)

                    #if DEBUG
                    n0SpikeExportSection
                    #endif
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("menu.title")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
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
        #if DEBUG
        .fileExporter(
            isPresented: $showN0Exporter,
            document: n0ExportDocument,
            contentType: .json,
            defaultFilename: "shelf-export.json"
        ) { _ in }
        .alert(Text(verbatim: "エクスポート失敗"), isPresented: $showN0ExportError) {
            Button(role: .cancel) {} label: { Text(verbatim: "OK") }
        } message: {
            Text(verbatim: n0ExportErrorMessage)
        }
        #endif
    }

    #if DEBUG
    /// N0スパイク用の本棚JSONエクスポート（DEBUGビルド限定・docs/n0-spike-plan.md 3.2節）
    private var n0SpikeExportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "DEBUG")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Button {
                    exportN0SpikeJSON()
                } label: {
                    HStack {
                        Text(verbatim: "N0スパイク用JSONエクスポート")
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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCardBackground)
            )
            .padding(.horizontal, 16)
        }
    }

    private func exportN0SpikeJSON() {
        do {
            let json = try generateN0SpikeExportJSON(context: modelContext)
            n0ExportDocument = N0SpikeJSONDocument(text: json)
            showN0Exporter = true
        } catch {
            n0ExportErrorMessage = error.localizedDescription
            showN0ExportError = true
        }
    }
    #endif
    
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

    private func settingsNavigationRow(title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
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
