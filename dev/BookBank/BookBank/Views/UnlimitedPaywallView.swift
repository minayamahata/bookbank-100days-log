//
//  UnlimitedPaywallView.swift
//  BookBank
//
//  Created on 2026/02/10
//

import SwiftUI
import StoreKit

/// Unlimited課金画面
struct UnlimitedPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    @State private var selectedProduct: Product?
    @State private var isRestoring = false
    
    private let themeColor = Color(hex: "A1975D")
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    
                    VStack(spacing: 24) {
                        featuresSection
                        plansSection
                        purchaseButton
                        
                        Text("年額プランは1年ごとに自動更新されます。\n解約は設定アプリからいつでも可能です。")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, 13)
                        
                        footerLinks
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .onAppear {
            selectLifetimeIfNeeded()
        }
        .onChange(of: unlimitedManager.lifetimeProduct) { _, _ in
            selectLifetimeIfNeeded()
        }
        .onChange(of: unlimitedManager.isUnlimited) { _, isUnlimited in
            if isUnlimited {
                dismiss()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Image("bg_paywall")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.4), location: 0.75),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                VStack(spacing: 0) {
                    Text("Unlimited")
                        .font(.custom("Fearlessly Authentic", size: 42))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.7),
                                .init(color: themeColor, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Text("世界の広がる方へ")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 30)
            }
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            featureRow(title: "テーマカラーを自由に選べる")
            featureRow(title: "無制限に口座を作成")
            featureRow(title: "無制限に読了リストを作成")
            featureRow(title: "本の詳細データダウンロード")
        }
        .frame(maxWidth: .infinity)
    }
    
    private func featureRow(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(themeColor)
                .frame(width: 16)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    // MARK: - Plans Section
    
    private var plansSection: some View {
        VStack(spacing: 12) {
            Text("プランを選択")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .top, spacing: 12) {
                if let yearly = unlimitedManager.yearlyProduct {
                    planCard(
                        product: yearly,
                        subtextIcon: "icon-tab-bookshelf",
                        subtext: "文庫本 約1冊分",
                        autoRenewNote: true,
                        isSelected: selectedProduct?.id == yearly.id
                    )
                }
                
                if let lifetime = unlimitedManager.lifetimeProduct {
                    planCard(
                        product: lifetime,
                        badge: "おすすめ",
                        subtextIcon: "icon-tab-bookshelf",
                        subtext: "ビジネス書 約1冊分",
                        autoRenewNote: false,
                        isSelected: selectedProduct?.id == lifetime.id
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func planCard(product: Product, badge: String? = nil, subtextIcon: String? = nil, subtext: String?, autoRenewNote: Bool = false, isSelected: Bool) -> some View {
        Button(action: {
            selectedProduct = product
        }) {
            VStack(spacing: 16) {
                Text(product.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(truncating: product.price as NSDecimalNumber).formatted())")
                        .font(.system(size: 26, weight: .bold))
                    Text(autoRenewNote ? "円／年" : "円")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(isSelected ? themeColor : .white)
                
                Text("（※自動更新）")
                    .font(.system(size: 12))
                    .foregroundColor(autoRenewNote ? .white : .clear)
                    .padding(.top, -16)
                
                if let subtext {
                    HStack(spacing: 6) {
                        if let subtextIcon {
                            Image(subtextIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        }
                        Text(subtext)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.white.opacity(0.6))
                } else {
                    Spacer().frame(height: 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? themeColor : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? themeColor : Color(white: 0.3))
                        )
                        .offset(x: 0, y: -12)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Purchase Button
    
    private var purchaseButton: some View {
        Button(action: {
            Task {
                await purchaseSelectedPlan()
            }
        }) {
            HStack(spacing: 8) {
                if unlimitedManager.isPurchasing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Unlimitedにアップグレード")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeColor)
            )
        }
        .disabled(unlimitedManager.isPurchasing || selectedProduct == nil)
        .opacity(unlimitedManager.isPurchasing || selectedProduct == nil ? 0.6 : 1)
    }
    
    // MARK: - Footer Links
    
    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button(action: {
                Task { await restorePurchases() }
            }) {
                if isRestoring {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                        .scaleEffect(0.8)
                } else {
                    Text("購入を復元")
                }
            }
            .disabled(isRestoring || unlimitedManager.isPurchasing)
            
            Text("|").padding(.horizontal, 10)
            
            Link("利用規約", destination: URL(string: "https://bookbank-share.vercel.app/terms")!)
            
            Text("|").padding(.horizontal, 10)
            
            Link("プライバシーポリシー", destination: URL(string: "https://bookbank-share.vercel.app/privacy")!)
        }
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.4))
    }
    
    // MARK: - Actions
    
    private func selectLifetimeIfNeeded() {
        if selectedProduct == nil {
            selectedProduct = unlimitedManager.lifetimeProduct ?? unlimitedManager.yearlyProduct
        }
    }
    
    private func purchaseSelectedPlan() async {
        guard let product = selectedProduct else { return }
        
        do {
            try await unlimitedManager.purchase(product)
        } catch {
            print("❌ Purchase failed: \(error)")
        }
    }
    
    private func restorePurchases() async {
        isRestoring = true
        await unlimitedManager.restorePurchases()
        isRestoring = false
    }
}

// MARK: - Preview

#Preview {
    UnlimitedPaywallView()
}
