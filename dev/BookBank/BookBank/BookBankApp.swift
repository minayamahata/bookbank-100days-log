//
//  BookBankApp.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/11.
//

import SwiftUI
import SwiftData

@main
struct BookBankApp: App {
    
    // MARK: - Properties
    
    /// SwiftDataのModelContainer
    let modelContainer: ModelContainer
    
    // MARK: - Initialization
    
    init() {
        // スキーマ定義
        let schema = Schema([
            Passbook.self,
            UserBook.self,
            Subscription.self
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
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Private Methods
    
    /// 初回起動時のデフォルトデータを作成
    /// 新仕様: 総合口座は作成せず、カスタム口座のみ管理
    private func initializeDefaultData() {
        // 現在は何もしない（オンボーディングで最初の口座を作成）
        print("✅ BookBank initialized (no default data)")
    }
}

// MARK: - RootView

/// アプリのルートビュー
/// カスタム口座の有無によってオンボーディングまたはメイン画面を表示
struct RootView: View {
    @Query private var passbooks: [Passbook]
    @State private var showOnboarding = false
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom }
    }
    
    var body: some View {
        Group {
            if customPassbooks.isEmpty {
                // カスタム口座がない場合はオンボーディングを表示
                Color.clear
                    .onAppear {
                        showOnboarding = true
                    }
            } else {
                // カスタム口座がある場合はメイン画面を表示
                MainTabView()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}
