import Photos
import SwiftUI
import UIKit

struct MonthlyLogShareSession: Identifiable, Equatable {
    let year: Int
    let month: Int
    let snapshot: MonthlyLogShareSnapshot
    let covers: [String: UIImage]

    var id: String { "\(year)-\(month)" }

    static func == (lhs: MonthlyLogShareSession, rhs: MonthlyLogShareSession) -> Bool {
        lhs.id == rhs.id
            && lhs.snapshot == rhs.snapshot
            && lhs.covers.keys == rhs.covers.keys
    }
}

private enum ActionFeedback: Equatable {
    case copied
    case saved

    var title: LocalizedStringKey {
        switch self {
        case .copied: "common.copied"
        case .saved: "monthly_log_share.saved"
        }
    }

    var localizationKey: String {
        switch self {
        case .copied: "common.copied"
        case .saved: "monthly_log_share.saved"
        }
    }
}

struct MonthlyLogShareView: View {
    /// 出力キャッシュのキー。ページと背景モードで決まる。
    private struct ExportKey: Hashable {
        let page: Int
        let mode: MonthlyLogShareBackgroundMode
    }

    let session: MonthlyLogShareSession
    var saver: PhotoLibrarySaving = SystemPhotoLibrarySaver()
    let onClose: () -> Void

    @State private var page = 0
    @State private var backgroundMode: MonthlyLogShareBackgroundMode = .defaultMode
    @State private var exportCache: [ExportKey: MonthlyLogShareExportAsset] = [:]
    @State private var isRendering = false
    @State private var actionFeedback: ActionFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var showDeniedAlert = false
    @State private var showRestrictedAlert = false
    @State private var showFailedAlert = false
    @State private var isSaving = false
    @State private var isSharingToInstagram = false
    @State private var showInstagramUnavailableAlert = false
    @State private var showInstagramOpenFailedAlert = false
    @State private var shareSourceView: UIView?

    private var templates: [MonthlyLogShareTemplate] {
        [.calendarSummary, .largeMonth, .verticalMonth, .circledCalendar, .minimalSummary, .monthInBooks]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            middleSection
            actionRow
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Color.black)
        .task(id: currentExportKey) {
            await renderCurrentIfNeeded()
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
        }
        .alert("monthly_log_share.save_denied.title", isPresented: $showDeniedAlert) {
            Button("book.camera.open_settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("monthly_log_share.save_denied.message")
        }
        .alert("monthly_log_share.save_denied.title", isPresented: $showRestrictedAlert) {
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("monthly_log_share.save_denied.message")
        }
        .alert("monthly_log_share.save_failed", isPresented: $showFailedAlert) {
            Button("common.cancel", role: .cancel) {}
        }
        .alert("monthly_log_share.instagram_unavailable.title", isPresented: $showInstagramUnavailableAlert) {
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("monthly_log_share.instagram_unavailable.message")
        }
        .alert("monthly_log_share.instagram_open_failed", isPresented: $showInstagramOpenFailedAlert) {
            Button("common.cancel", role: .cancel) {}
        }
    }

