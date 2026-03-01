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
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    @Query private var allBooks: [UserBook]
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    @State private var passbookToEdit: Passbook?
    @State private var showAddPassbook = false
    @State private var showProAlert = false
    @State private var showUnlimitedPaywall = false
    
    /// 口座選択時のコールバック
    var onPassbookSelected: ((Passbook) -> Void)?
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    // 全口座の合計金額
    private var totalAmount: Int {
        allBooks.compactMap { $0.priceAtRegistration }.reduce(0, +)
    }
    
    // 全口座の合計冊数
    private var totalBookCount: Int {
        allBooks.count
    }
    
    // 特定の口座の合計金額
    private func amountForPassbook(_ passbook: Passbook) -> Int {
        allBooks
            .filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
            .compactMap { $0.priceAtRegistration }
            .reduce(0, +)
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
        ScrollView {
            VStack(spacing: 20) {
                if unlimitedManager.isUnlimited {
                    unlimitedBadgeSection
                        .padding(.bottom, -12)
                }
                
                // 円グラフ（中央に総資産表示）
                ZStack {
                    Chart(chartData) { data in
                        SectorMark(
                            angle: .value("金額", data.amount),
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
                                        Text("\(Int(percentage.rounded()))%")
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
                    
                    // 中央の総資産表示
                    VStack(spacing: 8) {
                        Text("総資産")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 1) {
                            Text("\(totalAmount.formatted())")
                                .font(.system(size: 22))
                            Text("円")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.primary)
                        
                        Text("\(totalBookCount)冊")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 260)
                
                // 口座リスト
                VStack(spacing: 10) {
                    ForEach(customPassbooks) { passbook in
                        Button {
                            onPassbookSelected?(passbook)
                        } label: {
                            accountRow(passbook: passbook)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
                
                // 新しい口座を追加ボタン
                Button(action: {
                    if customPassbooks.count >= 3 && !unlimitedManager.isUnlimited {
                        showProAlert = true
                    } else {
                        showAddPassbook = true
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                        Text("新しい口座を追加")
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
        .navigationTitle("口座一覧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ThemeToggleButton()
            }
        }
        .sheet(item: $passbookToEdit) { passbook in
            EditPassbookView(passbook: passbook)
        }
        .sheet(isPresented: $showAddPassbook) {
            AddPassbookView()
        }
        .sheet(isPresented: $showUnlimitedPaywall) {
            UnlimitedPaywallView()
        }
        .overlay {
            if showProAlert {
                UnlimitedAlertView(
                    message: "4つ以上の口座を作成するにはUnlimited版が必要です。",
                    onConfirm: {
                        showProAlert = false
                        showUnlimitedPaywall = true
                    },
                    onCancel: {
                        showProAlert = false
                    }
                )
            }
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
    
    private var unlimitedBadgeSection: some View {
        HStack(spacing: 8) {
            ZStack {
                Image("icon-tab-account-fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary.opacity(0.4))
                
                Image("icon-tab-account")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
            .frame(width: 18, height: 18)
            
            Text("Unlimited")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // 口座行のビュー
    private func accountRow(passbook: Passbook) -> some View {
        HStack(spacing: 12) {
            // 口座アイコン（fillとstrokeを重ねる）
            ZStack {
                Image("icon-tab-account-fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(colorForPassbook(passbook).opacity(0.1))
                
                Image("icon-tab-account")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(colorForPassbook(passbook))
            }
            .frame(width: 20, height: 20)
            
            // 口座情報
            VStack(alignment: .leading, spacing: 4) {
                Text(passbook.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text("\(bookCountForPassbook(passbook))冊")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 金額
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(amountForPassbook(passbook).formatted())")
                    .font(.body)
                Text("円")
                    .font(.caption)
            }
            .foregroundColor(colorForPassbook(passbook))
            
            // 三点リーダー（タップで編集）
            Button(action: {
                passbookToEdit = passbook
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCardBackground)
        )
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
