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
    
    // MARK: - Properties
    
    /// 表示対象の口座（nilの場合は総合口座）
    let passbook: Passbook?
    
    // MARK: - SwiftData Query
    
    @Query private var allUserBooks: [UserBook]
    
    // MARK: - State
    
    /// 選択中の年
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // MARK: - Computed Properties
    
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
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if availableYears.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // 年表示（固定）
                        Text(String(selectedYear))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top)
                            .padding(.bottom, 8)
                        
                        // グラフ部分のTabView
                        TabView(selection: $selectedYear) {
                            ForEach(availableYears, id: \.self) { year in
                                YearlyChartContent(year: year, passbook: passbook, targetBooks: targetBooks)
                                    .tag(year)
                            }
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(height: 480)
                        
                        // 読書レポートへの入口
                        readingReportCard
                            .padding(.horizontal)
                            .padding(.top, 24)
                    }
                }
            }
        }
        .navigationTitle(passbook?.name ?? "総合口座")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Subviews
    
    /// 読書レポートカード
    private var readingReportCard: some View {
        NavigationLink(destination: ReadingReportView(passbook: passbook)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("資産ポートフォリオ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("あなたの読書レポートを見る")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    /// 空状態
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("データがありません")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("本を登録すると統計が表示されます")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - YearlyChartContent

/// 年別グラフコンテンツ（グラフ部分のみ）
struct YearlyChartContent: View {
    let year: Int
    let passbook: Passbook?
    let targetBooks: [UserBook]
    
    // MARK: - Computed Properties
    
    /// 指定年の月別データ（常に1-12月を返す）
    private var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        return (1...12).map { month in
            // 未来の月はデータなしとして扱う
            let isFutureMonth = (year == currentYear && month > currentMonth) || year > currentYear
            
            // 日本語のラベル（1月、2月...）
            let label = "\(month)月"
            
            if isFutureMonth {
                // 未来の月は空データ（X軸ラベルのみ表示）
                return ChartDataPoint(month: month, label: label, amount: 0, count: 0)
            }
            
            let booksInMonth = targetBooks.filter { book in
                let bookYear = calendar.component(.year, from: book.registeredAt)
                let bookMonth = calendar.component(.month, from: book.registeredAt)
                return bookYear == year && bookMonth == month
            }
            
            let amount = booksInMonth.compactMap { $0.priceAtRegistration }.reduce(0, +)
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
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // グラフ
                combinedChart
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Subviews
    
    /// 金額と冊数を上下2段で表示
    private var combinedChart: some View {
        VStack(spacing: 36) {
            // 金額グラフ（上段）
            VStack(alignment: .leading, spacing: 12) {
                Text("金額")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Chart {
                    // データがある月までのみグラフを描画
                    ForEach(chartData.filter { hasDataBeforeMonth($0.month) }) { dataPoint in
                        LineMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", dataPoint.amount)
                        )
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", dataPoint.amount)
                        )
                        .foregroundStyle(Color.green)
                        .symbolSize(30)
                    }
                    
                    // X軸の範囲を12ヶ月分に拡張するための透明なマーク
                    ForEach(chartData.filter { !hasDataBeforeMonth($0.month) }) { dataPoint in
                        PointMark(
                            x: .value("Month", dataPoint.label),
                            y: .value("Amount", 0)
                        )
                        .foregroundStyle(Color.clear)
                        .symbolSize(1)
                    }
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(size: 9))
                    }
                }
                .chartXAxis(.hidden)
            }
            
            // 冊数グラフ（下段）
            VStack(alignment: .leading, spacing: 12) {
                Text("冊数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Chart {
                    // X軸に12ヶ月すべて表示するため、全データをループ
                    ForEach(chartData) { dataPoint in
                        // 未来の月はグラフを表示しない（X軸ラベルのみ）
                        if hasDataBeforeMonth(dataPoint.month) {
                            BarMark(
                                x: .value("Month", dataPoint.label),
                                y: .value("Count", dataPoint.count),
                                width: 12
                            )
                            .foregroundStyle(Color.green.opacity(0.7))
                            .cornerRadius(2)
                        } else {
                            // 未来の月は透明な棒を配置（X軸ラベルのため）
                            BarMark(
                                x: .value("Month", dataPoint.label),
                                y: .value("Count", 0),
                                width: 12
                            )
                            .foregroundStyle(Color.clear)
                        }
                    }
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel(verticalSpacing: 20) {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - ReadingReportView

/// 読書レポート画面（プレースホルダー）
struct ReadingReportView: View {
    let passbook: Passbook?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("読書レポート")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("資産ポートフォリオの詳細を表示します")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("読書レポート")
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
