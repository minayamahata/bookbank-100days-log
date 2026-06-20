//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI
import SwiftData

/// 本棚画面
struct BookshelfView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座（nil = 総合口座）
    let passbook: Passbook?

    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    // MARK: - State
    
    /// お気に入りフィルター
    @State private var showFavoritesOnly: Bool
    
    /// メモありフィルター
    @State private var showWithMemoOnly: Bool
    
    /// カレンダー表示モード
    @State private var showCalendarView: Bool

    /// 月別メモ編集用（総合口座のみ）
    @State private var showMonthlyMemo: Bool
    @State private var memoTargetYear: Int
    @State private var memoTargetMonth: Int
    @State private var memoText: String
    
    /// 口座に紐づく書籍（総合口座の場合は全書籍）
    private var passbookBooks: [UserBook] {
        if let passbook {
            return allUserBooks.filter { book in
                book.passbook?.persistentModelID == passbook.persistentModelID
            }
        }
        return allUserBooks
    }
    
    /// フィルター適用後の書籍
    private var userBooks: [UserBook] {
        var books = passbookBooks
        
        // お気に入りフィルター
        if showFavoritesOnly {
            books = books.filter { $0.isFavorite }
        }
        
        // メモありフィルター
        if showWithMemoOnly {
            books = books.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }
        }
        
        return books
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
    
    /// この口座の全書籍数
    private var allBooksCount: Int {
        passbookBooks.count
    }
    
    /// お気に入りの書籍数
    private var favoriteCount: Int {
        passbookBooks.filter(\.isFavorite).count
    }
    
    /// メモありの書籍数
    private var memoCount: Int {
        passbookBooks.filter { book in
            book.memo != nil && !(book.memo?.isEmpty ?? true)
        }.count
    }
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    // カレンダー用の5カラムグリッド
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
    
    /// 月別にグループ化した書籍データ
    private var booksByMonth: [(year: Int, month: Int, books: [UserBook])] {
        let calendar = Calendar.current
        var grouped: [String: (year: Int, month: Int, books: [UserBook])] = [:]
        
        for book in userBooks {
            let components = calendar.dateComponents([.year, .month], from: book.registeredAt)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if grouped[key] == nil {
                grouped[key] = (year: components.year ?? 0, month: components.month ?? 0, books: [])
            }
            grouped[key]?.books.append(book)
        }
        
        return grouped.values.sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }
    
    /// 年別にグループ化した書籍データ（Stickyヘッダー用）
    private var booksByYear: [(year: Int, months: [(month: Int, books: [UserBook])])] {
        var grouped: [Int: [(month: Int, books: [UserBook])]] = [:]
        
        for monthData in booksByMonth {
            if grouped[monthData.year] == nil {
                grouped[monthData.year] = []
            }
            grouped[monthData.year]?.append((month: monthData.month, books: monthData.books))
        }
        
        return grouped.map { (year: $0.key, months: $0.value) }
            .sorted { $0.year > $1.year }
    }
    
    /// 言語に応じた年月表記（例: 2026年6月 / June 2026）
    private func formattedYearMonth(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else {
            return L10n.format(
                "bookshelf.year_month",
                locale: languageManager.resolvedLocale,
                Int64(year),
                Int64(month)
            )
        }

        let formatter = DateFormatter()
        formatter.locale = languageManager.resolvedLocale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    // MARK: - Initialization
    
    init(passbook: Passbook?, startsWithCalendarView: Bool = false) {
        self.passbook = passbook
        _showFavoritesOnly = State(initialValue: false)
        _showWithMemoOnly = State(initialValue: false)
        _showCalendarView = State(initialValue: startsWithCalendarView)
        _showMonthlyMemo = State(initialValue: false)
        _memoTargetYear = State(initialValue: 0)
        _memoTargetMonth = State(initialValue: 0)
        _memoText = State(initialValue: "")
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        let _ = languageManager.currentLanguage

        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // フィルターセクション
                    filterSection
                    
                    // 本棚グリッドまたはカレンダービュー
                    if showCalendarView {
                        calendarContent
                    } else {
                        gridContent
                    }
                }
            }
        }
        .id(passbook?.persistentModelID.hashValue.description ?? "overall")
        .background {
            if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
        }
        .navigationTitle("bookshelf.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMonthlyMemo) {
            MemoEditorView(memo: Binding(
                get: { memoText },
                set: { _ in }
            )) { newText in
                MonthlyMemoRepository.save(
                    year: memoTargetYear,
                    month: memoTargetMonth,
                    text: newText,
                    context: context
                )
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(
                        label: "common.all",
                        count: allBooksCount,
                        alwaysShowCount: true,
                        isSelected: !showFavoritesOnly && !showWithMemoOnly
                    ) {
                        showFavoritesOnly = false
                        showWithMemoOnly = false
                    }

                    filterPill(
                        label: "bookshelf.favorite",
                        count: favoriteCount,
                        isSelected: showFavoritesOnly
                    ) {
                        showFavoritesOnly.toggle()
                        if showFavoritesOnly {
                            showWithMemoOnly = false
                        }
                    }

                    filterPill(
                        label: "bookshelf.memo",
                        count: memoCount,
                        isSelected: showWithMemoOnly
                    ) {
                        showWithMemoOnly.toggle()
                        if showWithMemoOnly {
                            showFavoritesOnly = false
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            // カレンダービュー切り替えボタン
            Button(action: {
                showCalendarView.toggle()
            }) {
                Image("icon-calendar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(showCalendarView ? .white : .white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(showCalendarView ? Color.white.opacity(0.22) : Color.white.opacity(0.12))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func filterPill(
        label: LocalizedStringKey,
        count: Int,
        alwaysShowCount: Bool = false,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if alwaysShowCount || count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Grid Content
    
    private var gridContent: some View {
        Group {
            if userBooks.isEmpty {
                VStack(spacing: 8) {
                    Text("bookshelf.register_prompt")
                        .font(.body)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(userBooks) { book in
                        NavigationLink(destination: UserBookDetailView(book: book)) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .animation(nil, value: userBooks.count)
            }
        }
        .padding(.bottom, 100)
    }
    
    // MARK: - Calendar Content
    
    private var calendarContent: some View {
        LazyVStack(spacing: 50) {
            ForEach(Array(booksByMonth.enumerated()), id: \.offset) { _, monthData in
                calendarMonthSection(year: monthData.year, month: monthData.month, books: monthData.books)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
    }
    
    private func calendarMonthSection(year: Int, month: Int, books: [UserBook]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 月ヘッダー
            HStack(spacing: 8) {
                Text(formattedYearMonth(year: year, month: month))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if isOverallAccount {
                    Button {
                        openMonthlyMemo(year: year, month: month)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                BooksCountText(count: books.count, font: .system(size: 14), locale: languageManager.resolvedLocale)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            
            // 5カラムグリッドで本を並べる
            LazyVGrid(columns: calendarColumns, spacing: 4) {
                ForEach(books) { book in
                    NavigationLink(destination: UserBookDetailView(book: book)) {
                        calendarBookCover(for: book)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    /// カレンダー表示用の表紙（2:3・列幅いっぱい）
    private func calendarBookCover(for book: UserBook) -> some View {
        GeometryReader { geometry in
            Group {
                if let coverImage = book.coverUIImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if let imageURL = book.imageURL,
                          let url = URL(string: imageURL) {
                    CachedAsyncImage(
                        url: url,
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func openMonthlyMemo(year: Int, month: Int) {
        memoTargetYear = year
        memoTargetMonth = month
        memoText = MonthlyMemoRepository.fetch(year: year, month: month, context: context)?.text ?? ""
        showMonthlyMemo = true
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return NavigationStack {
        BookshelfView(passbook: passbook)
    }
    .modelContainer(container)
}
