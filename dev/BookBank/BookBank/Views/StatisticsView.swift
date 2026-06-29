//
//  StatisticsView.swift
//  BookBank
//
//  Created on 2026/01/21
//

import SwiftUI
import SwiftData
import Charts

/// グラフデータポイント
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let month: Int
    let label: String
    let amount: Int
    let count: Int
}

/// 集計画面	
/// 年別の読書統計をスワイプで切り替えて表示
struct StatisticsView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var context
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    
    // MARK: - Properties
    
    /// 表示対象の口座（nilの場合は総合口座）
    let passbook: Passbook?
    
    // MARK: - SwiftData Query
    
    @Query private var allUserBooks: [UserBook]
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    // MARK: - State
    
    /// 選択中の年
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // MARK: - Computed Properties
    
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
        if let passbook = passbook {
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
        guard let passbook = passbook else { return false }
        return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
    }
    
    /// 対象口座の書籍（口座指定がない場合は全書籍）
    private var targetBooks: [UserBook] {
        if let passbook = passbook {
            return allUserBooks.filter { $0.passbook?.id == passbook.id }
        }
        return allUserBooks
    }
    
    /// 本が登録されている年のリスト
    private var availableYears: [Int] {
        let calendar = Calendar.current
        var years = Set<Int>()
        
        for book in targetBooks {
            let year = calendar.component(.year, from: book.registeredAt)
            years.insert(year)
        }
        
        // 現在の年も含める（データがなくても表示）
        let currentYear = calendar.component(.year, from: Date())
        years.insert(currentYear)
        
        return years.sorted()
    }

    /// 総冊数（口座全体）
    private var totalBookCount: Int {
        targetBooks.count
    }

    /// 総合計金額（表示通貨）
    private var totalAmount: Int {
        targetBooks.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }

    /// メモの総文字数（口座全体）
    private var totalMemoCharacterCount: Int {
        targetBooks.compactMap { $0.memo }.reduce(0) { $0 + $1.count }
    }
    
    /// メモを書いた本の数（口座全体）
    private var totalMemoCount: Int {
        targetBooks.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }.count
    }
    
    /// お気に入りの総数（口座全体）
    private var totalFavoriteCount: Int {
        targetBooks.filter { $0.isFavorite }.count
    }

    // MARK: - Body
    
    var body: some View {
        let _ = currencyManager.displayCurrency
        let _ = languageManager.currentLanguage
        let locale = languageManager.resolvedLocale

        VStack(spacing: 0) {
            if availableYears.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // 年表示（固定）
                        Text(String(selectedYear))
                            .font(.title)
                            .foregroundColor(isOverallAccount ? .primary : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        // グラフ部分のTabView（年別統計含む）
                        TabView(selection: $selectedYear) {
                            ForEach(availableYears, id: \.self) { year in
                                YearlyChartContent(
                                    year: year,
                                    passbook: passbook,
                                    targetBooks: targetBooks,
                                    themeColor: accentColor,
                                    displayCurrency: currencyManager.displayCurrency,
                                    exchangeRates: exchangeRates,
                                    locale: locale
                                )
                                    .tag(year)
                                    .id("\(year)-\(locale.identifier)")
                            }
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(height: 610)

                        // 口座サマリー
                        VStack(alignment: .leading, spacing: 12) {
                            Text("account.summary")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            HStack {
                                Text("statistics.total_amount")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                DisplayCurrencyPriceText(
                                    amount: totalAmount,
                                    symbolFont: .caption2
                                )
                            }
                            HStack {
                                Text("statistics.total_books")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                BooksCountText(count: totalBookCount, unitFont: .caption2, locale: locale)
                            }
                            HStack {
                                Text("bookshelf.favorite")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                BooksCountText(count: totalFavoriteCount, unitFont: .caption2, locale: locale)
                            }
                            HStack {
                                Text("statistics.memo_count")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                BooksCountText(count: totalMemoCount, unitFont: .caption2, locale: locale)
                            }
                            HStack {
                                Text("statistics.memo_chars")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                CharacterCountText(count: totalMemoCharacterCount, unitFont: .caption2, locale: locale)
                            }
                        }
                        .padding()
                        .glassSectionCard(cornerRadius: 12)
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 80)

                    }
                }
            }
        }
        .navigationTitle("statistics.title")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            if isOverallAccount {
                OverallAccountBackgroundView()
            } else {
                ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme)
            }
        }
    }
    
    // MARK: - Subviews
    
    /// 空状態
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("statistics.empty")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("statistics.empty_message")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - YearlyChartContent

/// 年別グラフコンテンツ（統計サマリー + グラフ）
struct YearlyChartContent: View {
    let year: Int
    let passbook: Passbook?
    let targetBooks: [UserBook]
    let themeColor: Color
    let displayCurrency: AppCurrency
    let exchangeRates: ExchangeRateService
    let locale: Locale
    
    // MARK: - Year-specific Computed Properties
    
    /// 指定年の書籍
    private var booksInYear: [UserBook] {
        let calendar = Calendar.current
        return targetBooks.filter { book in
            calendar.component(.year, from: book.registeredAt) == year
        }
    }
    
