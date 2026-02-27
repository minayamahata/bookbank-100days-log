//
//  OnboardingView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var accountName: String = "小説"
    @State private var showError: Bool = false
    @State private var selectedCategory: String? = "小説"

    // カテゴリタグ
    private let categories = [
        "小説", "ビジネス書", "マンガ", "参考書",
        "雑誌", "旅行記", "エッセイ", "勉強用",
        "レシピ", "写真集", "絵本", "子ども用",
        "プレゼント", "積読"
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景
                backgroundView
                
                // コンテンツ
                ScrollView {
                    VStack(spacing: 0) {
                        // ヘッダー部分
                        headerSection
                            .padding(.top, 100)
                        
                        Spacer(minLength: 50)
                        
                        // 入力セクション
                        inputSection
                        
                        Spacer(minLength: 50)
                        
                        // 開設ボタン
                        openAccountButton
                            .padding(.bottom, 50)
                    }
                    .padding(.horizontal, 28)
                    .frame(minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .preferredColorScheme(.dark)
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("口座の作成に失敗しました")
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Background

    private var backgroundView: some View {
        GeometryReader { geo in
            Image("OnboardingBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // ロゴアイコン
            VStack(spacing: 20) {
                // コロンアイコン
                VStack(spacing: 5) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                }

                // BookBank タイトル
                Text("BookBank")
                    .font(.custom("Fearlessly Authentic", size: 36))
                    .foregroundColor(.white)
            }

            // サブタイトル
            VStack(spacing: 0) {
                Text("本を読む人だけの")
                Text("読書銀行")
            }
            .font(.system(size: 24, weight: .light))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 説明テキストと入力フィールド
            Text("まずは通帳を作りましょう")
                .font(.system(size: 17, weight: .light))
                .foregroundColor(.white)

            // 入力フィールド
            HStack(spacing: 8) {
                TextField("小説", text: $accountName)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(height: 50)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .onSubmit {
                        if !accountName.isEmpty {
                            createAccount()
                        }
                    }

                Text("口座")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            // カテゴリタグ（WrappingHStackの代わりにシンプルなVStack+HStack）
            categoryTagsView
        }
    }
    
    // カテゴリタグをシンプルに配置
    private var categoryTagsView: some View {
        let rows: [[String]] = [
            ["小説", "ビジネス書", "マンガ", "参考書"],
            ["雑誌", "旅行記", "エッセイ", "勉強用"],
            ["レシピ", "写真集", "絵本", "子ども用"],
            ["プレゼント", "積読"]
        ]
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { category in
                        CategoryTag(
                            title: category,
                            isSelected: selectedCategory == category
                        ) {
                            if selectedCategory == category {
                                selectedCategory = nil
                                accountName = ""
                            } else {
                                selectedCategory = category
                                accountName = category
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Open Account Button

    private var openAccountButton: some View {
        Button(action: createAccount) {
            Text("口座を開設")
                .font(.system(size: 16))
                .foregroundColor(accountName.isEmpty ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    accountName.isEmpty
                        ? Color.white.opacity(0.2)
                        : Color.white.opacity(0.4)
                )
                .cornerRadius(8)
        }
        .disabled(accountName.isEmpty)
    }

    // MARK: - Private Methods

    private func createAccount() {
        guard !accountName.isEmpty else { return }

        let newPassbook = Passbook(
            name: accountName,
            type: .custom,
            sortOrder: 1, // 総合口座の次
            isActive: true
        )

        context.insert(newPassbook)

        do {
            try context.save()
            print("✅ First custom passbook created: \(accountName)")
            dismiss()
        } catch {
            print("❌ Error creating first passbook: \(error)")
            showError = true
        }
    }
}

// MARK: - Category Tag

struct CategoryTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .black : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    isSelected
                        ? Color.white
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(26)
        }
    }
}

// MARK: - FlowLayout

/// 横並びで自動折り返しするレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // 次の行へ
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [Passbook.self, UserBook.self])
}
