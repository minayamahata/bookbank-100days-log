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

// MARK: - 共通ガラスカード背景

/// 円グラフ枠（口座一覧）と同じガラス＋細枠のカード背景
/// ライト: `.regular` / ダーク: `.clear` のリキッドグラスに、primary 0.1 の細い枠線を重ねる
struct GlassSectionCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24

    @Environment(\.colorScheme) private var colorScheme

    private var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    func body(content: Content) -> some View {
        Group {
            if isRunningForPreviews {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            } else if colorScheme == .dark {
                content
                    .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

extension View {
    /// 口座一覧の円グラフ枠と同じガラスカード背景を適用する
    func glassSectionCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassSectionCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - 総合口座背景

/// 総合口座専用の無彩色背景（口座一覧と同じ構成）
struct OverallAccountBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .light {
            // ライトモードはシルバーを敷かず無色（systemBackground）にする
            Color(.systemBackground)
                .ignoresSafeArea()
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Color.appGroupedBackground

                    Image("bg_glow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 2.2)
                        .blendMode(.screen)
                        .opacity(1)

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
}
