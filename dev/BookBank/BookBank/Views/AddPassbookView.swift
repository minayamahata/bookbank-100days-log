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
    
    // おすすめ口座名
    private let suggestedNames = ["プライベート", "漫画", "仕事用", "小説", "技術書", "雑誌"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 入力フィールド
                VStack(alignment: .leading, spacing: 12) {
                    Text("口座名")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        TextField("プライベート", text: $accountName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .submitLabel(.done)
                            .onSubmit {
                                if !accountName.isEmpty {
                                    createPassbook()
                                }
                            }
                        
                        Text("口座")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 24)
                
                // おすすめ
                VStack(alignment: .leading, spacing: 12) {
                    Text("おすすめ:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(suggestedNames, id: \.self) { name in
                            Button(action: {
                                accountName = name
                            }) {
                                Text(name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(16)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // テーマカラー選択
                VStack(alignment: .leading, spacing: 12) {
                    Text("テーマカラー")
                        .font(.headline)
                    
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
