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
    
    @State private var accountName: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var showError: Bool = false
    
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
                    
                    HStack(spacing: 0) {
                        ForEach(0..<PassbookColor.count, id: \.self) { index in
                            Button {
                                selectedColorIndex = index
                            } label: {
                                Circle()
                                    .fill(PassbookColor.color(for: index))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if selectedColorIndex == index {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 2)
                                                .frame(width: 30, height: 30)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
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
        }
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
