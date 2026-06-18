//
//  AccountListView.swift
//  BookBank
//
//  Created on 2026/01/24
//

import SwiftUI
import SwiftData
import Charts

/// 口座一覧ページ
struct AccountListView: View {
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    @Query private var allBooks: [UserBook]
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    @State private var passbookToEdit: Passbook?
    @State private var showAddPassbook = false
    @State private var showUnlimitedPaywall = false
    
    /// 口座選択時のコールバック
    var onPassbookSelected: ((Passbook) -> Void)?
    
    /// 総合口座選択時のコールバック
    var onOverallSelected: (() -> Void)?
    
    private static let overallColor = PassbookColor.overallThemeColor
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    // 全口座の合計金額（表示通貨）
    private var totalAmount: Int {
        allBooks.totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    // 全口座の合計冊数
    private var totalBookCount: Int {
        allBooks.count
    }
    
    // 特定の口座の合計金額（表示通貨）
    private func amountForPassbook(_ passbook: Passbook) -> Int {
        allBooks
            .filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
            .totalDisplayAmount(in: currencyManager.displayCurrency, exchangeRates: exchangeRates)
    }
    
    // 特定の口座の冊数
    private func bookCountForPassbook(_ passbook: Passbook) -> Int {
        allBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }.count
    }
    
    // 円グラフ用のデータ
    private var chartData: [AccountChartData] {
        if totalAmount > 0 {
            return customPassbooks.map { passbook in
                AccountChartData(
                    name: passbook.name,
                    amount: amountForPassbook(passbook),
                    color: PassbookColor.color(for: passbook, in: customPassbooks)
                )
            }
        } else if !customPassbooks.isEmpty {
            return customPassbooks.map { passbook in
                AccountChartData(
                    name: passbook.name,
                    amount: 1,
                    color: Color.gray.opacity(0.1)
                )
            }
        } else {
            return [AccountChartData(
                name: "empty",
                amount: 1,
                color: Color.gray.opacity(0.08)
            )]
        }
    }
    
    // 口座ごとの色を取得
    private func colorForPassbook(_ passbook: Passbook) -> Color {
        PassbookColor.color(for: passbook, in: customPassbooks)
    }
    
    var body: some View {
        let _ = languageManager.currentLanguage
        let _ = currencyManager.displayCurrency

        ScrollView {
            VStack(spacing: 20) {
                // 円グラフ + 総合口座
                VStack(spacing: 0) {
                    ZStack {
                        Chart(chartData) { data in
                            SectorMark(
                                angle: .value(L10n.string("chart.amount", locale: languageManager.resolvedLocale), data.amount),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(data.color)
                            .cornerRadius(2)
                            .annotation(position: .overlay) {
                                if totalAmount > 0 {
                                    let percentage: Double = {
                                        let value = Double(data.amount) / Double(totalAmount) * 100
                                        return value.isNaN || value.isInfinite ? 0 : value
                                    }()
                                    if percentage >= 5 {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(data.color)
                                                .frame(width: 6, height: 6)
                                            Text(L10n.format("common.percent", Int64(Int(percentage.rounded()))))
                                                .font(.caption2)
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.appCardBackground)
                                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                        )
                                    }
                                }
                            }
                        }
                        .chartLegend(.hidden)
                        
                        VStack(spacing: 4) {
                            if unlimitedManager.isUnlimited {
                                unlimitedBadgeSection
                            }
                            
                            Text("account.total_assets")
                                .font(.callout)
                                .fontWeight(.regular)
                                .foregroundColor(.primary)
                            
                            DisplayCurrencyPriceText(amount: totalAmount, font: .system(size: 26), fontWeight: .medium)
                            .foregroundColor(.primary)
                            
                            Text(L10n.format("common.books_count", Int64(totalBookCount)))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 260)
                    
                    Button(action: {
                        onOverallSelected?()
                    }) {
                        accountRow(
                            name: L10n.string("account.bookbank_overall", locale: languageManager.resolvedLocale),
                            bookCount: totalBookCount,
                            amount: totalAmount,
                            color: Self.overallColor,
                            showEditButton: false,
                            showRowBackground: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 30)
                .padding(.bottom, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appSectionBackground)
                )
                
                // カスタム口座リスト
                VStack(spacing: 6) {
                    ForEach(customPassbooks) { passbook in
                        Button(action: {
                            onPassbookSelected?(passbook)
                        }) {
                            accountRow(
                                passbook: passbook,
                                showEditButton: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // 新しい口座を追加ボタン
                Button(action: {
                    if customPassbooks.count >= 3 && !unlimitedManager.isUnlimited {
                        showUnlimitedPaywall = true
                    } else {
                        showAddPassbook = true
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                        Text("account.add_new")
                            .font(.body)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Color.appGroupedBackground
                    
                    Image("bg_glow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 2.2)
                        .blendMode(.screen)
                        .opacity(1)
                    
                    Image("bg_noise")
                        .resizable(resizingMode: .tile)
                        .blendMode(.overlay)
                        .opacity(0.2)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
        )
        .navigationTitle(L10n.string("account.list.title", locale: languageManager.resolvedLocale))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $passbookToEdit) { passbook in
            EditPassbookView(passbook: passbook)
        }
        .sheet(isPresented: $showAddPassbook) {
            AddPassbookView()
        }
        .sheet(isPresented: $showUnlimitedPaywall) {
            UnlimitedPaywallView()
        }
    }
    
    private static let unlimitedGradient = LinearGradient(
        colors: [
            Color(red: 180/255, green: 180/255, blue: 190/255),
            Color(red: 220/255, green: 220/255, blue: 230/255),
            Color(red: 200/255, green: 200/255, blue: 210/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private static let goldColor = Color(red: 161/255, green: 151/255, blue: 93/255)
    
    private var unlimitedBadgeSection: some View {
        Text("paywall.unlimited")
            .font(.custom("Fearlessly Authentic", size: 16))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // 口座行のビュー（カスタム口座用）
    private func accountRow(passbook: Passbook, showEditButton: Bool) -> some View {
        accountRow(
            name: passbook.name,
            bookCount: bookCountForPassbook(passbook),
            amount: amountForPassbook(passbook),
            color: colorForPassbook(passbook),
            showEditButton: showEditButton,
            onEdit: { passbookToEdit = passbook }
        )
    }
    
    // 口座行のビュー
    private func accountRow(
        name: String,
        bookCount: Int,
        amount: Int,
        color: Color,
        showEditButton: Bool,
        showRowBackground: Bool = true,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            // 口座アイコン（fillとstrokeを重ねる）
            ZStack {
                Image("icon-tab-account-fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color.opacity(0.1))
                
                Image("icon-tab-account")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color)
            }
            .frame(width: 20, height: 20)
            
            // 口座情報
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(L10n.format("common.books_count", Int64(bookCount)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 金額
            DisplayCurrencyPriceText(amount: amount)
                .foregroundColor(color)
            
            if showEditButton {
                // 三点リーダー（タップで編集）
                Button(action: {
                    onEdit?()
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, showEditButton ? 8 : 16)
        .padding(.vertical, 14)
        .background {
            if showRowBackground {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCardBackground)
            }
        }
    }
}

// 円グラフ用のデータ構造
struct AccountChartData: Identifiable {
    let id = UUID()
    let name: String
    let amount: Int
    let color: Color
}

#Preview {
    NavigationStack {
        AccountListView()
    }
    .environment(ThemeManager())
    .modelContainer(for: [Passbook.self, UserBook.self])
}
