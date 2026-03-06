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
            ReadingList.self
        ])
        
        // ModelContainerの設定
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
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

/// アプリのルートビュー
/// スプラッシュスクリーン → カスタム口座の有無によってオンボーディングまたはメイン画面を表示
struct RootView: View {
    @Environment(ThemeManager.self) private var themeManager
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
        }
        .onAppear {
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
