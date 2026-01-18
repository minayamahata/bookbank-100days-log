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
    
    @State private var accountName: String = ""
    @State private var showError: Bool = false
    
    // おすすめ口座名
    private let suggestedNames = ["プライベート", "漫画", "仕事用"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // ヘッダー
                VStack(spacing: 16) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("BookBankへようこそ！")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("最初の口座を開設しましょう")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                
                Spacer()
                
                // 入力フィールド
                VStack(alignment: .leading, spacing: 16) {
                    Text("口座名")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        TextField("プライベート", text: $accountName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .submitLabel(.done)
                            .onSubmit {
                                if !accountName.isEmpty {
                                    createAccount()
                                }
                            }
                        
                        Text("口座")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // おすすめ
                    VStack(alignment: .leading, spacing: 8) {
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
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // 開設ボタン
                Button(action: createAccount) {
                    Text("口座を開設")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accountName.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(accountName.isEmpty)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("口座の作成に失敗しました")
            }
        }
        .interactiveDismissDisabled()
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
