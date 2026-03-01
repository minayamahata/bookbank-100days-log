//
//  AddPassbookView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

struct AddPassbookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    @State private var accountName: String = "小説"
    @State private var selectedColorIndex: Int = 10
    @State private var showError: Bool = false
    @State private var showColorPicker = false
    @State private var customColor: Color = .blue
    @State private var useCustomColor: Bool = false
    @State private var showUnlimitedPaywall = false
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    @Environment(\.colorScheme) private var colorScheme
    
    // おすすめ口座名
    private let suggestedNames = [
        "小説", "ビジネス書", "マンガ", "参考書",
        "雑誌", "旅行記", "エッセイ", "勉強用",
        "レシピ", "写真集", "絵本", "子ども用",
        "プレゼント", "積読"
    ]
    
    private let tagRows: [[String]] = [
        ["小説", "ビジネス書", "マンガ", "参考書"],
        ["雑誌", "旅行記", "エッセイ", "勉強用"],
        ["レシピ", "写真集", "絵本", "子ども用"],
        ["プレゼント", "積読"]
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                // 入力フィールド
                VStack(alignment: .leading, spacing: 12) {
                    Text("口座名")
                        .font(.body)

                    
                    HStack(spacing: 8) {
                        TextField("小説", text: $accountName)
                            .font(.system(size: 18, weight: .light))
                            .multilineTextAlignment(.center)
                            .frame(height: 50)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                            .submitLabel(.done)
                            .onSubmit {
                                if !accountName.isEmpty {
                                    createPassbook()
                                }
                            }
                        
                        Text("口座")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 24)
                
                // おすすめ
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tagRows, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { name in
                                Button(action: {
                                    accountName = name
                                }) {
                                    Text(name)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .foregroundColor(accountName == name ? (colorScheme == .dark ? .black : .white) : .primary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(
                                            accountName == name
                                                ? Color.primary
                                                : Color.clear
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(accountName == name ? Color.clear : Color.primary.opacity(0.3), lineWidth: 1)
                                        )
                                        .cornerRadius(20)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer().frame(height: 16)
                
                // テーマカラー選択
                VStack(alignment: .leading, spacing: 12) {
                    Text("テーマカラー")
                        .font(.body)
                    
                    let columns = 6
                    let totalCount = PassbookColor.count + 1
                    let rows = (totalCount + columns - 1) / columns
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(0..<columns, id: \.self) { col in
                                    let index = row * columns + col
                                    if index < PassbookColor.count {
                                        Button {
                                            selectedColorIndex = index
                                            useCustomColor = false
                                        } label: {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(PassbookColor.color(for: index))
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 46)
                                                .overlay {
                                                    if !useCustomColor && selectedColorIndex == index {
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.primary, lineWidth: 2)
                                                            .padding(-3)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    } else if index == PassbookColor.count {
                                        Button {
                                            if unlimitedManager.isUnlimited {
                                                showColorPicker = true
                                            } else {
                                                showUnlimitedPaywall = true
                                            }
                                        } label: {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(
                                                        AngularGradient(
                                                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                            center: .center
                                                        )
                                                    )
                                                if !unlimitedManager.isUnlimited {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color.black.opacity(0.5))
                                                }
                                                Image(systemName: "plus")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .shadow(color: .black.opacity(0.3), radius: 1)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 46)
                                            .overlay {
                                                if useCustomColor {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.primary, lineWidth: 2)
                                                        .padding(-3)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 46)
                                    }
                                }
                            }
                        }
                    }
                    
                    if useCustomColor {
                        VStack(alignment: .trailing, spacing: 0) {
                            Triangle()
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 12, height: 6)
                                .padding(.trailing, 28)
                            
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(customColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary, lineWidth: 2)
                                            .padding(-3)
                                    )
                                
                                Text("カスタムカラー")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button("変更") {
                                    showColorPicker = true
                                }
                                .font(.system(size: 14))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal)
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("新しい口座")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        createPassbook()
                    }
                    .disabled(accountName.isEmpty)
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("口座の作成に失敗しました")
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerSheet(selectedColor: $customColor, onComplete: {
                    useCustomColor = true
                })
            }
            .sheet(isPresented: $showUnlimitedPaywall) {
                UnlimitedPaywallView()
            }
        }
        .tint(.accentColor)
    }
    
    // MARK: - Private Methods
    
    private func createPassbook() {
        guard !accountName.isEmpty else { return }
        
        // 次のsortOrderを計算
        let maxSortOrder = passbooks.map { $0.sortOrder }.max() ?? 0
        
        let newPassbook = Passbook(
            name: accountName,
            type: .custom,
            sortOrder: maxSortOrder + 1,
            isActive: true
        )
        newPassbook.colorIndex = selectedColorIndex
        if useCustomColor {
            newPassbook.customColorHex = PassbookColor.hexString(from: customColor)
        }
        
        context.insert(newPassbook)
        
        do {
            try context.save()
            print("✅ New passbook created: \(accountName)")
            dismiss()
        } catch {
            print("❌ Error creating passbook: \(error)")
            showError = true
        }
    }
}

#Preview {
    AddPassbookView()
        .modelContainer(for: [Passbook.self, UserBook.self])
}
