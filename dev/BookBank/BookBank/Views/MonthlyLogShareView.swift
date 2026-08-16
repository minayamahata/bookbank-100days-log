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
    let session: MonthlyLogShareSession
    var saver: PhotoLibrarySaving = SystemPhotoLibrarySaver()
    let onClose: () -> Void

    @State private var page = 0
    @State private var rendered: [Int: Data] = [:]
    @State private var isRendering = true
    @State private var actionFeedback: ActionFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var showDeniedAlert = false
    @State private var showRestrictedAlert = false
    @State private var showFailedAlert = false
    @State private var isSaving = false
    @State private var shareSourceView: UIView?

    private var templates: [MonthlyLogShareTemplate] { MonthlyLogShareTemplate.allCases }

    var body: some View {
        VStack(spacing: 0) {
            header
            carousel
                .overlay(alignment: .bottom) {
                    if let actionFeedback {
                        successToast(actionFeedback)
                            .padding(.bottom, 22)
                            .transition(successToastTransition)
                            .zIndex(1)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: actionFeedback)
            pageDots
                .padding(.top, 8)
            recommendedRow
                .padding(.top, 20)
            actionRow
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Color.black)
        .task {
            await renderAll()
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
                .font(.app(.headline))
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var carousel: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let desiredPeek: CGFloat = 28
            let displayScale: CGFloat = 0.85
            let maxCardWidth = max(1, geometry.size.width - 2 * (desiredPeek + spacing))
            let maxCardHeight = max(1, geometry.size.height - 8)
            let fitted = fittedPreviewSize(
                in: CGSize(width: maxCardWidth, height: maxCardHeight)
            )
            let actualCardSize = CGSize(
                width: fitted.width * displayScale,
                height: fitted.height * displayScale
            )
            let sideInset = max(0, (geometry.size.width - actualCardSize.width) / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                        previewPage(
                            index: index,
                            template: template,
                            cardSize: actualCardSize
                        )
                        .frame(
                            width: actualCardSize.width,
                            height: geometry.size.height,
                            alignment: .bottom
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewPage(
        index: Int,
        template: MonthlyLogShareTemplate,
        cardSize: CGSize
    ) -> some View {
        ZStack {
            CheckerboardBackground()
            if let data = rendered[index], let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MonthlyLogShareCanvas(
                    snapshot: session.snapshot,
                    covers: session.covers,
                    template: template
                )
                .frame(
                    width: MonthlyLogShareRenderer.logicalSize.width,
                    height: MonthlyLogShareRenderer.logicalSize.height
                )
                .scaleEffect(cardSize.width / MonthlyLogShareRenderer.logicalSize.width)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fittedPreviewSize(in bounds: CGSize) -> CGSize {
        let aspect = MonthlyLogShareRenderer.logicalSize.width / MonthlyLogShareRenderer.logicalSize.height
        let height = min(bounds.height, bounds.width / aspect)
        let width = height * aspect
        return CGSize(width: width, height: height)
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

    private var recommendedRow: some View {
        VStack(spacing: 4) {
            Text("monthly_log_share.recommended")
                .font(.app(.caption))
                .foregroundStyle(.white.opacity(0.55))
            Text("monthly_log_share.recommended_destination")
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            actionButton(assetName: "icn_copy", title: "common.copy", enabled: currentPNG != nil) {
                copyCurrent()
            }
            actionButton(
                assetName: "icn_download",
                title: "common.save",
                enabled: currentPNG != nil && !isSaving
            ) {
                Task { await saveCurrent() }
            }
            actionButton(assetName: "icn_more", title: "monthly_log_share.more", enabled: currentPNG != nil) {
                shareCurrent()
            }
            .background {
                ShareSourceView(view: $shareSourceView)
            }
        }
    }

    private func actionButton(
        assetName: String,
        title: LocalizedStringKey,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                Text(title)
                    .font(.app(.caption))
            }
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var currentPNG: Data? {
        rendered[page]
    }

    @MainActor
    private func renderAll() async {
        isRendering = true
        var next: [Int: Data] = [:]
        for template in templates {
            if let data = MonthlyLogShareRenderer.pngData(
                snapshot: session.snapshot,
                covers: session.covers,
                template: template
            ) {
                next[template.rawValue] = data
            }
        }
        rendered = next
        isRendering = false
    }

    private func copyCurrent() {
        guard let data = currentPNG else { return }
        presentFeedback(.copied)
        Task { @MainActor in
            MonthlyLogShareExport.copyPNGToPasteboard(data)
        }
    }

    private func saveCurrent() async {
        guard let data = currentPNG, !isSaving else { return }
        isSaving = true
        let alreadyAllowed = Self.canSaveWithoutPrompt(saver.authorizationStatus())
        if alreadyAllowed {
            presentFeedback(.saved)
        }
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(png: data)
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
        guard let data = currentPNG else { return }
        do {
            let url = try MonthlyLogShareExport.writeTemporaryPNG(data)
            MonthlyLogShareActivityPresenter.present(url: url, sourceView: shareSourceView)
        } catch {
            showFailedAlert = true
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