    /// 指定年の合計金額（表示通貨）
    private var yearlyAmount: Int {
        booksInYear.totalDisplayAmount(in: displayCurrency, exchangeRates: exchangeRates)
    }
    
    /// 指定年の冊数
    private var yearlyBookCount: Int {
        booksInYear.count
    }
    
    /// 指定年のお気に入り数
    private var yearlyFavoriteCount: Int {
        booksInYear.filter { $0.isFavorite }.count
    }
    
    /// 指定年のメモ数
    private var yearlyMemoCount: Int {
        booksInYear.filter { $0.memo != nil && !($0.memo?.isEmpty ?? true) }.count
    }
    
    /// 金額の最小単位 → メジャー単位の倍率
    private var amountMinorUnitDivisor: Double {
        Double(displayCurrency.minorUnitDivisor)
    }

    /// 最小単位の金額をメジャー単位（グラフ表示用）へ
    private func chartMajorAmount(_ minor: Int) -> Double {
        Double(minor) / amountMinorUnitDivisor
    }

    /// 金額グラフのラベル（メジャー単位・通貨記号なし）
    private func chartAmountLabel(_ major: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = displayCurrency.formattingLocale
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: major)) ?? "\(Int(major.rounded()))"
    }

    /// 金額グラフの最大値（メジャー単位・Y軸ドメイン用）
    private var maxAmount: Double {
        chartData.map { chartMajorAmount($0.amount) }.max() ?? 0
    }

    /// 冊数グラフの最大値（Y軸ドメイン用）
    private var maxCount: Int {
        chartData.map { $0.count }.max() ?? 0
    }

    /// 金額グラフのY軸上限（全0のとき 0...0 にならないよう最低値を確保）
    private var amountChartYUpperBound: Double {
        maxAmount > 0 ? maxAmount : 100
    }

    /// 冊数グラフのY軸上限（全0のとき軸が消えないよう最低値を確保）
    private var countChartYUpperBound: Int {
        maxCount > 0 ? maxCount : 5
    }

    /// 冊数グラフのY軸目盛り（上限値は含めず、最上部のグリッド線を出さない）
    private var countChartYAxisValues: [Int] {
        let upper = countChartYUpperBound
        guard upper > 1 else { return [0] }

        let desiredTickCount = 5
        let step = max(1, Int(ceil(Double(upper) / Double(desiredTickCount))))
        var values: [Int] = []
        var value = 0
        while value < upper {
            values.append(value)
            value += step
        }
        if values.first != 0 {
            values.insert(0, at: 0)
        }
        return values
    }
    
    // MARK: - Chart Computed Properties
    
    /// 指定年の月別データ（常に1-12月を返す）
    private var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        return (1...12).map { month in
            // 未来の月はデータなしとして扱う
            let isFutureMonth = (year == currentYear && month > currentMonth) || year > currentYear
            
            // ローカライズされた月ラベル（1月、Jan、1…）
            let label = monthLabel(month)

            if isFutureMonth {
                // 未来の月は空データ（X軸ラベルのみ表示）
                return ChartDataPoint(month: month, label: label, amount: 0, count: 0)
            }
            
            let booksInMonth = targetBooks.filter { book in
                let bookYear = calendar.component(.year, from: book.registeredAt)
                let bookMonth = calendar.component(.month, from: book.registeredAt)
                return bookYear == year && bookMonth == month
            }
            
            let amount = booksInMonth.totalDisplayAmount(in: displayCurrency, exchangeRates: exchangeRates)
            let count = booksInMonth.count
            
            return ChartDataPoint(month: month, label: label, amount: amount, count: count)
        }
    }
    
    /// 指定月より前にデータがあるかチェック
    private func hasDataBeforeMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        if year < currentYear {
            return true
        } else if year == currentYear {
            return month <= currentMonth
        }
        return false
    }
    
    /// 月ラベルを locale に合わせて生成
    private func monthLabel(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return L10n.format("statistics.month_label", locale: locale, Int64(month))
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    // MARK: - Body
    
    var body: some View {
        let _ = locale

        VStack(spacing: 16) {
            // 年別統計サマリー（2x2グリッド）
            yearlyStatsSection
            
            // グラフ
            combinedChart
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 30)
    }
    
    // MARK: - Subviews
    
    /// 年別統計サマリー（2x2グリッド）
    private var yearlyStatsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            // 合計金額
            statsCard(
                titleKey: "statistics.yearly_amount",
                amount: yearlyAmount
            )
            
            statsCard(
                titleKey: "statistics.book_count",
                count: yearlyBookCount
            )
            
            statsCard(
                titleKey: "bookshelf.favorite",
                count: yearlyFavoriteCount
            )
            
            statsCard(
                titleKey: "bookshelf.memo",
                count: yearlyMemoCount
            )
        }
    }
    
    /// 金額付き統計カード
    private func statsCard(titleKey: LocalizedStringKey, amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titleKey)
                .font(.caption)
                .foregroundColor(.secondary)
            DisplayCurrencyPriceText(
                amount: amount,
                font: .title,
                fontWeight: .medium,
                symbolFont: .caption.weight(.medium)
            )
                .foregroundStyle(
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSectionCard(cornerRadius: 8)
    }

    /// 冊数統計カード
    private func statsCard(titleKey: LocalizedStringKey, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titleKey)
                .font(.caption)
                .foregroundColor(.secondary)
            BooksCountText(count: count, font: .title, fontWeight: .medium, locale: locale)
                .foregroundStyle(
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSectionCard(cornerRadius: 8)
    }
    
    /// 金額と冊数を上下2段で表示
    private var combinedChart: some View {
        VStack(spacing: 36) {
            // 金額グラフ（上段）
            VStack(alignment: .leading, spacing: 12) {
                Text("statistics.amount")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Chart {
                    // エリア（グラデーション塗りつぶし）
                    ForEach(chartData.filter { hasDataBeforeMonth($0.month) }) { dataPoint in
                        AreaMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", chartMajorAmount(dataPoint.amount))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: themeColor.opacity(0.3), location: 0),
                                    Gradient.Stop(color: themeColor.opacity(0.05), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.linear)
                    }
                    
                    // データがある月までのみグラフを描画
                    ForEach(chartData.filter { hasDataBeforeMonth($0.month) }) { dataPoint in
                        LineMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", chartMajorAmount(dataPoint.amount))
                        )
                        .foregroundStyle(themeColor)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        
                        PointMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", chartMajorAmount(dataPoint.amount))
                        )
                        .foregroundStyle(themeColor)
                        .symbolSize(30)
                        .annotation(position: dataPoint.month % 2 == 0 ? .top : .bottom, spacing: 4) {
                            if dataPoint.amount > 0 {
                                Text(chartAmountLabel(chartMajorAmount(dataPoint.amount)))
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // X軸の範囲を12ヶ月分に拡張するための透明なマーク
                    ForEach(chartData.filter { !hasDataBeforeMonth($0.month) }) { dataPoint in
                        PointMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", 0.0)
                        )
                        .foregroundStyle(Color.clear)
                        .symbolSize(1)
                    }
                }
                .frame(height: 120)
                .chartYScale(domain: 0...amountChartYUpperBound)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(chartAmountLabel(doubleValue))
                                    .font(.system(size: 10))
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
            }
            
            // 冊数グラフ（下段）
            VStack(alignment: .leading, spacing: 12) {
                Text("statistics.book_count")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Chart {
                    // X軸に12ヶ月すべて表示するため、全データをループ
                    ForEach(chartData) { dataPoint in
                        // 未来の月はグラフを表示しない（X軸ラベルのみ）
                        if hasDataBeforeMonth(dataPoint.month) {
                            BarMark(
                                x: .value("Month", dataPoint.label),
                                y: .value("Count", dataPoint.count),
                                width: 14
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    stops: [
                                        Gradient.Stop(color: themeColor, location: 0),
                                        Gradient.Stop(color: themeColor.opacity(0.3), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(2)
                            .annotation(position: .top, spacing: 4) {
                                if dataPoint.count > 0 {
                                    Text("\(dataPoint.count)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            // 未来の月は透明な棒を配置（X軸ラベルのため）
                            BarMark(
                                x: .value("Month", dataPoint.label),
                                y: .value("Count", 0),
                                width: 14
                            )
                            .foregroundStyle(Color.clear)
                        }
                    }
                }
                .frame(height: 120)
                .chartYScale(domain: 0...countChartYUpperBound)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: countChartYAxisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(intValue.formatted())
                                    .font(.system(size: 10))
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: chartData.map(\.label)) { value in
                        AxisGridLine()
                        AxisValueLabel(verticalSpacing: 20) {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .glassSectionCard(cornerRadius: 12)
    }
}

// MARK: - ReadingReportView

/// 読書レポート画面（プレースホルダー）
struct ReadingReportView: View {
    let passbook: Passbook?
    
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    private var themeColor: Color {
        if let passbook = passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return PassbookColor.overallAccentColor
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(themeColor)
            
            Text("statistics.report.title")
                .font(.title2)
            
            Text("statistics.report.subtitle")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("statistics.report.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: Passbook.self, UserBook.self, Subscription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let context = container.mainContext
        
        // テスト用の口座を作成
        let testPassbook = Passbook(name: "テスト口座", type: .custom, sortOrder: 1)
        context.insert(testPassbook)
        
        // 各月にテストデータを作成（2026年1月〜12月）
        let calendar = Calendar.current
        let year = 2026
        
        for month in 1...12 {
            // 各月に1〜3冊のランダムな本を登録
            let booksInMonth = Int.random(in: 1...3)
            
            for _ in 0..<booksInMonth {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = Int.random(in: 1...28)
                
                if let date = calendar.date(from: components) {
                    let book = UserBook(
                        title: "テスト書籍 \(month)月",
                        author: "著者名",
                        isbn: "",
                        price: Int.random(in: 1000...5000),
                        passbook: testPassbook
                    )
                    // 登録日を手動で設定
                    book.registeredAt = date
                    context.insert(book)
                }
            }
        }
        
        return NavigationStack {
            StatisticsView(passbook: nil)
        }
        .modelContainer(container)
    }
}
