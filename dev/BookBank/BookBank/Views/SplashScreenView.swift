//
//  SplashScreenView.swift
//  BookBank
//
//  Created on 2026/01/26
//

import SwiftUI

struct SplashScreenView: View {
    // 背景画像の候補
    private static let backgroundImages = [
        "SplashBackground1",
        "SplashBackground2",
        "SplashBackground3",
        "SplashBackground4",
        "SplashBackground5",
        "SplashBackground6"
    ]
    
    // ランダムに選ばれた背景画像
    private let selectedBackground: String
    
    // アニメーション状態
    @State private var showDots = false
    @State private var showLogo = false
    @State private var showTagline = false
    @State private var showCorners = false
    @State private var logoOffset: CGFloat = 20
    
    init() {
        selectedBackground = Self.backgroundImages.randomElement() ?? "SplashBackground1"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景画像（ランダム）
                Image(selectedBackground)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // コンテンツ
                VStack {
                    // 上部: Imagination / Depth
                    HStack {
                        Text("Imagination")
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundColor(.white)

                        Spacer()

                        Text("Depth")
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, geometry.safeAreaInsets.top + 60)
                    .opacity(showCorners ? 1 : 0)

                    Spacer()

                    // 中央: ロゴ
                    VStack(spacing: 29) {
                        // ロゴアイコン（コロン形状）
                        VStack(spacing: 9) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .opacity(showDots ? 1 : 0)
                                .scaleEffect(showDots ? 1 : 0.5)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .opacity(showDots ? 1 : 0)
                                .scaleEffect(showDots ? 1 : 0.5)
                        }

                        // テキスト
                        VStack(spacing: 0) {
                            Text("BookBank")
                                .font(.custom("Fearlessly Authentic", size: 42))
                                .foregroundColor(.white)
                                .opacity(showLogo ? 1 : 0)

                            Text("your mind.")
                                .font(.custom("Fearlessly Authentic Italic", size: 25))
                                .foregroundColor(.white.opacity(0.7))
                                .blendMode(.overlay)
                                .opacity(showTagline ? 1 : 0)
                        }
                    }
                    .offset(y: logoOffset)

                    Spacer()

                    // 下部: Growth / Reverie
                    HStack {
                        Text("Growth")
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundColor(.white)

                        Spacer()

                        Text("Reverie")
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 60)
                    .opacity(showCorners ? 1 : 0)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // ドットのアニメーション
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            showDots = true
        }
        
        // ロゴのアニメーション
        withAnimation(.easeOut(duration: 1.0).delay(0.8)) {
            showLogo = true
            logoOffset = 0
        }
        
        // タグラインのアニメーション
        withAnimation(.easeOut(duration: 1.0).delay(1.5)) {
            showTagline = true
        }
        
        // 四隅のテキストのアニメーション
        withAnimation(.easeOut(duration: 1.0).delay(2.2)) {
            showCorners = true
        }
    }
}

#Preview {
    SplashScreenView()
}
