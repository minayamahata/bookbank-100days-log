//
//  LiquidGlassButton.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI

/// リキッドグラス風エフェクトを持つ登録ボタン
struct LiquidGlassButton: View {
    let color: Color
    let size: CGFloat = 56
    
    var body: some View {
        ZStack {
            // ドロップシャドウ（軽め）
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size, height: size)
                .blur(radius: 8)
                .offset(y: 3)
            
            // ガラス背景
            Circle()
                .fill(.ultraThinMaterial.opacity(0.6))
                .frame(width: size, height: size)
            
            // メインカラー: しっかりした色
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
            
            // 内側シャドウ: 下部に軽く影を入れてガラスの厚み感
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
            
            // エッジの光沢（はっきり見える）
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
                .frame(width: size - 0.5, height: size - 0.5)
            
            // プラスアイコン
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.15), radius: 0.5, x: 0, y: 0.5)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 30) {
            LiquidGlassButton(color: .blue)
            LiquidGlassButton(color: .green)
            LiquidGlassButton(color: .orange)
            LiquidGlassButton(color: .purple)
        }
    }
}
