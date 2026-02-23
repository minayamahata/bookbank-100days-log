//
//  PlatinumAlertView.swift
//  BookBank
//
//  Created on 2026/02/22
//

import SwiftUI

/// Platinum機能への誘導アラート（統一デザイン）
struct PlatinumAlertView: View {
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
                    Text("Platinum機能")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // ボタン
                VStack(spacing: 12) {
                    // Platinum機能を体験するボタン（青塗り）
                    Button(action: onConfirm) {
                        Text("Platinum機能を体験する")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    
                    // キャンセルボタン（黒テキスト）
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
    PlatinumAlertView(
        message: "4つ以上の口座を作成するにはPlatinum版が必要です。",
        onConfirm: {},
        onCancel: {}
    )
}
