//
//  WhatsNewView.swift
//  BookBank
//
//  新機能のお知らせ（docs/whats-new-message-design.md）。
//  背景を暗くした中央カードに4ページを表示する。状態の保存は呼び出し側が行う。
//

import SwiftUI

/// ページャの高さ計測用（4ページ中いちばん高いものに合わせる）
private struct WhatsNewPageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 新機能のお知らせカード。
/// - 「×」→ `onClose`（一時的に閉じる。状態は変えない）
/// - 「はじめる」→ `onConfirm`（確認済みとして閉じる）
/// - 背景タップでは閉じない。開くたびに1ページ目から始まる。
struct WhatsNewView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onClose: () -> Void
    var onConfirm: () -> Void

    @State private var pageIndex = 0
    @State private var visible = false
    @State private var measuredPageHeight: CGFloat?

    /// 見出し・選択中ドット・「次へ」の既存ゴールド
    private var goldColor: Color {
        PassbookColor.color(for: PassbookColor.goldThemeIndex)
    }

    /// 「はじめる」の青緑（承認イメージの近似）。このView限定で、色体系には追加しない。
    private static let getStartedColor = Color(hex: "0F8578")

    /// カード背景。ライトは #ECECEC、ダークは従来のカード色（#1C1C1E）。
    /// このView限定で、`Color.appCardBackground` のライト値は変更しない。
    private static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1)
            : UIColor(red: 0xEC/255.0, green: 0xEC/255.0, blue: 0xEC/255.0, alpha: 1)
    })

    private var pages: [WhatsNewPage] { WhatsNewMessage.pages }
    private var isLastPage: Bool { pageIndex == pages.count - 1 }

    var body: some View {
        let _ = themeManager.currentTheme
        let _ = languageManager.currentLanguage

        ZStack {
            // モーダル背景（DESIGN_SYSTEM 1章）。タップしても閉じない。
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            GeometryReader { geometry in
                card(maxPagerHeight: max(200, geometry.size.height - 260))
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            if reduceMotion {
                visible = true
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    visible = true
                }
            }
        }
    }

    /// カードの高さは内容に合わせる（全高固定にしない）。
    /// カード内は縦スクロールさせない（2026-08-20 オーナー指示）。
    /// 閉じるボタンはスワイプ中のページ内容より上に出すため、ZStackの最上層に置く
    private func card(maxPagerHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                pager(maxPagerHeight: maxPagerHeight)

                pageDots
                    .padding(.top, 12)

                actionButton
                    .padding(.top, 32)
                    .padding(.bottom, 24)
            }

            closeButton
                .padding(8)
                .zIndex(1)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Self.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    private func pager(maxPagerHeight: CGFloat) -> some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                // カード内は縦スクロールさせない。上限超過時は下端で切れる（実機確認項目）
                pageContent(page)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: min(measuredPageHeight ?? 480, maxPagerHeight))
        .background(
            // 非表示の実測用コピー。いちばん高いページに合わせる
            ZStack(alignment: .top) {
                ForEach(pages) { page in
                    pageContent(page)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WhatsNewPageHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
        )
        .onPreferenceChange(WhatsNewPageHeightKey.self) { height in
            if height > 0 {
                measuredPageHeight = height
            }
        }
    }

    private func pageContent(_ page: WhatsNewPage) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: L10n.format(WhatsNewMessage.headerKey, page.id))
                .font(.app(.subheadline, weight: .bold))
                .foregroundColor(goldColor)
                .padding(.top, 32)
                .padding(.horizontal, 24)

            Text(LocalizedStringKey(page.titleKey))
                .font(.app(.title3, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            Text(LocalizedStringKey(page.descriptionKey))
                .font(.app(.subheadline))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            // カード横幅100%・9:7のまま切り抜かない
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .padding(.top, 24)
                .accessibilityHidden(true)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? goldColor : Color.primary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L10n.format(
            WhatsNewMessage.pageIndicatorAccessibilityKey,
            Int64(pageIndex + 1),
            Int64(pages.count)
        )))
    }

    /// 総合口座の口座カプセルボタンと同じスタイル（tintだけページで切り替える）
    private var actionButton: some View {
        Button {
            if isLastPage {
                dismiss(onConfirm)
            } else {
                advancePage()
            }
        } label: {
            Text(isLastPage ? LocalizedStringKey(WhatsNewMessage.getStartedKey)
                            : LocalizedStringKey(WhatsNewMessage.nextKey))
                .font(.app(.footnote))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .passbookCapsuleGradient(tint: isLastPage ? Self.getStartedColor : goldColor)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            dismiss(onClose)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .padding(6)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(WhatsNewMessage.closeAccessibilityKey)))
    }

    private func advancePage() {
        let next = min(pageIndex + 1, pages.count - 1)
        if reduceMotion {
            pageIndex = next
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pageIndex = next
            }
        }
    }

    /// フェードアウトしてから閉じる。Reduce Motion 有効時は即時。
    private func dismiss(_ completion: @escaping () -> Void) {
        if reduceMotion {
            completion()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion()
        }
    }
}

#Preview {
    WhatsNewView(onClose: {}, onConfirm: {})
        .environment(ThemeManager())
        .environment(LanguageManager())
}
