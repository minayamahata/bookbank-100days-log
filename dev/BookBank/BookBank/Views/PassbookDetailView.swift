//
//  PassbookDetailView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/14.
//

import SwiftUI
import SwiftData

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
    @Environment(PassbookSheetChromeState.self) private var passbookSheetChromeState
    
    // MARK: - State

    @State private var sheetDetent: PassbookSheetDetent = .collapsed
    @State private var accountSectionHeight: CGFloat = 0
    @State private var contentTopInset: CGFloat = 0
    @State private var safeAreaTopInset: CGFloat = 0
    @State private var locksRowNavigation = false
    @State private var selectedBook: UserBook?

    private let sheetGap: CGFloat = 20
    private let navBarHeight: CGFloat = 44

    /// 画面上端からコンテンツ開始まで（未計測時は safeArea + ナビバー）
    private var effectiveContentTopInset: CGFloat {
        contentTopInset > 0 ? contentTopInset : safeAreaTopInset + navBarHeight
    }

    /// 展開時：シート上端を画面最上部まで伸ばす
    private var sheetExpandedTop: CGFloat {
        -(accountSectionHeight + sheetGap + effectiveContentTopInset)
    }

    /// 展開ヘッダーの上余白（Dynamic Island のすぐ下に置く）
    /// ※ この数値を増やすとヘッダーが下がり、減らすと上がる
    private var expandedHeaderTopInset: CGFloat {
        max(safeAreaTopInset - 0, 4)
    }
    
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

    /// 展開時の＋ボタンのグラス色（右下のリキッドグラスボタンと同じ配色）
    private var expandedAddTint: Color {
        if colorScheme == .dark && isBlackTheme { return .white }
        return accentColor
    }

    /// 展開時の＋ボタンの記号色（右下のリキッドグラスボタンと同じ判定）
    private var expandedAddIconColor: Color {
        if colorScheme == .dark && expandedAddTint.luminance > 0.5 { return .black }
        return .white
    }

    /// 展開時にナビバーへ表示する金額のスタイル（シート側ヘッダーと同じ配色）
    private var headerPriceStyle: AnyShapeStyle {
        if isOverallAccount {
            return AnyShapeStyle(accentColor)
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: themeColor, location: 0),
                    .init(color: themeColor, location: 0.6),
                    .init(color: themeColor.opacity(0.3), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
            Group {
                if isOverallAccount {
                    OverallAccountBackgroundView()
                } else {
                    ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
                }
            }
            .animation(nil, value: sheetDetent)

            VStack(spacing: sheetGap) {
                accountInfoSection
                    .frame(height: accountSectionHeight > 0 ? accountSectionHeight : nil, alignment: .top)
                    .allowsHitTesting(sheetDetent != .expanded)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { _, height in
                        guard height > 0, !locksRowNavigation else { return }
                        guard abs(accountSectionHeight - height) > 0.5 else { return }
                        accountSectionHeight = height
                    }

                PassbookDepositSheet(
                    totalValue: totalValue,
                    accentColor: accentColor,
                    isOverallAccount: isOverallAccount,
                    themeColor: themeColor,
                    collapsedTop: 0,
                    expandedTop: sheetExpandedTop,
                    expandedHeaderInset: expandedHeaderTopInset,
                    detent: $sheetDetent,
                    locksRowNavigation: $locksRowNavigation
                ) {
                    listContent
                }
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
                .zIndex(sheetDetent == .expanded ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { _, minY in
            guard minY > 0, abs(contentTopInset - minY) > 0.5 else { return }
            contentTopInset = minY
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { _, top in
            guard abs(safeAreaTopInset - top) > 0.5 else { return }
            safeAreaTopInset = top
        }
        .onChange(of: sheetDetent) { _, detent in
            // ナビバー項目の入れ替えがスプリングに乗って左上へバウンドするのを防ぐため、
            // 表示判定に使うフラグはアニメーション無効で更新する（シートのスライドは別途継続）。
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                passbookSheetChromeState.isExpanded = detent == .expanded
            }
        }
        .onAppear {
            passbookSheetChromeState.isExpanded = sheetDetent == .expanded
        }
        .onDisappear {
            // 別ページへ遷移したら画面外で折りたたみ、戻ったときに展開状態が残らないようにする
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                sheetDetent = .collapsed
            }
            passbookSheetChromeState.isExpanded = false
        }
        .onChange(of: passbook?.persistentModelID) { _, _ in
            sheetDetent = .collapsed
            accountSectionHeight = 0
            contentTopInset = 0
            safeAreaTopInset = 0
            passbookSheetChromeState.isExpanded = false
            locksRowNavigation = false
            selectedBook = nil
        }
        .id(passbook?.persistentModelID.hashValue.description ?? "overall")
        .navigationDestination(item: $selectedBook) { book in
            UserBookDetailView(book: book)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if passbookSheetChromeState.isExpanded {
                    DisplayCurrencyPriceText(
                        amount: totalValue,
                        font: .system(size: 18, weight: .semibold),
                        symbolFont: .system(size: 12, weight: .medium)
                    )
                    .foregroundStyle(headerPriceStyle)
                } else {
                    Text("passbook.title")
                        .font(.system(size: 17))
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if passbookSheetChromeState.isExpanded {
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                            sheetDetent = .collapsed
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if passbookSheetChromeState.isExpanded, let registrationPassbook {
                    NavigationLink {
                        BookSearchView(passbook: registrationPassbook, allowPassbookChange: true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(expandedAddIconColor)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(expandedAddTint)
                }
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
        .padding(.bottom, 24)
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

                if UnlimitedManager.shared.isUnlimited {
                    Text("paywall.unlimited")
                        .font(.custom("Fearlessly Authentic", size: 16))
                        .foregroundColor(.black)
                }
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
                        .passbookCapsuleGradient(tint: passbookLinkGlassTint(for: passbook))
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
                .font(.footnote)
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

    @ViewBuilder
    private func passbookBookCover(for book: UserBook) -> some View {
        Group {
            if let coverImage = book.coverUIImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let imageURL = book.coverImageURL,
                      let url = URL(string: imageURL) {
                CachedAsyncImage(
                    url: url,
                    width: 47,
                    height: 70
                )
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 47, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .id(book.persistentModelID)
    }

    private func passbookDepositRow(for book: UserBook, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            passbookBookCover(for: book)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
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
            .padding(.trailing, book.priceAtRegistration != nil ? 72 : 0)

            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
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
                    Button {
                        guard !locksRowNavigation else { return }
                        selectedBook = book
                    } label: {
                        passbookDepositRow(for: book, index: index)
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

// MARK: - Preview

#Preview("総合口座") {
    NavigationStack {
        PassbookDetailView(passbook: nil)
    }
    .bookBankPreviewEnvironment()
    .environment(AppShellState())
    .environment(PassbookSheetChromeState())
}

#Preview("カスタム口座") {
    NavigationStack {
        PassbookDetailView(passbook: PreviewSupport.passbook(named: "漫画"))
    }
    .bookBankPreviewEnvironment()
    .environment(AppShellState())
    .environment(PassbookSheetChromeState())
}

