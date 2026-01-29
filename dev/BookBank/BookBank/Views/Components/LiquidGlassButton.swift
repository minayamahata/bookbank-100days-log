//
//  LiquidGlassButton.swift
//  BookBank
//
//  Created on 2026/01/25
//

import SwiftUI

/// リキッドグラス登録ボタン（iOS標準glassEffect使用）
struct LiquidGlassButton: View {
    let color: Color
    let size: CGFloat = 56
    
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 16))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(color))
            .clipShape(Circle())
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
