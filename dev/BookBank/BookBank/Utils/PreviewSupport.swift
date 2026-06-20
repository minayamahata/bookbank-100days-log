//
//  PreviewSupport.swift
//  BookBank
//

import SwiftData
import SwiftUI

enum PreviewRuntime {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

enum PreviewSupport {
    static let languageManager = LanguageManager()
    static let currencyManager = CurrencyManager()
    static let exchangeRates = ExchangeRateService.shared

    @MainActor
    static let modelContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Passbook.self, UserBook.self, ReadingList.self, MonthlyMemo.self,
            configurations: config
        )
        let context = container.mainContext

        let manga = Passbook(name: "漫画", type: .custom, sortOrder: 0)
        manga.colorIndex = 0
        let tech = Passbook(name: "技術書", type: .custom, sortOrder: 1)
        tech.colorIndex = 1
        context.insert(manga)
        context.insert(tech)

        let book = UserBook(
            title: "サンプル書籍",
            author: "著者",
            price: 1500,
            source: .manual,
            passbook: manga,
            currencyCode: AppCurrency.jpy.code
        )
        context.insert(book)
        try? context.save()
        return container
    }()

    @MainActor
    static func passbook(named name: String) -> Passbook? {
        let descriptor = FetchDescriptor<Passbook>()
        let passbooks = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return passbooks.first { $0.name == name }
    }
}

extension View {
    @ViewBuilder
    func passbookCapsuleGlass(tint: Color) -> some View {
        if PreviewRuntime.isActive {
            background(tint.opacity(0.25), in: Capsule())
        } else {
            glassEffect(.regular.tint(tint))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    func passbookCircleGlass(tint: Color) -> some View {
        if PreviewRuntime.isActive {
            background(tint.opacity(0.25), in: Circle())
        } else {
            glassEffect(.regular.tint(tint))
                .clipShape(Circle())
        }
    }

    func bookBankPreviewEnvironment() -> some View {
        self
            .environment(ThemeManager())
            .environment(PreviewSupport.languageManager)
            .environment(PreviewSupport.currencyManager)
            .environment(PreviewSupport.exchangeRates)
            .environment(\.locale, PreviewSupport.languageManager.resolvedLocale)
            .modelContainer(PreviewSupport.modelContainer)
    }
}
