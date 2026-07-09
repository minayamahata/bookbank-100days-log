//
//  BookBankApp.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct BookBankApp: App {

    // MARK: - Properties

    /// SwiftDataのModelContainer
    let modelContainer: ModelContainer

    /// テーマ管理
    @State private var themeManager = ThemeManager()

    /// 言語管理
    @State private var languageManager = LanguageManager()

    /// 表示通貨管理
    @State private var currencyManager = CurrencyManager()

    /// 為替レート
    @State private var exchangeRateService = ExchangeRateService.shared
    
    // MARK: - Initialization
    
    init() {
        // デバッグ: 利用可能なフォント名を出力
        #if DEBUG
        for family in UIFont.familyNames.sorted() {
            if family.lowercased().contains("fearless") || family.lowercased().contains("inter") {
                print("🔤 Font Family: \(family)")
                for name in UIFont.fontNames(forFamilyName: family) {
                    print("   - \(name)")
                }
            }
        }
        #endif
        
        // ナビゲーションバーのタイトルフォントを設定
        Self.configureNavigationBarAppearance()
        
        // スキーマ定義
        let schema = Schema([
            Passbook.self,
            UserBook.self,
            Subscription.self,
            ReadingList.self,
            MonthlyMemo.self
        ])
        
        // ModelContainerの設定（プレビュー時はメモリ上のみ・サンドボックス書き込みエラーを回避）
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isPreview
        )
        
        // R3移行前バックアップ（設計メモ r3-uuid-migration-notes.md 4.5節①）:
        // 最も危険なのは直後の ModelContainer 生成時に走る軽量スキーママイグレーション。
        // ストアが開かれる前にファイル一式をコピーし、生成失敗時はバックアップから復元して1回だけ再試行する。
        let storeURL = modelConfiguration.url
        if !isPreview {
            StoreBackupManager.backupIfNeeded(storeURL: storeURL)
        }

        do {
            if isPreview {
                modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } else {
                modelContainer = try StoreBackupManager.makeContainerWithRecovery(
                    schema: schema,
                    configuration: modelConfiguration,
                    storeURL: storeURL
                )
            }
            
            // 初回起動時のデフォルトデータ作成
            initializeDefaultData()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    /// ナビゲーションバーの外観を設定
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // インラインタイトル用のフォント（.subheadline相当 = 15pt）
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular)
        ]
        
        // ラージタイトル用のフォント
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular)
        ]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeManager)
                .environment(languageManager)
                .environment(currencyManager)
                .environment(exchangeRateService)
                .environment(\.locale, languageManager.resolvedLocale)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Private Methods
    
    private func initializeDefaultData() {
        #if DEBUG
        print("✅ BookBank initialized (no default data)")
        #endif
    }
}

// MARK: - RootView

/// 初回起動時のスプラッシュ表示状態（セッション内で1回のみ）
private enum SplashPresentationState {
    static var hasScheduledInitialSplash = false
}

/// アプリのルートビュー
/// スプラッシュスクリーン → カスタム口座の有無によってオンボーディングまたはメイン画面を表示
struct RootView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRateService
    @Environment(\.modelContext) private var modelContext
    @State private var showSplash = true
    @State private var showOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            MainTabView()

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            .environment(themeManager)
            .environment(languageManager)
            .environment(currencyManager)
            .environment(exchangeRateService)
            .environment(\.locale, languageManager.resolvedLocale)
        }
        .onAppear {
            if PreviewRuntime.isActive {
                showSplash = false
                return
            }

            // R3移行（設計メモ 5.4節の実行順）: UUIDバックフィル → 並び順変換 → 通貨。
            // 1→2の順序は必須（並び順変換が uuid を参照するため）。
            UUIDBackfillMigration.migrateIfNeeded(context: modelContext)
            ReadingListOrderMigration.migrateIfNeeded(context: modelContext)
            CurrencyMigration.migrateIfNeeded(context: modelContext)

            // 全マイグレーションの検証通過後にのみ移行前バックアップを削除する
            // （設計メモ 前提9・判断点①: 全検証通過まで保険を手放さない）
            if UUIDBackfillMigration.hasCompleted,
               ReadingListOrderMigration.hasCompleted,
               let storeURL = modelContext.container.configurations.first?.url {
                StoreBackupManager.deleteBackup(storeURL: storeURL)
            }

            Task {
                await exchangeRateService.refreshIfNeeded()
            }

            guard !SplashPresentationState.hasScheduledInitialSplash else {
                showSplash = false
                return
            }
            SplashPresentationState.hasScheduledInitialSplash = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
        }
    }
}
