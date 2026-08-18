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
    let books: [BookDTO]

    /// 月メモを開くコールバック（year, month）
    /// - Note: 月別メモは口座横断（年月ごとに1つ）のため、どの口座のカレンダーからでも
    ///   同じメモを編集できる。表示判定に口座種別は用いない。
    let onMonthlyMemo: (Int, Int) -> Void

    /// 同一日の複数冊一覧シートで本が選ばれ、シートのdismissが完了したあとに呼ばれる。
    /// 詳細を物理画面最上端まで展開できるよう、シート内へpushせず親のNavigationStackで開いてもらう
    /// （`docs/bug-review-2026-07-06.md` D-4の後日変更・2026-08-13）
    let onSelectDayBook: (BookDTO) -> Void

    /// 月ヘッダーの共有ボタン。その月を対象にマンスリーログ共有画面を開く
    var onShareMonth: (Int, Int) -> Void = { _, _ in }

    /// 同日複数冊シートの表示状態。スクリーンショット検知の二重表示防止に使う
    var onDaySheetPresentedChange: (Bool) -> Void = { _ in }

    /// カレンダーViewが実際に前面か。push先では onDisappear で false になる
    var onForegroundChange: (Bool) -> Void = { _ in }

    /// スクロールに追従して流れる先頭要素（フィルター行など）
    @ViewBuilder var header: () -> Header

    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.colorScheme) private var colorScheme

    /// 同一日に複数冊ある日をタップしたときに提示する一覧シートの対象
    @State private var selectedDay: DaySelection?

    /// 一覧シートで選ばれた本の一時保持。シートのdismiss完了後に `onSelectDayBook` で親へ通知する
    /// （dismissとpushの競合を避けるため、dismiss完了前にnavigationを開始しない）
    @State private var pendingDayBook: BookDTO?

    /// カレンダー用の7カラムグリッド（曜日）
    private let weekColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private let calendar = Calendar.current

    // MARK: - データ整形

    /// 1か月分のカレンダーデータ
    private struct MonthGroup: Identifiable {
        let year: Int
        let month: Int
        let occurrences: [BookReadingOccurrence]
        var id: String { "\(year)-\(month)" }
    }

    /// 1年分のカレンダーデータ
    private struct YearGroup: Identifiable {
        let year: Int
        let months: [MonthGroup]
        var id: Int { year }
    }

    /// 同一日に複数冊ある日の一覧シート用データ
    private struct DaySelection: Identifiable {
        let year: Int
        let month: Int
        let day: Int
        /// その日の読書（表示順）
        let occurrences: [BookReadingOccurrence]
        var id: String { "\(year)-\(month)-\(day)" }
    }

    /// 年別にグループ化した書籍データ
    /// 今年は今月まで、過去年は全12か月を表示（登録のない月も含む）
    /// 新しい年が先・各年内は新しい月が先
    private var booksByYear: [YearGroup] {
        // "year-month" -> その月の読書
        var occurrenceMap: [String: [BookReadingOccurrence]] = [:]
        var earliest: (year: Int, month: Int)?
        var latest: (year: Int, month: Int)?

        for occurrence in ReadingTally.occurrences(from: books) {
            let components = calendar.dateComponents([.year, .month], from: occurrence.date)
            guard let year = components.year, let month = components.month else { continue }
            occurrenceMap["\(year)-\(month)", default: []].append(occurrence)

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
                months.append(MonthGroup(year: year, month: month, occurrences: occurrenceMap["\(year)-\(month)"] ?? []))
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
                            monthSection(year: monthData.year, month: monthData.month, occurrences: monthData.occurrences)
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
        .sheet(item: $selectedDay, onDismiss: {
            onDaySheetPresentedChange(false)
            // 本を選ばずスワイプで閉じた場合は pendingDayBook が nil のまま＝何も開かない
            guard let book = pendingDayBook else { return }
            pendingDayBook = nil
            onSelectDayBook(book)
        }) { selection in
            dayBooksSheet(selection)
        }
        .onChange(of: selectedDay != nil) { _, presented in
            onDaySheetPresentedChange(presented)
        }
        .onAppear { onForegroundChange(true) }
        .onDisappear { onForegroundChange(false) }
    }

    // MARK: - 年見出し（スクロール時に上部固定）

    private func yearHeader(year: Int) -> some View {
        Text(verbatim: String(year))
            .font(.app(size: 34, weight: .bold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // MARK: - 月セクション

    private func monthSection(year: Int, month: Int, occurrences: [BookReadingOccurrence]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 月ヘッダー
            HStack(spacing: 8) {
                Text(formattedMonth(month: month))
                    .font(.app(.title3, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if !occurrences.isEmpty {
                    HStack(spacing: 0) {
                        DisplayCurrencyPriceText(
                            amount: ReadingTally.totalDisplayAmount(
                                of: occurrences,
                                in: currencyManager.displayCurrency,
                                exchangeRates: exchangeRates
                            ),
                            font: .app(size: 16)
                        )

                        Text(" （")
                            .font(.app(size: 16))
                        BooksCountText(count: occurrences.count, font: .app(size: 16), locale: languageManager.resolvedLocale)
                        Text(" ）")
                            .font(.app(size: 16))
                    }
                    .foregroundColor(.primary)
                }

                Spacer()

                Button {
                    onShareMonth(year, month)
                } label: {
                    Image("icon-share")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("monthly_log_share.share_month"))

                // 月別メモは口座横断（年月ごとに1つ）のため、全口座のカレンダーで表示する
                Button {
                    onMonthlyMemo(year, month)
                } label: {
                    Image("icn_log-edit")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
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

            weekdayHeader

            calendarGrid(year: year, month: month, occurrences: occurrences)
        }
        .padding(.horizontal, 16)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MonthlyLogShareMonthFrameKey.self,
                    value: [
                        MonthlyLogShareVisibleMonth.Candidate(
                            year: year,
                            month: month,
                            frame: geometry.frame(in: .global)
                        )
                    ]
                )
            }
        }
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
                    .font(.app(size: 11))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - カレンダーグリッド

    private func calendarGrid(year: Int, month: Int, occurrences: [BookReadingOccurrence]) -> some View {
        let layout = MonthlyCalendarLayout.make(year: year, month: month, occurrences: occurrences, calendar: calendar)

        return LazyVGrid(columns: weekColumns, spacing: 4) {
            // 月初の曜日に合わせた空白セル
            ForEach(0..<layout.leadingBlankCount, id: \.self) { index in
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .id("blank-\(index)")
            }

            // 1〜月末の各日
            ForEach(layout.days) { day in
                dayCell(year: year, month: month, day: day.day, occurrences: day.occurrences)
            }
        }
    }

    @ViewBuilder
    private func dayCell(year: Int, month: Int, day: Int, occurrences: [BookReadingOccurrence]) -> some View {
        if let latest = occurrences.first?.book {
            if occurrences.count > 1 {
                // 複数回：タップで一覧シートを提示し、各本の詳細へ遷移できるようにする
                Button {
                    selectedDay = DaySelection(year: year, month: month, day: day, occurrences: occurrences)
                } label: {
                    filledDayCell(day: day, latest: latest, extraCount: occurrences.count - 1)
                }
                .buttonStyle(.plain)
            } else {
                // 1冊のみ：現状どおり詳細へ直接遷移
                NavigationLink(destination: UserBookDetailView(book: latest)) {
                    filledDayCell(day: day, latest: latest, extraCount: 0)
                }
                .buttonStyle(.plain)
            }
        } else {
            emptyDayCell(day: day)
        }
    }

    // MARK: - 同一日の複数冊リストシート

    @ViewBuilder
    private func dayBooksSheet(_ selection: DaySelection) -> some View {
        NavigationStack {
            List {
                ForEach(selection.occurrences) { occurrence in
                    // 詳細はこのシート内へpushしない。選択本を一時保持して先にシートを閉じ、
                    // dismiss完了後（`.sheet` の onDismiss）に親のNavigationStackで開く
                    Button {
                        pendingDayBook = occurrence.book
                        selectedDay = nil
                    } label: {
                        dayBookRow(occurrence.book)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.appCardBackground)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appCardBackground)
            .navigationTitle(dayTitle(selection))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    /// リスト1行（表紙｜書名・著者｜右端に金額）
    private func dayBookRow(_ book: BookDTO) -> some View {
        HStack(alignment: .center, spacing: 12) {
            rowCover(for: book)
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.app(.callout))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !book.displayAuthor.isEmpty {
                    Text(book.displayAuthor)
                        .font(.app(.caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if book.priceAtRegistration != nil {
                BookPriceText(book: book, font: .app(.headline, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// リスト行用の固定サイズ表紙（2:3）
    private func rowCover(for book: BookDTO) -> some View {
        LocalCoverImage(book: book) { coverImage in
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let imageURL = book.coverImageURL,
                      let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: 50, height: 75)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
            }
        }
    }

    /// シートのタイトル（登録日・yyyy.MM.dd）
    private func dayTitle(_ selection: DaySelection) -> String {
        var components = DateComponents()
        components.year = selection.year
        components.month = selection.month
        components.day = selection.day
        guard let date = calendar.date(from: components) else {
            return "\(selection.year).\(selection.month).\(selection.day)"
        }
        let formatter = DateFormatter()
        formatter.locale = languageManager.resolvedLocale
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    /// 本が登録された日のセル（表紙＋日付＋緑チェック＋複数時バッジ）
    private func filledDayCell(day: Int, latest: BookDTO, extraCount: Int) -> some View {
        cover(for: latest)
            .overlay {
                Color.black.opacity(0.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                Text("\(day)")
                    .font(.app(size: 17))
                    .foregroundColor(.white)
            }
            .overlay(alignment: .topTrailing) {
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.app(size: 9, weight: .bold))
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
                    .font(.app(size: 17))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
    }

    /// 表紙（2:3・列幅いっぱい）
    private func cover(for book: BookDTO) -> some View {
        GeometryReader { geometry in
            LocalCoverImage(book: book) { coverImage in
                if let coverImage {
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

    func sampleBook(_ title: String, monthsAgo: Int, price: Int) -> BookDTO {
        BookDTO(
            id: UUID().uuidString,
            title: title,
            author: nil,
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: price,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: price,
            currencyCode: AppCurrency.jpy.code,
            registeredAt: calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now,
            createdAt: now,
            updatedAt: now,
            passbookId: nil,
            hasCoverImage: false
        )
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
            onMonthlyMemo: { _, _ in },
            onSelectDayBook: { _ in }
        ) {
            EmptyView()
        }
    }
    .bookBankPreviewEnvironment()
    .environment(BookshelfChromeState())
    .environment(AppShellState())
}
