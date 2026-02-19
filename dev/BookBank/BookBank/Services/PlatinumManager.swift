//
//  PlatinumManager.swift
//  BookBank
//
//  Created on 2026/02/10
//

import Foundation
import StoreKit
import Observation

/// Platinum会員の購入・状態管理を行うシングルトン
@Observable
@MainActor
final class PlatinumManager {
    
    // MARK: - Singleton
    
    static let shared = PlatinumManager()
    
    // MARK: - Product IDs
    
    private let productIds = [
        "com.bookbank.platinum.yearly",   // 年額サブスク
        "com.bookbank.platinum.lifetime"  // 買い切り
    ]
    
    private let yearlyProductId = "com.bookbank.platinum.yearly"
    
    // MARK: - Observable Properties
    
    /// Platinum会員かどうか
    private(set) var isPlatinum: Bool = false
    
    /// 年額サブスクが有効かどうか（lifetimeのみの場合はfalse・解約管理不要のため）
    private(set) var hasActiveYearlySubscription: Bool = false
    
    /// 利用可能な商品一覧
    private(set) var products: [Product] = []
    
    /// 購入処理中かどうか
    private(set) var isPurchasing: Bool = false
    
    /// エラーメッセージ
    var errorMessage: String?
    
    // MARK: - Private Properties
    
    @ObservationIgnored
    private var transactionListener: Task<Void, Error>?
    
    // MARK: - Initialization
    
    private init() {
        // トランザクション監視を開始
        transactionListener = listenForTransactions()
        
        // 商品情報と購入状態を取得
        Task {
            await loadProducts()
            await updatePurchaseStatus()
        }
    }
    
    /// トランザクションリスナーを停止
    func stopListening() {
        transactionListener?.cancel()
        transactionListener = nil
    }
    
    // MARK: - Public Methods
    
    /// 商品を購入
    func purchase(_ product: Product) async throws {
        isPurchasing = true
        errorMessage = nil
        
        defer { isPurchasing = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // トランザクションを検証
                let transaction = try checkVerified(verification)
                
                // 購入状態を更新
                await updatePurchaseStatus()
                
                // トランザクションを完了
                await transaction.finish()
                
            case .userCancelled:
                // ユーザーがキャンセル
                break
                
            case .pending:
                // 保留中（ペアレンタルコントロールなど）
                errorMessage = "購入が保留中です。承認後に反映されます。"
                
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// 購入を復元
    func restorePurchases() async {
        do {
            // App Storeと同期
            try await AppStore.sync()
            
            // 購入状態を更新
            await updatePurchaseStatus()
        } catch {
            errorMessage = "復元に失敗しました: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    /// 商品情報を取得
    private func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
            // 年額を先に表示
            products.sort { $0.id < $1.id }
        } catch {
            print("❌ Failed to load products: \(error)")
            errorMessage = "商品情報の取得に失敗しました"
        }
    }
    
    /// 購入状態を更新
    private func updatePurchaseStatus() async {
        var hasValidEntitlement = false
        var hasYearly = false
        
        // 現在の権利を確認
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // 対象の商品IDか確認
                if productIds.contains(transaction.productID) {
                    // サブスクの場合は有効期限を確認
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            hasValidEntitlement = true
                            if transaction.productID == yearlyProductId {
                                hasYearly = true
                            }
                        }
                    } else {
                        // 買い切り（非消耗型）の場合
                        hasValidEntitlement = true
                    }
                }
            } catch {
                print("❌ Failed to verify transaction: \(error)")
            }
        }
        
        isPlatinum = hasValidEntitlement
        hasActiveYearlySubscription = hasYearly
    }
    
    /// トランザクションを監視
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // 購入状態を更新
                    await self.updatePurchaseStatus()
                    
                    // トランザクションを完了
                    await transaction.finish()
                } catch {
                    print("❌ Transaction listener error: \(error)")
                }
            }
        }
    }
    
    /// トランザクションを検証
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Convenience Properties

extension PlatinumManager {
    /// 年額サブスク商品
    var yearlyProduct: Product? {
        products.first { $0.id == "com.bookbank.platinum.yearly" }
    }
    
    /// 買い切り商品
    var lifetimeProduct: Product? {
        products.first { $0.id == "com.bookbank.platinum.lifetime" }
    }
}
