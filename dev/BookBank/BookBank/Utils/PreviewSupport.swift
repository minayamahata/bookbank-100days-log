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

        let manual = UserBook(
            title: "サンプル書籍",
            author: "著者",
            price: 1500,
            source: .manual,
            passbook: manga,
            currencyCode: AppCurrency.jpy.code
        )
        context.insert(manual)

        // `source` の差分をプレビューで見るために API 取得の本も置く（8.3節-5(a)）
        let api = UserBook(
            title: "APIで取得した本",
            author: "海外の著者",
            isbn: "9784000000000",
            publisher: "サンプル出版",
            publishedYear: 2024,
            price: 3200,
            imageURL: "https://example.invalid/cover.jpg",
            source: .api,
            passbook: tech,
            currencyCode: AppCurrency.jpy.code
        )
        context.insert(api)
        try? context.save()
        return container
    }()

    /// プレビュー用リポジトリ束（インメモリSwiftData実装・設計メモ 5.5節）
    @MainActor
    static let repositories = AppRepositories(container: modelContainer)

    @MainActor
    static func passbook(named name: String) -> PassbookDTO? {
        let descriptor = FetchDescriptor<Passbook>()
        let passbooks = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return passbooks.first { $0.name == name }.map(ModelDTOMapping.passbookDTO(from:))
    }

    /// プレビュー用の書籍DTO（R4ステップ4: 各 `#Preview` の `@Model` fetch を置き換える）。
    ///
    /// `source` で指定するのは、`EditBookView` のように手動登録／API取得で入力欄の出方が
    /// 変わる画面が両方をプレビューできるようにするため（8.3節-5(a)）
    @MainActor
    static func book(source: BookSource) -> BookDTO? {
        let descriptor = FetchDescriptor<UserBook>()
        let books = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        return books.first { $0.source == source }.map(ModelDTOMapping.bookDTO(from:))
    }

    /// プレビュー用の読了リストDTO（R4ステップ5）
    @MainActor
    static func sampleReadingList() -> ReadingListDTO {
        let books = [book(source: .manual), book(source: .api)].compactMap { $0 }
        let now = Date()
        return ReadingListDTO(
            id: "preview-reading-list",
            title: "2024年ベスト",
            description: "今年読んで良かった本たち",
            colorIndex: 10,
            bookIds: books.map(\.id),
            books: books,
            createdAt: now,
            updatedAt: now,
            legacyShareId: "preview-share-id"
        )
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

    /// カプセルの塗りを横方向グラデーション（左=tint70% → 右=tint100%）にする
    /// 縁取りは右下の＋ボタン（リキッドグラス）と同じ光沢リム風
    @ViewBuilder
    func passbookCapsuleGradient(tint: Color) -> some View {
        let fill = LinearGradient(
            colors: [tint.opacity(0.4), tint],
            startPoint: .leading,
            endPoint: .trailing
        )
        let glassRim = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.55), location: 0),
                .init(color: .white.opacity(0.14), location: 0.5),
                .init(color: .primary.opacity(0.1), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(glassRim, lineWidth: 0.5))
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
            .environment(PreviewSupport.repositories)
            .environment(\.locale, PreviewSupport.languageManager.resolvedLocale)
            .modelContainer(PreviewSupport.modelContainer)
    }
}
