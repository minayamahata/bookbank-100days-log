//
//  PassbookDepositSheet.swift
//  BookBank
//
//  通帳画面の入金履歴ボトムシート（磁石スナップ付き）
//

import SwiftUI

/// ボトムシートのスナップ位置
enum PassbookSheetDetent: Equatable {
    case collapsed
    case expanded
}

/// 磁石スナップ付きボトムシート
struct PassbookDepositSheet<ListContent: View>: View {
    let totalValue: Int
    let accentColor: Color
    let isOverallAccount: Bool
    let themeColor: Color
    let collapsedTop: CGFloat
    let expandedTop: CGFloat
    /// 展開時ヘッダーをナビバー直下に置くための余白（= 画面上端からコンテンツ開始までの距離）
    let expandedHeaderInset: CGFloat
    @Binding var detent: PassbookSheetDetent
    @Binding var locksRowNavigation: Bool
    @ViewBuilder let listContent: () -> ListContent

    @State private var dragOffset: CGFloat = 0
    @State private var listScrollOffset: CGFloat = 0

    private var currentTop: CGFloat {
        let base = detent == .collapsed ? collapsedTop : expandedTop
        return min(max(base + dragOffset, expandedTop), collapsedTop)
    }

    private var expansionProgress: CGFloat {
        guard collapsedTop > expandedTop else { return detent == .expanded ? 1 : 0 }
        return 1 - (currentTop - expandedTop) / (collapsedTop - expandedTop)
    }

    private var topCornerRadius: CGFloat {
        40 * (1 - expansionProgress)
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: topCornerRadius
        )
    }

    private var isListAtTop: Bool {
        listScrollOffset <= 4
    }

    var body: some View {
        GeometryReader { geometry in
            let containerHeight = geometry.size.height
            let sheetHeight = max(containerHeight - currentTop, containerHeight)

            sheetContent
                .frame(width: geometry.size.width, height: sheetHeight, alignment: .top)
                .offset(y: currentTop)
                .ignoresSafeArea(edges: detent == .expanded ? .top : [])
                .animation(.spring(response: 0.35, dampingFraction: 0.88), value: detent)
                .transaction { transaction in
                    if dragOffset != 0 {
                        transaction.animation = nil
                    }
                }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            sheetHeader

            HStack {
                Text("passbook.deposit_history")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, expansionProgress > 0.5 ? 4 : 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .gesture(detent == .collapsed ? expandDragGesture : nil)
            .simultaneousGesture(detent == .expanded ? collapseDragGesture : nil)

            ScrollView {
                listContent()
            }
            .scrollDisabled(detent == .collapsed)
            .simultaneousGesture(detent == .collapsed ? expandDragGesture : nil)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                listScrollOffset = offset
            }
            .simultaneousGesture(detent == .expanded && isListAtTop ? collapseDragGesture : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                sheetCollapsedBackground
                sheetExpandedBackground.opacity(expansionProgress)
            }
        }
        .clipShape(sheetShape)
        .overlay(sheetShape.strokeBorder(listGlassBorder, lineWidth: 0.5))
        .contentShape(sheetShape)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var sheetCollapsedBackground: Color {
        colorScheme == .dark ? .appCardBackground : .appGroupedBackground
    }

    private var sheetExpandedBackground: Color {
        colorScheme == .dark ? .appGroupedBackground : .appSectionBackground
    }

    private var listGlassBorder: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.28 : 0.55), location: 0),
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), location: 0.5),
                .init(color: Color.primary.opacity(0.1), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sheetHeaderHeight: CGFloat {
        let collapsedHeight: CGFloat = 22
        let expandedHeight: CGFloat = 10 + expandedHeaderInset
        return collapsedHeight + (expandedHeight - collapsedHeight) * expansionProgress
    }

    @ViewBuilder
    private var sheetHeader: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .opacity(1 - expansionProgress)
                .padding(.top, 8)
                .padding(.bottom, 2)

            // 金額はナビバー（固定位置）が担当。ドラッグ中にスライドして
            // 悪目立ちしないよう、シート内のコンパクト金額は表示しない。
            PassbookSheetCompactHeader(
                totalValue: totalValue,
                accentColor: accentColor,
                isOverallAccount: isOverallAccount,
                themeColor: themeColor,
                onCollapse: collapseSheet
            )
            .opacity(0)
            .allowsHitTesting(false)
        }
        .frame(height: sheetHeaderHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(detent == .collapsed ? expandDragGesture : nil)
        .simultaneousGesture(detent == .expanded ? collapseDragGesture : nil)
    }

    /// 折りたたみ時：シート全体を上方向にドラッグして展開
    private var expandDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if abs(value.translation.height) > 4 {
                    locksRowNavigation = true
                }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                snapSheet(velocity: value.predictedEndTranslation.height - value.translation.height)
                releaseRowNavigationAfterSheetDrag()
            }
    }

    /// 展開時：下方向ドラッグで折りたたみ（リスト先頭のときのみ ScrollView 側で有効）
    private var collapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                if value.translation.height > 4 {
                    locksRowNavigation = true
                }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                guard value.translation.height > 0 else { return }
                snapSheet(velocity: value.predictedEndTranslation.height - value.translation.height)
                releaseRowNavigationAfterSheetDrag()
            }
    }

    private func releaseRowNavigationAfterSheetDrag() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            locksRowNavigation = false
        }
    }

    private func collapseSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            detent = .collapsed
            dragOffset = 0
        }
    }

    private func snapSheet(velocity: CGFloat) {
        let base = detent == .collapsed ? collapsedTop : expandedTop
        let projected = base + dragOffset
        let midpoint = (collapsedTop + expandedTop) / 2

        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            if detent == .collapsed {
                if velocity < -120 || projected < midpoint {
                    detent = .expanded
                }
            } else {
                if velocity > 120 || projected > midpoint || dragOffset > 40 {
                    detent = .collapsed
                }
            }
            dragOffset = 0
        }
    }
}

/// 展開時のコンパクトヘッダー
private struct PassbookSheetCompactHeader: View {
    let totalValue: Int
    let accentColor: Color
    let isOverallAccount: Bool
    let themeColor: Color
    let onCollapse: () -> Void

    private var priceStyle: AnyShapeStyle {
        if isOverallAccount {
            return AnyShapeStyle(accentColor)
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: themeColor, location: 0),
                    Gradient.Stop(color: themeColor, location: 0.6),
                    Gradient.Stop(color: themeColor.opacity(0.3), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            DisplayCurrencyPriceText(
                amount: totalValue,
                font: .system(size: 18, weight: .semibold),
                symbolFont: .system(size: 12, weight: .medium)
            )
            .foregroundStyle(priceStyle)

            Spacer()

            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
