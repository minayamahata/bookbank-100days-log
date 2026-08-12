//
//  CollapsibleBottomBar.swift
//  BookBank
//
//  画面下に貼り付けた帯（`safeAreaInset(edge: .bottom)`）を畳むための入れ物。
//  **畳むときも階層からは外さない**——`if` で出し入れすると、キーボードの入れ替わりと
//  重なったときに戻ってきた帯が左上（ナビゲーションバーの上）に小さく描かれる
//  （**2026-08-12 オーナー報告B**——出典ページのテンキーから抜けたときに発生）。
//  高さと不透明度だけを畳めば、レイアウトの持ち主が入れ替わらないのでこの壊れ方をしない。
//

import SwiftUI

struct CollapsibleBottomBar<Content: View>: View {
    let isCollapsed: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(height: isCollapsed ? 0 : nil)
            .opacity(isCollapsed ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isCollapsed)
            .accessibilityHidden(isCollapsed)
    }
}
