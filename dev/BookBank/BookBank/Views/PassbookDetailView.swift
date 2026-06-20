//
//  PassbookDetailView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/14.
//

import SwiftUI
import SwiftData

/// スクロール折りたたみ進捗（コンパクトヘッダー専用・画面全体の再描画を避ける）
@Observable
final class PassbookScrollCollapse {
    var progress: CGFloat = 0
}

/// 通帳画面
/// 選択した口座の詳細と、登録されている書籍の一覧を表示
struct PassbookDetailView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nil = 総合口座）
    let passbook: Passbook?
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// 画面を閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    /// カラースキーム（ライト/ダークモード）
    @Environment(\.colorScheme) private var colorScheme

    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(AppShellState.self) private var appShellState
    
    // MARK: - State
    
    /// コラプス進捗はコンパクトヘッダーだけが購読（リスト全体の再描画を防ぐ）
    @State private var scrollCollapse = PassbookScrollCollapse()
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        if let passbook {
            return allUserBooks.filter { book in
                book.passbook?.persistentModelID == passbook.persistentModelID
            }
        }
        return allUserBooks
    }
    
    /// 合計金額（表示通貨）
    private var totalValue: Int {
        userBooks.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    /// 今日の日付文字列
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    /// 登録書籍数
    private var bookCount: Int {
        userBooks.count
    }
    
    /// カスタム口座のリスト
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// 総合口座かどうか
    private var isOverallAccount: Bool {
        passbook == nil
    }

    /// この口座のテーマカラー
    private var themeColor: Color {
        if let passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return PassbookColor.overallAccentColor
    }

    /// UIアクセントカラー
    private var accentColor: Color {
        isOverallAccount ? PassbookColor.overallAccentColor : themeColor
    }
    
    /// テーマカラーが黒かどうか
    private var isBlackTheme: Bool {
        guard let passbook else { return false }
        return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
    }
    
    /// 本の登録先口座（総合口座表示時は先頭のカスタム口座）
    private var registrationPassbook: Passbook? {
        passbook ?? customPassbooks.first
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook?) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        let _ = currencyManager.displayCurrency
        let _ = exchangeRates.lastUpdated

        ZStack(alignment: .top) {
            // 背景
            if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
            
            // メインコンテンツ
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // 口座情報セクション（スクロールで自然に隠れる）
                            accountInfoSection
                                .id("top")
                            
                            // コンテンツカード（ボトムシート風）
                            VStack(alignment: .leading, spacing: 0) {
                                // ハンドル
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 36, height: 5)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 10)
                                
                                // ヘッダー（入金履歴ラベル）
                                HStack {
                                    Text("passbook.deposit_history")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.top, 16)
                                .padding(.bottom, 12)
                                
                                // 書籍リスト
                                listContent
                                
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: geometry.size.height)
                            .background(Color(.systemBackground))
                            .clipShape(contentCardShape)
                            .overlay(contentCardGlassBorder)
                        }
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newValue in
                        let progress = min(max(newValue / 150, 0), 1)
                        if abs(scrollCollapse.progress - progress) > 0.001 {
                            scrollCollapse.progress = progress
                        }
                    }
                    .overlay(alignment: .top) {
                        PassbookCompactHeaderOverlay(
                            scrollProxy: scrollProxy,
                            totalValue: totalValue,
                            accentColor: accentColor,
                            isOverallAccount: isOverallAccount,
                            themeColor: themeColor
                        )
                    }
                }
            }
        }
        .environment(scrollCollapse)
        .id(passbook?.persistentModelID.hashValue.description ?? "overall")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("passbook.title")
                    .font(.system(size: 17))
            }
        }
    }
    private var accountHeaderPrimaryTextColor: Color {
        isOverallAccount ? .primary : .white
    }

    private var accountHeaderSecondaryTextColor: Color {
        isOverallAccount ? .secondary : .white
    }

    private var accountActionButtonTextColor: Color {
        if isOverallAccount { return .primary }
        return colorScheme == .dark && isBlackTheme ? .black : .white
    }

    private var accountActionButtonGlassTint: Color {
        if isOverallAccount { return PassbookColor.silverThemeColor.opacity(0.35) }
        return colorScheme == .dark && isBlackTheme ? .white : themeColor
    }

    private var listRowHighlightColor: Color {
        if isOverallAccount {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.primary.opacity(0.06)
        }
        return colorScheme == .dark ? Color.white.opacity(0.1) : themeColor.opacity(0.1)
    }

    private var depositEntryBadgeBackground: Color {
        if isOverallAccount {
            return colorScheme == .dark ? Color.white.opacity(0.12) : Color.primary.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : accentColor.opacity(0.12)
    }

    private func listRowGlassBorder(cornerRadius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                listGlassBorderGradient,
                lineWidth: 0.5
            )
    }

    private var contentCardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 40,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 40
        )
    }

    private var listGlassBorderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.28 : 0.55), location: 0),
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), location: 0.5),
                .init(color: Color.primary.opacity(0.1), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contentCardGlassBorder: some View {
        contentCardShape
            .strokeBorder(listGlassBorderGradient, lineWidth: 0.5)
    }

    // MARK: - Account Info Section
    
    private var accountInfoSection: some View {
        VStack(spacing: 0) {
            if isOverallAccount {
                overallAccountSummaryCard
            } else {
                customAccountSummaryHeader
            }

            // アクションボタン
            if isOverallAccount {
                overallAccountActionButtons
                    .padding(.top, 32)

                if !customPassbooks.isEmpty {
                    overallAccountPassbookLinks
                        .padding(.top, 32)
                }
            } else {
                HStack(spacing: 12) {
                    if let registrationPassbook {
                        NavigationLink(destination: BookSearchView(passbook: registrationPassbook, allowPassbookChange: true)) {
                            Text("book.register")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(accountActionButtonTextColor)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .passbookCapsuleGlass(tint: accountActionButtonGlassTint)
                        }
                    }
                    
                    NavigationLink(destination: BookshelfView(passbook: passbook)) {
                        Text("passbook.view_bookshelf")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(accountActionButtonTextColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .passbookCapsuleGlass(tint: accountActionButtonGlassTint)
                    }
                }
                .padding(.top, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 60)
    }

    /// 総合口座：日付・金額・冊数を1つのカードにまとめる
    private var overallAccountSummaryCard: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: 16)

            HStack {
                Text(L10n.string("account.bookbank_overall", locale: languageManager.resolvedLocale))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image("app_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Text(todayString)
                        .font(.footnote)
                        .foregroundColor(Color(white: 0.75))
                }

                HStack(alignment: .lastTextBaseline) {
                    DisplayCurrencyPriceText(
                        amount: totalValue,
                        font: .system(size: 36, weight: .medium),
                        symbolFont: .system(size: 21, weight: .medium)
                    )
                    .foregroundColor(.white)

                    Spacer(minLength: 8)

                    BooksCountText(count: bookCount, font: .subheadline, locale: languageManager.resolvedLocale)
                        .foregroundColor(.white)
                }
                .padding(.top, 56)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Image("bg_passbook")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 3
            )
        )
        .shadow(color: Color.white.opacity(0.14), radius: 24, x: 0, y: 0)
        .shadow(color: Color.white.opacity(0.07), radius: 48, x: 0, y: 6)
        .padding(.horizontal, 16)
    }

    /// 総合口座：丸アイコン + ラベルのアクションボタン
    private var overallAccountActionButtons: some View {
        HStack(alignment: .top, spacing: 8) {
            if let registrationPassbook {
                NavigationLink(destination: BookSearchView(passbook: registrationPassbook, allowPassbookChange: true)) {
                    overallAccountActionButtonLabel(title: "passbook.register_book", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }

            NavigationLink(destination: AccountListView()) {
                overallAccountActionButtonLabel(title: "passbook.view_accounts", icon: "icon-tab-account")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: BookshelfView(passbook: passbook)) {
                overallAccountActionButtonLabel(title: "passbook.view_bookshelf", icon: "icon-tab-bookshelf")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: BookshelfView(passbook: passbook, startsWithCalendarView: true)) {
                overallAccountActionButtonLabel(title: "passbook.view_calendar", icon: "icon-calendar")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// 総合口座：各カスタム口座へのカプセルリンク
    private var overallAccountPassbookLinks: some View {
        FlowLayout(spacing: 8, horizontalAlignment: .center) {
            ForEach(customPassbooks) { passbook in
                Button {
                    appShellState.selectPassbook(passbook)
                } label: {
                    Text(passbook.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .passbookCapsuleGlass(tint: passbookLinkGlassTint(for: passbook))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private func passbookLinkGlassTint(for passbook: Passbook) -> Color {
        PassbookColor.color(for: passbook, in: customPassbooks)
    }

    private func overallAccountActionButtonLabel(
        title: LocalizedStringKey,
        icon: String? = nil,
        systemImage: String? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16))
                } else if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
            }
            .foregroundColor(.primary)
            .frame(width: 56, height: 56)
            .passbookCircleGlass(tint: accountActionButtonGlassTint)

            Text(title)
                .font(.caption2)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
    }

    /// カスタム口座：従来のヘッダー表示
    private var customAccountSummaryHeader: some View {
        VStack(spacing: 0) {
            Text(todayString)
                .font(.footnote)
                .foregroundColor(accountHeaderSecondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.bottom, 32)

            DisplayCurrencyPriceText(
                amount: totalValue,
                font: .system(size: 48, weight: .medium),
                symbolFont: .system(size: 28, weight: .medium)
            )
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .white, location: 0),
                        Gradient.Stop(color: .white, location: 0.6),
                        Gradient.Stop(color: themeColor.opacity(0.1), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Text(L10n.format("passbook.registered_books", locale: languageManager.resolvedLocale, Int64(bookCount)))
                .font(.subheadline)
                .foregroundColor(accountHeaderPrimaryTextColor)
        }
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        LazyVStack(spacing: 6) {
            if userBooks.isEmpty {
                Text("passbook.recent_books_prompt")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(userBooks.enumerated()), id: \.element.id) { index, book in
                    NavigationLink(destination: UserBookDetailView(book: book)) {
                        HStack(alignment: .center, spacing: 12) {
                            // サムネイル
                            if let coverImage = book.coverUIImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 47, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            } else if let imageURL = book.imageURL,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(
                                    url: url,
                                    width: 47,
                                    height: 70
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 47, height: 70)
                                    .overlay {
                                        Image(systemName: "book.closed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(userBooks.count - index)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(accentColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(depositEntryBadgeBackground)
                                        )

                                    Text(formatDate(book.registeredAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Text(book.title)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                if !book.displayAuthor.isEmpty {
                                    Text(book.displayAuthor)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if book.priceAtRegistration != nil {
                                BookPriceText(book: book, font: .headline, fontWeight: .medium)
                                    .foregroundColor(accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(listRowHighlightColor)
                        )
                        .overlay(listRowGlassBorder())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 100)
    }
    
    // MARK: - Actions
    
    /// 日付をYYYY.MM.DD形式でフォーマット
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

// MARK: - Compact Header Overlay

/// スクロール連動コンパクトヘッダー（この View だけが progress を購読する）
private struct PassbookCompactHeaderOverlay: View {
    @Environment(PassbookScrollCollapse.self) private var scrollCollapse

    let scrollProxy: ScrollViewProxy
    let totalValue: Int
    let accentColor: Color
    let isOverallAccount: Bool
    let themeColor: Color

    private var opacity: CGFloat {
        min(max((scrollCollapse.progress - 0.2) / 0.3, 0), 1)
    }

    private var priceStyle: AnyShapeStyle {
        if isOverallAccount {
            return AnyShapeStyle(accentColor)
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: themeColor, location: 0),
                    Gradient.Stop(color: themeColor, location: 0.6),
                    Gradient.Stop(color: themeColor.opacity(0.3), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy.scrollTo("top", anchor: .top)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 32, height: 32)
            }

            Spacer()

            DisplayCurrencyPriceText(
                amount: totalValue,
                font: .system(size: 18, weight: .semibold),
                symbolFont: .system(size: 12, weight: .medium)
            )
            .foregroundStyle(priceStyle)

            Spacer()

            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.05)
    }
}

// MARK: - Preview

#Preview("総合口座") {
    NavigationStack {
        PassbookDetailView(passbook: nil)
    }
    .bookBankPreviewEnvironment()
    .environment(AppShellState())
}

#Preview("カスタム口座") {
    NavigationStack {
        PassbookDetailView(passbook: PreviewSupport.passbook(named: "漫画"))
    }
    .bookBankPreviewEnvironment()
    .environment(AppShellState())
}

