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
    private var platinumManager: PlatinumManager { PlatinumManager.shared }
    
    @State private var passbookToEdit: Passbook?
    @State private var showAddPassbook = false
    @State private var showProAlert = false
    @State private var showPlatinumPaywall = false
    
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
        customPassbooks.map { passbook in
            AccountChartData(
                name: passbook.name,
                amount: amountForPassbook(passbook),
                color: PassbookColor.color(for: passbook, in: customPassbooks)
            )
        }
    }
    
    // 口座ごとの色を取得
    private func colorForPassbook(_ passbook: Passbook) -> Color {
        PassbookColor.color(for: passbook, in: customPassbooks)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Platinum会員表示（左上）
                if platinumManager.isPlatinum {
                    platinumBadgeSection
                }
                
                // 円グラフ（中央に総資産表示）
                if !chartData.isEmpty && totalAmount > 0 {
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
                                // パーセンテージラベル
                                let percentage = Double(data.amount) / Double(totalAmount) * 100
                                if percentage >= 5 { // 5%以上のみ表示
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(data.color)
                                            .frame(width: 6, height: 6)
                                        Text("\(Int(percentage.rounded()))%")
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.appCardBackground)
                                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    )
                                }
                            }
                        }
                        .chartLegend(.hidden)
                        
                        // 中央の総資産表示
                        VStack(spacing: 2) {
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
                    .frame(height: 220)
                } else {
                    // データがない場合の総資産表示
                    VStack(spacing: 4) {
                        Text("総資産")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(totalAmount.formatted())")
                                .font(.system(size: 32))
                            Text("円")
                                .font(.system(size: 18))
                        }
                        .foregroundColor(.primary)
                        
                        Text("\(totalBookCount)冊")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
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
                
                // 新しい口座を追加ボタン
                Button(action: {
                    if customPassbooks.count >= 3 && !platinumManager.isPlatinum {
                        showProAlert = true
                    } else {
                        showAddPassbook = true
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("新しい口座を追加")
                            .font(.body)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color.appGroupedBackground)
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
        .sheet(isPresented: $showPlatinumPaywall) {
            PlatinumPaywallView()
        }
        .confirmationDialog("Platinum機能", isPresented: $showProAlert, titleVisibility: .visible) {
            Button("Platinum機能を体験する") {
                showPlatinumPaywall = true
            }
        } message: {
            Text("4つ以上の口座を作成するにはPlatinum版が必要です。")
        }
    }
    
    // Platinumカラー（Paywallと統一）
    private static let platinumGradient = LinearGradient(
        colors: [
            Color(red: 180/255, green: 180/255, blue: 190/255),
            Color(red: 220/255, green: 220/255, blue: 230/255),
            Color(red: 200/255, green: 200/255, blue: 210/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Platinum会員バッジ（アイコン1つ + Platinum表記）
    private var platinumBadgeSection: some View {
        HStack(spacing: 8) {
            // 口座アイコン（Platinumカラー）
            ZStack {
                Image("icon-tab-account-fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(red: 200/255, green: 200/255, blue: 210/255).opacity(0.4))
                
                Image("icon-tab-account")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Self.platinumGradient)
            }
            .frame(width: 18, height: 18)
            
            // Platinum表記（枠線なし・Platinumカラー）
            Text("Platinum")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.platinumGradient)
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
            .foregroundColor(.primary)
            
            // 三点リーダー（タップで編集）
            Button(action: {
                passbookToEdit = passbook
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
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
