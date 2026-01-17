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
            MainTabView()
        }
        .modelContainer(modelContainer)
    }
    
    // MARK: - Private Methods
    
    /// 初回起動時のデフォルトデータを作成
    private func initializeDefaultData() {
        let context = modelContainer.mainContext
        
        // 総合口座が存在するかチェック
        let fetchDescriptor = FetchDescriptor<Passbook>()
        
        do {
            let allPassbooks = try context.fetch(fetchDescriptor)
            let existingOverallPassbooks = allPassbooks.filter { $0.type == .overall }
            
            // 総合口座が存在しない場合のみ作成
            if existingOverallPassbooks.isEmpty {
                let overallPassbook = Passbook.createOverall()
                context.insert(overallPassbook)
                try context.save()
                print("✅ Default 'Overall Passbook' created")
            }
        } catch {
            print("❌ Error initializing default data: \(error)")
        }
    }
}
