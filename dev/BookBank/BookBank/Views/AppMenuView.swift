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
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    var onDismiss: (() -> Void)?
    
    @State private var showUnlimitedPaywall = false
    @State private var safariLink: SafariLink?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 表示モード
                    VStack(alignment: .leading, spacing: 8) {
                        Text("表示")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        themeManager.currentTheme = theme
                                    }
                                } label: {
                                    HStack {
                                        Text(theme.displayName)
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
                                
                                if theme != AppTheme.allCases.last {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appCardBackground)
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    // サブスクリプション・リンク
                    VStack(spacing: 0) {
                        if unlimitedManager.isUnlimited && unlimitedManager.hasActiveYearlySubscription {
                            menuLinkRow(title: "サブスクリプションを管理") {
                                openExternalURL("https://apps.apple.com/account/subscriptions")
                            }
                            Divider().padding(.leading, 20)
                        }
                        
                        if !unlimitedManager.isUnlimited {
                            menuLinkRow(title: "Unlimitedにアップグレード") {
                                showUnlimitedPaywall = true
                            }
                            Divider().padding(.leading, 20)
                        }
                        
                        menuLinkRow(title: "利用規約") {
                            openInSafari("https://bookbank-share.vercel.app/terms")
                        }
                        Divider().padding(.leading, 20)
                        
                        menuLinkRow(title: "プライバシーポリシー") {
                            openInSafari("https://bookbank-share.vercel.app/privacy")
                        }
                        Divider().padding(.leading, 20)
                        
                        menuLinkRow(title: "このアプリについて") {
                            openInSafari("https://ayame-inc.jp/products/bookbank")
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appCardBackground)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("メニュー")
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
    
    private func menuLinkRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
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
}
