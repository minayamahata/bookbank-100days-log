//
//  ChipFlowLayout.swift
//  BookBank
//
//  チップを左から詰めて折り返す汎用レイアウト（ステップ8'）。
//  つながりの一覧（本棚の検索入力前）と詳細画面のつながりチップ行で使う。
//  行の幅を超えるチップは行幅まで縮めて提案し、中のTextの省略（lineLimit）に委ねる。
//

import SwiftUI

struct ChipFlowLayout: Layout {
    /// チップ間の横の間隔
    var spacing: CGFloat = 8
    /// 行間
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = chipSize(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width
            usedWidth = max(usedWidth, x)
            x += spacing
            lineHeight = max(lineHeight, size.height)
        }

        let width = proposal.width ?? usedWidth
        return CGSize(width: width, height: subviews.isEmpty ? 0 : y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = chipSize(of: subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// チップの寸法。行幅より長いラベル（つながりは最長30文字）は行幅に収める
    private func chipSize(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let size = subview.sizeThatFits(.unspecified)
        guard size.width > maxWidth, maxWidth.isFinite else { return size }
        let constrained = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        return CGSize(width: min(constrained.width, maxWidth), height: constrained.height)
    }
}
