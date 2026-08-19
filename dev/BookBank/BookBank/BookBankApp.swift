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

    /// データアクセス（R4・View接続はステップ2以降）
    @State private var repositories: AppRepositories
    
    // MARK: - Initialization
    
    init() {
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
        
        // 移行前バックアップ（R3: r3-uuid-migration-notes.md 4.5節① / R4.7: reread-history-spec.md 12.1）:
        // 最も危険なのは直後の ModelContainer 生成時に走る軽量スキーママイグレーション。
        // ストアが開かれる前にファイル一式をコピーし、生成失敗時は R4.7 を優先、なければ R3 から復元して1回だけ再試行する。
        let storeURL = modelConfiguration.url
        if !isPreview {
            StoreBackupManager.backupIfNeeded(storeURL: storeURL)
            StoreBackupManager.backupIfNeeded(storeURL: storeURL, kind: .rereadSchemaV1)
        }

        do {
            let container: ModelContainer
            if isPreview {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } else {
                container = try StoreBackupManager.makeContainerWithRecovery(
                    schema: schema,
                    configuration: modelConfiguration,
                    storeURL: storeURL
                )
            }
            modelContainer = container
            _repositories = State(initialValue: AppRepositories(container: container))
            
            // 初回起動時のデフォルトデータ作成
            initializeDefaultData()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    /// ナビゲーションバーの外観を設定。言語変更時にも呼び、新しいバーへ反映する。
    /// `UINavigationBar.appearance()` は既に表示中のバーへは即時反映されないことがある。
    static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        let titleFont = AppTypography.uiFont(size: 15, relativeTo: .subheadline, weight: .regular)
        appearance.titleTextAttributes = [
            .font: titleFont
        ]
        appearance.largeTitleTextAttributes = [
            .font: titleFont
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
                .environment(repositories)
                .environment(\.locale, languageManager.resolvedLocale)
                .lineSpacing(AppTypography.interfaceLineSpacing(for: languageManager.currentLanguage))
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
    @Environment(AppRepositories.self) private var repositories
    @Environment(\.modelContext) private var modelContext
    @State private var showSplash = true
    @State private var showOnboarding = false
    @State private var showWhatsNew = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            MainTabView()

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if showWhatsNew {
                WhatsNewView(
                    onClose: {
                        // 「×」= 一時的に閉じる。確認済みにはしない
                        showWhatsNew = false
                    },
                    onConfirm: {
                        WhatsNewStore().markConfirmed()
                        showWhatsNew = false
                    }
                )
                .zIndex(2)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
                // 新規ユーザー: オンボーディングの閉じアニメーション後に自動表示を判定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    attemptAutoShowWhatsNew()
                }
            }
            .environment(themeManager)
            .environment(languageManager)
            .environment(currencyManager)
            .environment(exchangeRateService)
            .environment(repositories)
            .environment(\.locale, languageManager.resolvedLocale)
            .lineSpacing(AppTypography.interfaceLineSpacing(for: languageManager.currentLanguage))
        }
        .onChange(of: languageManager.currentLanguage) { _, _ in
            BookBankApp.configureNavigationBarAppearance()
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
                RereadSchemaValidation.finalizeIfValid(context: modelContext, storeURL: storeURL)
            }

            // マイグレーションはリポジトリ外書き込みのためパルスに乗らない（設計メモ 4.3節）。
            // 子Viewの .task が先に購読していた場合、バックフィル前uuidのDTOを掴み続ける穴を塞ぐ。
            repositories.notifyExternalChange()

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
                } else {
                    // 既存ユーザー: スプラッシュのフェード完了後に自動表示を判定
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        attemptAutoShowWhatsNew()
                    }
                }
            }
        }
    }

    /// 新機能のお知らせの自動表示（docs/whats-new-message-design.md 5章）。
    /// 表示が実際に始まる時点で回数を+1し、同一起動内の再実行は起動内状態で防ぐ。
    private func attemptAutoShowWhatsNew() {
        guard !PreviewRuntime.isActive else { return }
        let store = WhatsNewStore()
        guard WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: hasCompletedOnboarding,
            isConfirmed: store.isConfirmed,
            autoShowCount: store.autoShowCount,
            hasAutoShownThisLaunch: WhatsNewSessionState.launchSession.hasAutoShown
        ) else { return }

        WhatsNewSessionState.launchSession.markAutoShown()
        // 一時スイッチ中は保存状態を汚さない（回数を加算しない）
        if !WhatsNewAutoShowPolicy.temporarilyAlwaysAutoShow {
            store.recordAutoShowStarted()
        }
        showWhatsNew = true
    }
}
