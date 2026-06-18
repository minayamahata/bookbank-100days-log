//
//  OnboardingView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    var onComplete: (() -> Void)?
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var accountName: String = String(localized: "category.novel")
    @State private var showError: Bool = false
    @State private var selectedCategoryKey: String? = "category.novel"

    private let categoryKeys = [
        "category.novel", "category.business", "category.manga", "category.reference",
        "category.magazine", "category.travel", "category.essay", "category.study",
        "category.recipe", "category.photo", "category.picture_book", "category.children",
        "category.gift", "category.tsundoku"
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
        .alert("common.error", isPresented: $showError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("account.create.error")
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
                Text("brand.bookbank")
                    .font(.custom("Fearlessly Authentic", size: 36))
                    .foregroundColor(.white)
            }

            // サブタイトル
            VStack(spacing: 0) {
                Text("onboarding.subtitle1")
                Text("onboarding.subtitle2")
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
            Text("onboarding.prompt")
                .font(.system(size: 17, weight: .light))
                .foregroundColor(.white)

            // 入力フィールド
            HStack(spacing: 8) {
                TextField("account.name_placeholder", text: $accountName)
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

                Text("account.title")
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
            Array(categoryKeys.prefix(4)),
            Array(categoryKeys.dropFirst(4).prefix(4)),
            Array(categoryKeys.dropFirst(8).prefix(4)),
            Array(categoryKeys.dropFirst(12))
        ]
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        CategoryTag(
                            titleKey: LocalizedStringKey(key),
                            isSelected: selectedCategoryKey == key
                        ) {
                            if selectedCategoryKey == key {
                                selectedCategoryKey = nil
                                accountName = ""
                            } else {
                                selectedCategoryKey = key
                                accountName = String(localized: String.LocalizationValue(key))
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
            Text("account.create")
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
            sortOrder: 1,
            isActive: true
        )
        newPassbook.colorIndex = 10

        context.insert(newPassbook)

        do {
            try context.save()
            if let onComplete {
                onComplete()
            } else {
                dismiss()
            }
        } catch {
            #if DEBUG
            print("❌ Error creating first passbook: \(error)")
            #endif
            showError = true
        }
    }
}

// MARK: - Category Tag

struct CategoryTag: View {
    let titleKey: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
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
