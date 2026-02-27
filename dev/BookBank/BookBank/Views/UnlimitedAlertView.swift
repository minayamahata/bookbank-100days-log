//
//  UnlimitedAlertView.swift
//  BookBank
//
//  Created on 2026/02/22
//

import SwiftUI

/// Unlimited機能への誘導アラート（統一デザイン）
struct UnlimitedAlertView: View {
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // 背景オーバーレイ
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // ダイアログ本体
            VStack(spacing: 20) {
                // タイトルとメッセージ
                VStack(spacing: 8) {
                    Text("Unlimited機能")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // ボタン
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text("Unlimited機能を体験する")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appCardBackground)
            )
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    UnlimitedAlertView(
        message: "4つ以上の口座を作成するにはUnlimited版が必要です。",
        onConfirm: {},
        onCancel: {}
    )
}
