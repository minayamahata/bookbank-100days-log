import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum PhotoLibrarySaveError: Error, Equatable {
    case denied
    case restricted
    case failed
    case alreadyInProgress
}

enum PhotoLibrarySaveOutcome: Equatable {
    case saved
    case ignoredBecauseBusy
    case denied
    case restricted
    case failed
}

@MainActor
protocol PhotoLibrarySaving {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    /// PNG / JPEG 共通。`PHAssetCreationRequest` は Data の形式を自動判別する。
    func saveImageData(_ data: Data) async throws
}

@MainActor
final class SystemPhotoLibrarySaver: PhotoLibrarySaving {
    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    func saveImageData(_ data: Data) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw PhotoLibrarySaveError.failed
        }
    }
}

@MainActor
final class MonthlyLogShareSaveController {
    private let saver: PhotoLibrarySaving
    private(set) var isSaving = false

    init(saver: PhotoLibrarySaving) {
        self.saver = saver
    }

    func save(data: Data) async -> PhotoLibrarySaveOutcome {
        guard !isSaving else { return .ignoredBecauseBusy }
        isSaving = true
        defer { isSaving = false }

        var status = saver.authorizationStatus()
        if status == .notDetermined {
            status = await saver.requestAuthorization()
        }

        switch status {
        case .authorized, .limited:
            do {
                try await saver.saveImageData(data)
                return .saved
            } catch {
                return .failed
            }
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        default:
            return .denied
        }
    }
}

enum MonthlyLogShareExport {
    /// PNG はアルファを保つため `UIImage` ではなく Data を、種別に合う UTType で格納する。
    static func copyToPasteboard(
        _ asset: MonthlyLogShareExportAsset,
        pasteboard: UIPasteboard = .general
    ) {
        pasteboard.setData(asset.data, forPasteboardType: asset.utType.identifier)
    }

    /// 共有シート用の一時ファイル。拡張子は PNG / JPEG に合わせる。
    static func writeTemporaryFile(_ asset: MonthlyLogShareExportAsset) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BookBank-monthly-log-\(UUID().uuidString).\(asset.fileExtension)"
            )
        try asset.data.write(to: url, options: .atomic)
        return url
    }

    static func removeTemporaryFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

enum MonthlyLogShareActivityPresenter {
    @MainActor
    static func present(url: URL, sourceView: UIView?) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            MonthlyLogShareExport.removeTemporaryFile(url)
        }

        guard let presenter = topViewController() else {
            MonthlyLogShareExport.removeTemporaryFile(url)
            return
        }

        if let popover = activity.popoverPresentationController {
            if let sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else if let view = presenter.view {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
        }

        presenter.present(activity, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController
        return topMost(from: root)
    }

    private static func topMost(from viewController: UIViewController?) -> UIViewController? {
        if let presented = viewController?.presentedViewController {
            return topMost(from: presented)
        }
        if let navigation = viewController as? UINavigationController {
            return topMost(from: navigation.visibleViewController)
        }
        if let tab = viewController as? UITabBarController {
            return topMost(from: tab.selectedViewController)
        }
        return viewController
    }
}
