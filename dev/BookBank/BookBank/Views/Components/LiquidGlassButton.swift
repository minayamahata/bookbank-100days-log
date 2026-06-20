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
    var isBlackTheme: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// 白テーマ＋ダークモード時は白を使用
    private var effectiveColor: Color {
        if colorScheme == .dark && isBlackTheme {
            return .white
        }
        return color
    }
    
    /// ダークモードでガラスが白系のときだけ黒、それ以外は白
    private var textColor: Color {
        if colorScheme == .dark && effectiveColor.luminance > 0.5 {
            return .black
        }
        return .white
    }
    
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 16))
            .foregroundColor(textColor)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(effectiveColor))
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