    private var successToastTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96))
    }

    private func successToast(_ feedback: ActionFeedback) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.black)
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)

            Text(feedback.title)
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.cancel"))

            Spacer()

            Text("monthly_log_share.title")
                .font(.app(.subheadline))
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        // ヘッダー下の余白は headerToPreviewMinimumSpacing（カルーセル側）だけで管理する
    }

    // MARK: - 縦方向の間隔（2026-08-21 確定値。見た目上の距離で管理する）

    /// ヘッダー領域の下端からプレビューカード上端までの最小間隔
    private static let headerToPreviewMinimumSpacing: CGFloat = 24
    /// 9:16 カードの見えている下端からページドット上端まで
    private static let previewToPageDotsSpacing: CGFloat = 10
    /// ページドット下端から、背景スウォッチの見える外周（38pt 選択リング）上端まで
    private static let pageDotsToSwatchVisibleSpacing: CGFloat = 10
    /// スウォッチのタップ領域 44pt と見える外周 38pt の差の片側（透明な余白）
    private static let swatchTapAreaTopInset: CGFloat = (44 - 38) / 2
    private static let pageDotsHeight: CGFloat = 6
    private static let swatchRowHeight: CGFloat = 44

    /// ページドットとスウォッチ行の間に置くレイアウト上の間隔。
    /// タップ領域の透明余白 3pt を差し引き、見た目の距離が 10pt になるようにする。
    private static var pageDotsToSwatchLayoutSpacing: CGFloat {
        pageDotsToSwatchVisibleSpacing - swatchTapAreaTopInset
    }

    /// カルーセルの下に来る固定行の高さ。カードはヘッダー下 24pt とこの分を除いた高さで決め、
    /// 余った縦スペースはスウォッチとアクション行の間に置く。
    private static var fixedRowsBelowCarousel: CGFloat {
        previewToPageDotsSpacing + pageDotsHeight + pageDotsToSwatchLayoutSpacing + swatchRowHeight
    }

    /// タイトル直下から カルーセル → ページドット → 背景スウォッチ と詰めて並べ、
    /// 余りは末尾の Spacer が吸収する（アクション行は動かない）。
    private var middleSection: some View {
        GeometryReader { geometry in
            let spacing = MonthlyLogSharePreviewMetrics.pageSpacing
            let desiredPeek = MonthlyLogSharePreviewMetrics.desiredPeek
            let maxCardWidth = max(1, geometry.size.width - 2 * (desiredPeek + spacing))
            let maxCardHeight = max(
                1,
                geometry.size.height - Self.headerToPreviewMinimumSpacing - Self.fixedRowsBelowCarousel
            )
            let fitted = MonthlyLogSharePreviewMetrics.referenceCardSize(
                in: CGSize(width: maxCardWidth, height: maxCardHeight)
            )
            let referenceWidth = fitted.width * MonthlyLogSharePreviewMetrics.displayScale
            let baseCardSize = MonthlyLogSharePreviewMetrics.cardSize(
                format: .portrait,
                referenceWidth: referenceWidth
            )

            VStack(spacing: 0) {
                carouselScroll(
                    baseCardSize: baseCardSize,
                    referenceWidth: referenceWidth,
                    spacing: spacing,
                    availableWidth: geometry.size.width
                )
                .overlay(alignment: .bottom) {
                    if let actionFeedback {
                        successToast(actionFeedback)
                            .padding(.bottom, 22)
                            .transition(successToastTransition)
                            .zIndex(1)
                    }
                }
                .overlay {
                    if isRendering, currentAsset == nil {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: actionFeedback)
                .padding(.top, Self.headerToPreviewMinimumSpacing)
                pageDots
                    .padding(.top, Self.previewToPageDotsSpacing)
                backgroundSelector
                    .padding(.top, Self.pageDotsToSwatchLayoutSpacing)
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// カード寸法の計算・横スワイプ・見切れ量は従来のまま。高さだけカードちょうどに固定する。
    private func carouselScroll(
        baseCardSize: CGSize,
        referenceWidth: CGFloat,
        spacing: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let pageWidth = baseCardSize.width
        let sideInset = max(0, (availableWidth - pageWidth) / 2)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                    previewPage(
                        template: template,
                        cardSize: MonthlyLogSharePreviewMetrics.cardSize(
                            format: template.canvasFormat,
                            referenceWidth: referenceWidth
                        )
                    )
                    .frame(
                        width: pageWidth,
                        height: baseCardSize.height,
                        alignment: .center
                    )
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, sideInset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(
            id: Binding(
                get: { Optional(page) },
                set: { page = $0 ?? page }
            )
        )
        .frame(height: baseCardSize.height)
    }

    private func previewPage(
        template: MonthlyLogShareTemplate,
        cardSize: CGSize
    ) -> some View {
        flatPreview(template: template, cardSize: cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                // 黒背景カードはシート背景と同化するため輪郭だけ足す
                if backgroundMode == .black {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
            }
    }

    private func flatPreview(
        template: MonthlyLogShareTemplate,
        cardSize: CGSize
    ) -> some View {
        let logicalSize = template.canvasFormat.logicalSize
        let scale = logicalSize.width > 0 ? cardSize.width / logicalSize.width : 1
        return ZStack {
            switch backgroundMode {
            case .white:
                Color.white
            case .black:
                Color.black
            case .transparent:
                CheckerboardBackground()
            }
            MonthlyLogShareCanvas(
                snapshot: session.snapshot,
                covers: session.covers,
                template: template,
                palette: backgroundMode.palette
            )
            .frame(width: logicalSize.width, height: logicalSize.height)
            .scaleEffect(scale)
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(templates.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("monthly_log_share.title"))
        .accessibilityValue(Text("\(page + 1) / \(templates.count)"))
    }

    private var backgroundSelector: some View {
        HStack(spacing: 8) {
            ForEach(MonthlyLogShareBackgroundMode.allCases) { mode in
                Button {
                    backgroundMode = mode
                } label: {
                    // 中身・通常外枠・選択リングを別サイズの層に分け、中身の上へ線を重ねない
                    ZStack {
                        swatchContent(mode)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                        // 通常の外枠: 中身の外側 32pt・1pt。不透明グレーで市松を透けさせない
                        Circle()
                            .stroke(Color(white: 0.35), lineWidth: 1)
                            .frame(width: 32, height: 32)
                        if backgroundMode == mode {
                            // 選択リング: さらに外側 38pt・2pt 白。中身との間に黒い隙間が残る
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 38, height: 38)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(mode.localizationKey)))
                .accessibilityAddTraits(backgroundMode == mode ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func swatchContent(_ mode: MonthlyLogShareBackgroundMode) -> some View {
        switch mode {
        case .white:
            Circle().fill(Color.white)
        case .black:
            // 輪郭は共通の 2pt 境界線が担うため、個別の縁取りは持たない
            Circle().fill(Color.black)
        case .transparent:
            CheckerboardBackground(cell: 5)
        }
    }

    private var currentTemplate: MonthlyLogShareTemplate {
        templates[min(max(page, 0), templates.count - 1)]
    }

    /// 表示順ではなくテンプレート属性で判定する。書影ありはボタン自体を出さない。
    private var showsInstagramStoriesButton: Bool {
        currentTemplate.supportsInstagramStoriesShare
    }

    /// 4ボタン時は小さい端末でラベルが重ならないよう間隔だけ狭める。3ボタンは従来どおり。
    private var actionRowSpacing: CGFloat {
        showsInstagramStoriesButton ? 16 : 28
    }

    private var canShareToInstagramStories: Bool {
        currentAsset != nil && !isRendering && !isSharingToInstagram
    }

    private var actionRow: some View {
        HStack(spacing: actionRowSpacing) {
            if showsInstagramStoriesButton {
                actionButton(
                    assetName: "icn_instagram",
                    title: "monthly_log_share.instagram_stories",
                    enabled: canShareToInstagramStories,
                    fillsCircle: true
                ) {
                    Task { await shareToInstagramStories() }
                }
            }
            actionButton(assetName: "icn_copy", title: "common.copy", enabled: currentAsset != nil) {
                copyCurrent()
            }
            actionButton(
                assetName: "icn_download",
                title: "common.save",
                enabled: currentAsset != nil && !isSaving
            ) {
                Task { await saveCurrent() }
            }
            actionButton(assetName: "icn_more", title: "monthly_log_share.more", enabled: currentAsset != nil) {
                shareCurrent()
            }
            .background {
                ShareSourceView(view: $shareSourceView)
            }
        }
        .padding(.horizontal, showsInstagramStoriesButton ? 12 : 0)
    }

    private func actionButton(
        assetName: String,
        title: LocalizedStringKey,
        enabled: Bool,
        fillsCircle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if fillsCircle {
                        Image(assetName)
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    } else {
                        Image(assetName)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                }
                .opacity(enabled ? 1 : 0.35)
                Text(title)
                    .font(.app(.caption))
                    .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 出力の遅延生成

    private var currentExportKey: ExportKey {
        ExportKey(
            page: min(max(page, 0), templates.count - 1),
            mode: backgroundMode
        )
    }

    private var currentAsset: MonthlyLogShareExportAsset? {
        exportCache[currentExportKey]
    }

    @MainActor
    private func renderCurrentIfNeeded() async {
        let key = currentExportKey
        if exportCache[key] != nil {
            return
        }
        isRendering = true
        // ProgressView を一度描画してから重い生成に入る
        await Task.yield()
        guard !Task.isCancelled else {
            isRendering = false
            return
        }
        let asset = MonthlyLogShareRenderer.exportAsset(
            snapshot: session.snapshot,
            covers: session.covers,
            template: templates[key.page],
            mode: backgroundMode
        )
        if let asset {
            exportCache[key] = asset
        }
        isRendering = false
    }

    // MARK: - アクション

    private func copyCurrent() {
        guard let asset = currentAsset else { return }
        presentFeedback(.copied)
        Task { @MainActor in
            MonthlyLogShareExport.copyToPasteboard(asset)
        }
    }

    private func saveCurrent() async {
        guard let asset = currentAsset, !isSaving else { return }
        isSaving = true
        let alreadyAllowed = Self.canSaveWithoutPrompt(saver.authorizationStatus())
        if alreadyAllowed {
            presentFeedback(.saved)
        }
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: asset.data)
        isSaving = false
        switch outcome {
        case .saved:
            if !alreadyAllowed {
                presentFeedback(.saved)
            }
        case .ignoredBecauseBusy:
            break
        case .denied:
            clearFeedbackIfNeeded()
            showDeniedAlert = true
        case .restricted:
            clearFeedbackIfNeeded()
            showRestrictedAlert = true
        case .failed:
            clearFeedbackIfNeeded()
            showFailedAlert = true
        }
    }

    private static func canSaveWithoutPrompt(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    private func presentFeedback(_ feedback: ActionFeedback) {
        feedbackDismissTask?.cancel()
        actionFeedback = feedback
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        announceFeedback(feedback)
        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if actionFeedback == feedback {
                actionFeedback = nil
            }
        }
    }

    private func clearFeedbackIfNeeded() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        actionFeedback = nil
    }

    private func announceFeedback(_ feedback: ActionFeedback) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: L10n.string(feedback.localizationKey)
        )
    }

    private func shareCurrent() {
        guard let asset = currentAsset else { return }
        do {
            let url = try MonthlyLogShareExport.writeTemporaryFile(asset)
            MonthlyLogShareActivityPresenter.present(url: url, sourceView: shareSourceView)
        } catch {
            showFailedAlert = true
        }
    }

    private func shareToInstagramStories() async {
        guard canShareToInstagramStories else { return }
        isSharingToInstagram = true
        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: currentAsset,
            template: currentTemplate,
            appID: MonthlyLogShareInstagramStories.appID(from: .main),
            opener: SystemInstagramStoriesURLOpener(),
            pasteboard: SystemInstagramStoriesPasteboard()
        )
        isSharingToInstagram = false
        switch outcome {
        case .shared:
            break
        case .failed(.instagramNotInstalled):
            showInstagramUnavailableAlert = true
        case .failed:
            showInstagramOpenFailedAlert = true
        }
    }
}

/// 透明 PNG プレビュー用の市松。出力画像には入れない。
struct CheckerboardBackground: View {
    var cell: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let light = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(rect),
                        with: .color(light ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    )
                }
            }
        }
    }
}

private struct ShareSourceView: UIViewRepresentable {
    @Binding var view: UIView?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            self.view = view
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if view !== uiView {
                view = uiView
            }
        }
    }
}
