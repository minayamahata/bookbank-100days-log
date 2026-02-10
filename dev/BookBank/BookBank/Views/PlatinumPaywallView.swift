//
//  PlatinumPaywallView.swift
//  BookBank
//
//  Created on 2026/02/10
//

import SwiftUI
import StoreKit

/// Platinum課金画面
struct PlatinumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private var platinumManager: PlatinumManager { PlatinumManager.shared }
    
    @State private var selectedProduct: Product?
    @State private var isRestoring = false
    
    // プラチナカードをイメージしたグラデーション
    private let platinumGradient = LinearGradient(
        colors: [
            Color(red: 180/255, green: 180/255, blue: 190/255),  // シルバー
            Color(red: 220/255, green: 220/255, blue: 230/255),  // プラチナ
            Color(red: 200/255, green: 200/255, blue: 210/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 背景のダークグラデーション
    private let darkBackground = LinearGradient(
        colors: [
            Color(red: 20/255, green: 20/255, blue: 25/255),
            Color(red: 30/255, green: 30/255, blue: 40/255)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                darkBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // ヘッダー
                        headerSection
                        
                        // 特典セクション
                        featuresSection
                        
                        // プラン選択
                        plansSection
                        
                        // 購入ボタン
                        purchaseButton
                        
                        // 復元リンク
                        restoreButton
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 16))
                    }
                }
            }
            .onAppear {
                // 初期選択: 年額プラン
                if selectedProduct == nil {
                    selectedProduct = platinumManager.yearlyProduct
                }
            }
            .onChange(of: platinumManager.isPlatinum) { _, isPlatinum in
                // 購入完了後に自動でdismiss
                if isPlatinum {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Platinumアイコン
            ZStack {
                Circle()
                    .fill(platinumGradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: .white.opacity(0.3), radius: 20)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 30/255, green: 30/255, blue: 40/255),
                                Color(red: 50/255, green: 50/255, blue: 60/255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // タイトル
            Text("BookBank")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Platinum")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(platinumGradient)
            
            Text("すべての機能を無制限に")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(spacing: 16) {
            featureRow(
                icon: "building.columns",
                title: "口座を無制限に作成",
                description: "読書ジャンルや目的に応じて、好きなだけ口座を作成できます"
            )
            
            featureRow(
                icon: "list.bullet.rectangle",
                title: "読了リストを無制限に作成",
                description: "あなたの読書記録を自由に整理・共有できます"
            )
            
            featureRow(
                icon: "arrow.down.doc",
                title: "詳細データのエクスポート",
                description: "書籍の詳細情報を含むマークダウンをダウンロード"
            )
        }
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // アイコン
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // テキスト
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Plans Section
    
    private var plansSection: some View {
        VStack(spacing: 12) {
            Text("プランを選択")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                // 年額プラン
                if let yearly = platinumManager.yearlyProduct {
                    planCard(
                        product: yearly,
                        badge: "おすすめ",
                        subtext: "月あたり82円",
                        isSelected: selectedProduct?.id == yearly.id
                    )
                }
                
                // 買い切りプラン
                if let lifetime = platinumManager.lifetimeProduct {
                    planCard(
                        product: lifetime,
                        badge: "一生使える",
                        subtext: nil,
                        isSelected: selectedProduct?.id == lifetime.id
                    )
                }
            }
        }
    }
    
    private func planCard(product: Product, badge: String, subtext: String?, isSelected: Bool) -> some View {
        Button(action: {
            selectedProduct = product
        }) {
            VStack(spacing: 12) {
                // バッジ
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? AnyShapeStyle(platinumGradient) : AnyShapeStyle(Color.white.opacity(0.2)))
                    )
                
                // プラン名
                Text(product.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 価格
                Text(product.displayPrice)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                // サブテキスト
                if let subtext = subtext {
                    Text(subtext)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text(" ")
                        .font(.system(size: 11))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? AnyShapeStyle(platinumGradient) : AnyShapeStyle(Color.white.opacity(0.2)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
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
                if platinumManager.isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Platinumにアップグレード")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(platinumGradient)
            )
            .shadow(color: .white.opacity(0.3), radius: 10)
        }
        .disabled(platinumManager.isPurchasing || selectedProduct == nil)
        .opacity(platinumManager.isPurchasing || selectedProduct == nil ? 0.6 : 1)
    }
    
    // MARK: - Restore Button
    
    private var restoreButton: some View {
        Button(action: {
            Task {
                await restorePurchases()
            }
        }) {
            HStack(spacing: 6) {
                if isRestoring {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .scaleEffect(0.8)
                } else {
                    Text("購入を復元")
                        .font(.system(size: 14))
                }
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.vertical, 8)
        }
        .disabled(isRestoring || platinumManager.isPurchasing)
    }
    
    // MARK: - Actions
    
    private func purchaseSelectedPlan() async {
        guard let product = selectedProduct else { return }
        
        do {
            try await platinumManager.purchase(product)
        } catch {
            // エラーハンドリング（エラーメッセージはPlatinumManagerで管理）
            print("❌ Purchase failed: \(error)")
        }
    }
    
    private func restorePurchases() async {
        isRestoring = true
        await platinumManager.restorePurchases()
        isRestoring = false
    }
}

// MARK: - Preview

#Preview {
    PlatinumPaywallView()
}
