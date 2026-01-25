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
    
    // MARK: - Initialization
    
    init() {
        // ナビゲーションバーのタイトルフォントを設定
        Self.configureNavigationBarAppearance()
        
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
    
    /// ナビゲーションバーの外観を設定
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // インラインタイトル用のフォント（.subheadline相当 = 15pt）
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold)
        ]
        
        // ラージタイトル用のフォント
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold)
        ]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
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
        #if DEBUG
        // デバッグビルド時のみテストデータを自動生成
        generateTestDataIfNeeded()
        #else
        // リリースビルドでは何もしない
        print("✅ BookBank initialized (no default data)")
        #endif
    }
    
    #if DEBUG
    /// デバッグ用のテストデータを生成（初回起動時のみ）
    private func generateTestDataIfNeeded() {
        let context = modelContainer.mainContext
        
        // 既にデータがある場合はスキップ
        let descriptor = FetchDescriptor<Passbook>()
        let existingPassbooks = (try? context.fetch(descriptor)) ?? []
        
        if !existingPassbooks.isEmpty {
            print("✅ BookBank initialized (existing data found)")
            return
        }
        
        print("🔧 DEBUG: Generating test data...")
        
        // テスト用の口座を作成
        let testPassbooks = [
            Passbook(name: "技術書", type: .custom, sortOrder: 1),
            Passbook(name: "漫画", type: .custom, sortOrder: 2),
            Passbook(name: "小説", type: .custom, sortOrder: 3)
        ]
        
        for passbook in testPassbooks {
            context.insert(passbook)
        }
        
        // 各月にテストデータを作成（2024年、2025年、2026年）
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        for year in [currentYear - 2, currentYear - 1, currentYear] {
            // 各年の月数を決定（現在の年は今月まで）
            let maxMonth = (year == currentYear) ? calendar.component(.month, from: Date()) : 12
            
            for month in 1...maxMonth {
                // 各月に1〜3冊のランダムな本を登録
                let booksInMonth = Int.random(in: 1...3)
                
                for _ in 0..<booksInMonth {
                    var components = DateComponents()
                    components.year = year
                    components.month = month
                    components.day = Int.random(in: 1...28)
                    
                    if let date = calendar.date(from: components) {
                        // ランダムに口座を選択
                        let randomPassbook = testPassbooks.randomElement()!
                        
                        let book = UserBook(
                            title: "テスト書籍 \(year)年\(month)月",
                            author: "著者名",
                            isbn: "",
                            price: Int.random(in: 800...8000),
                            passbook: randomPassbook
                        )
                        // 登録日を手動で設定
                        book.registeredAt = date
                        context.insert(book)
                    }
                }
            }
        }
        
        // データを保存
        do {
            try context.save()
            print("✅ DEBUG: Test data generated successfully")
        } catch {
            print("❌ DEBUG: Failed to save test data: \(error)")
        }
    }
    #endif
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
