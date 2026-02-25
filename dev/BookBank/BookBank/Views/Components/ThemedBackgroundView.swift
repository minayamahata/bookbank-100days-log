//
//  ThemedBackgroundView.swift
//  BookBank
//
//  Created on 2026/02/24
//

import SwiftUI

/// テーマカラーに応じた背景ビュー
/// 通帳、本棚、集計ページなどで共通使用
struct ThemedBackgroundView: View {
    let themeColor: Color
    let isBlackTheme: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// 実際に使用するグラデーションカラー
    private var gradientColor: Color {
        if colorScheme == .dark && isBlackTheme {
            return Color(hex: "292826")
        }
        return themeColor
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // ベース：systemBackground
                Color(.systemBackground)
                
                // グラデーション：テーマカラー → 透明（円形）
                RadialGradient(
                    stops: [
                        Gradient.Stop(color: gradientColor, location: 0),
                        Gradient.Stop(color: gradientColor, location: 0.4),
                        Gradient.Stop(color: gradientColor.opacity(0), location: 1)
                    ],
                    center: UnitPoint(x: 0.4, y: 0.1),
                    startRadius: 0,
                    endRadius: geometry.size.width * 1
                )
                
                // 光源PNG：上部中央に配置
                Image("bg_glow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 2.2)
                    .blendMode(.screen)
                    .opacity(1)
                
                // ノイズテクスチャ：全体に重ねる
                Image("bg_noise")
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(0.2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ThemedBackgroundView(themeColor: .blue, isBlackTheme: false)
}
