//
//  BookshelfCalendarView.swift
//  BookBank
//
//  本棚のカレンダービュー（日付セルを曜日位置に並べた月間カレンダー）
//

import SwiftUI

/// 本棚のカレンダービュー
/// 登録日ごとに表紙を月間カレンダー上へ配置する
struct BookshelfCalendarView<Header: View>: View {

    /// 表示対象の書籍（フィルタ適用後）
    let books: [UserBook]

    /// 総合口座かどうか（月メモボタンの表示判定）
    let isOverallAccount: Bool

    /// 月メモを開くコールバック（year, month）
    let onMonthlyMemo: (Int, Int) -> Void

    /// スクロールに追従して流れる先頭要素（フィルター行など）
    @ViewBuilder var header: () -> Header

    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.colorScheme) private var colorScheme

    /// カレンダー用の7カラムグリッド（曜日）
    private let weekColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private let calendar = Calendar.current

    // MARK: - データ整形

    /// 1か月分のカレンダーデータ
    private struct MonthGroup: Identifiable {
        let year: Int
        let month: Int
        let books: [UserBook]
        var id: String { "\(year)-\(month)" }
    }

    /// 1年分のカレンダーデータ
    private struct YearGroup: Identifiable {
        let year: Int
        let months: [MonthGroup]
        var id: Int { year }
    }

    /// 年別にグループ化した書籍データ
    /// 今年は今月まで、過去年は全12か月を表示（登録のない月も含む）
    /// 新しい年が先・各年内は新しい月が先
    private var booksByYear: [YearGroup] {
        // "year-month" -> 書籍配列
        var booksMap: [String: [UserBook]] = [:]
        var earliest: (year: Int, month: Int)?
        var latest: (year: Int, month: Int)?

        for book in books {
            let components = calendar.dateComponents([.year, .month], from: book.registeredAt)
            guard let year = components.year, let month = components.month else { continue }
            booksMap["\(year)-\(month)", default: []].append(book)

            if earliest == nil || (year, month) < (earliest!.year, earliest!.month) {
                earliest = (year, month)
            }
            if latest == nil || (year, month) > (latest!.year, latest!.month) {
                latest = (year, month)
            }
        }

        guard let earliest, let latest else { return [] }

        // 今日時点の年月（今年は今月までしか表示しない）
        let today = calendar.dateComponents([.year, .month], from: Date())
        let currentYear = today.year ?? latest.year
        let currentMonth = today.month ?? 12

        // 表示する最新年は「今年」または最後の登録年の新しい方
        let topYear = max(currentYear, latest.year)

        var result: [YearGroup] = []

        // 最新年〜最古年まで。今年は今月→1月、過去年は12月→1月を表示する
        var year = topYear
        while year >= earliest.year {
            let startMonth = (year == currentYear) ? currentMonth : 12
            var months: [MonthGroup] = []
            var month = startMonth
            while month >= 1 {
                months.append(MonthGroup(year: year, month: month, books: booksMap["\(year)-\(month)"] ?? []))
                month -= 1
            }
            result.append(YearGroup(year: year, months: months))
            year -= 1
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header()

                ForEach(booksByYear) { yearData in
                    Section {
                        ForEach(yearData.months) { monthData in
                            monthSection(year: monthData.year, month: monthData.month, books: monthData.books)
                                .padding(.top, monthData.id == yearData.months.first?.id ? 12 : 32)
                        }
                        .padding(.bottom, 32)
                    } header: {
                        yearHeader(year: yearData.year)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 100)
        }
    }

    // MARK: - 年見出し（スクロール時に上部固定）

    private func yearHeader(year: Int) -> some View {
        Text(verbatim: String(year))
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // MARK: - 月セクション

    private func monthSection(year: Int, month: Int, books: [UserBook]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 月ヘッダー
            HStack(spacing: 8) {
                Text(formattedMonth(month: month))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if !books.isEmpty {
                    HStack(spacing: 0) {
                        DisplayCurrencyPriceText(
                            amount: books.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates),
                            font: .system(size: 16)
                        )

                        Text(" （")
                            .font(.system(size: 16))
                        BooksCountText(count: books.count, font: .system(size: 16), locale: languageManager.resolvedLocale)
                        Text(" ）")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.primary)
                }

                Spacer()

                if isOverallAccount {
                    Button {
                        onMonthlyMemo(year, month)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            weekdayHeader

            calendarGrid(year: year, month: month, books: books)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 曜日見出し

    /// firstWeekday に合わせて並べた曜日記号（言語に追従）
    private var weekdaySymbols: [String] {
        var localeCalendar = Calendar(identifier: .gregorian)
        localeCalendar.locale = languageManager.resolvedLocale
        let symbols = localeCalendar.shortWeekdaySymbols // 0 = 日曜
        let first = calendar.firstWeekday - 1 // 0 始まりに変換
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: weekColumns, spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - カレンダーグリッド

    private func calendarGrid(year: Int, month: Int, books: [UserBook]) -> some View {
        let booksByDay = groupByDay(books)
        let leadingBlanks = leadingBlankCount(year: year, month: month)
        let dayCount = daysInMonth(year: year, month: month)

        return LazyVGrid(columns: weekColumns, spacing: 4) {
            // 月初の曜日に合わせた空白セル
            ForEach(0..<leadingBlanks, id: \.self) { index in
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .id("blank-\(index)")
            }

            // 1〜月末の各日
            ForEach(1...max(dayCount, 1), id: \.self) { day in
                dayCell(day: day, books: booksByDay[day] ?? [])
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int, books: [UserBook]) -> some View {
        if let latest = books.first {
            NavigationLink(destination: UserBookDetailView(book: latest)) {
                filledDayCell(day: day, latest: latest, extraCount: books.count - 1)
            }
            .buttonStyle(.plain)
        } else {
            emptyDayCell(day: day)
        }
    }

    /// 本が登録された日のセル（表紙＋日付＋緑チェック＋複数時バッジ）
    private func filledDayCell(day: Int, latest: UserBook, extraCount: Int) -> some View {
        cover(for: latest)
            .overlay {
                Color.black.opacity(0.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                Text("\(day)")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
            }
            .overlay(alignment: .topTrailing) {
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.black.opacity(0.55))
                        )
                        .padding(3)
                }
            }
    }

    /// 本がない日のセル（薄い日付数字のみ）
    private func emptyDayCell(day: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                Text("\(day)")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
    }

    /// 表紙（2:3・列幅いっぱい）
    private func cover(for book: UserBook) -> some View {
        GeometryReader { geometry in
            Group {
                if let coverImage = book.coverUIImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if let imageURL = book.coverImageURL,
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
        .aspectRatio(2 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: - ヘルパー

    /// その月の本を「日 -> 書籍配列（新しい順）」にまとめる
    private func groupByDay(_ books: [UserBook]) -> [Int: [UserBook]] {
        var result: [Int: [UserBook]] = [:]
        for book in books {
            let day = calendar.component(.day, from: book.registeredAt)
            result[day, default: []].append(book)
        }
        for key in result.keys {
            result[key]?.sort { $0.registeredAt > $1.registeredAt }
        }
        return result
    }

    /// 月初の曜日に合わせた先頭空白セル数
    private func leadingBlankCount(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstDay = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay) // 1 = 日曜
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// その月の日数
    private func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }

    /// 言語に応じた月表記（例: 6月 / June）
    private func formattedMonth(month: Int) -> String {
        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = 1

        let gregorian = Calendar(identifier: .gregorian)
        guard let date = gregorian.date(from: components) else {
            return String(month)
        }

        let formatter = DateFormatter()
        formatter.locale = languageManager.resolvedLocale
        formatter.calendar = gregorian
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let now = Date()

    func sampleBook(_ title: String, monthsAgo: Int, price: Int) -> UserBook {
        let book = UserBook(title: title, price: price, currencyCode: AppCurrency.jpy.code)
        book.registeredAt = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
        return book
    }

    let books = [
        sampleBook("本A", monthsAgo: 0, price: 1200),
        sampleBook("本B", monthsAgo: 0, price: 800),
        sampleBook("本C", monthsAgo: 2, price: 1500),
        sampleBook("本D", monthsAgo: 8, price: 2000)
    ]

    return NavigationStack {
        BookshelfCalendarView(
            books: books,
            isOverallAccount: true,
            onMonthlyMemo: { _, _ in }
        ) {
            EmptyView()
        }
    }
    .bookBankPreviewEnvironment()
    .environment(BookshelfChromeState())
}
