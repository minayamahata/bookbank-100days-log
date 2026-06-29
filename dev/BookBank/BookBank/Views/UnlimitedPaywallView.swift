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
                        
                        Text("paywall.auto_renew")
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
                    Text("paywall.unlimited")
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
                    
                    Text("paywall.tagline")
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
            featureRow(titleKey: "paywall.feature.theme")
            featureRow(titleKey: "paywall.feature.passbooks")
            featureRow(titleKey: "paywall.feature.reading_lists")
            featureRow(titleKey: "paywall.feature.download")
        }
        .frame(maxWidth: .infinity)
    }
    
    private func featureRow(titleKey: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(themeColor)
                .frame(width: 16)
            
            Text(titleKey)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    // MARK: - Plans Section
    
    private var plansSection: some View {
        VStack(spacing: 12) {
            Text("paywall.select_plan")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .top, spacing: 12) {
                if let yearly = unlimitedManager.yearlyProduct {
                    planCard(
                        product: yearly,
                        subtextIcon: "icon-tab-bookshelf",
                        subtextKey: "paywall.yearly_subtext",
                        isYearly: true,
                        isSelected: selectedProduct?.id == yearly.id
                    )
                }
                
                if let lifetime = unlimitedManager.lifetimeProduct {
                    planCard(
                        product: lifetime,
                        badgeKey: "paywall.lifetime_badge",
                        subtextIcon: "icon-tab-bookshelf",
                        subtextKey: "paywall.lifetime_subtext",
                        isSelected: selectedProduct?.id == lifetime.id
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func planCard(product: Product, badgeKey: LocalizedStringKey? = nil, subtextIcon: String? = nil, subtextKey: LocalizedStringKey? = nil, isYearly: Bool = false, isSelected: Bool) -> some View {
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
                    Text(isYearly ? "paywall.yen_per_year" : "common.yen")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(isSelected ? themeColor : .white)
                
                if let subtextKey {
                    HStack(spacing: 6) {
                        if let subtextIcon {
                            Image(subtextIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        }
                        Text(subtextKey)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.white.opacity(0.6))
                } else {
                    Spacer().frame(height: 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
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
            .overlay(alignment: .top) {
                if let badgeKey {
                    Text(badgeKey)
                        .font(.system(size: 12, weight: .bold))
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
                    Text("paywall.upgrade")
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
                    Text("paywall.restore")
                }
            }
            .disabled(isRestoring || unlimitedManager.isPurchasing)
            
            Text("|").padding(.horizontal, 10)
            
            Link("service.terms", destination: LegalLink.terms)
            
            Text("|").padding(.horizontal, 10)
            
            Link("service.privacy", destination: LegalLink.privacy)
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
            #if DEBUG
            print("❌ Purchase failed: \(error)")
            #endif
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
