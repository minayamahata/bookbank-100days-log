import Foundation
import UIKit

/// Instagram Stories 直接共有の判定・URL・ペーストボード payload。
/// `UIApplication` / `UIPasteboard` へは依存せず、起動はプロトコル経由。
enum MonthlyLogShareInstagramStories {
    static let urlScheme = "instagram-stories"
    static let shareHost = "share"
    static let sourceApplicationQueryName = "source_application"
    static let stickerImagePasteboardKey = "com.instagram.sharedSticker.stickerImage"
    static let facebookAppIDInfoPlistKey = "FacebookAppID"
    static let pasteboardExpirationInterval: TimeInterval = 60 * 5

    enum Failure: Equatable, Sendable {
        case unsupportedTemplate
        case missingAsset
        case missingAppID
        case instagramNotInstalled
        case openFailed
    }

    enum Outcome: Equatable, Sendable {
        case shared
        case failed(Failure)
    }

    struct PasteboardPayload: Equatable, Sendable {
        let stickerImageData: Data
        let pasteboardType: String
        let expirationInterval: TimeInterval
    }

    /// Info.plist の `FacebookAppID`。空・未設定・空白のみは nil。架空値は作らない。
    static func appID(fromInfoDictionary info: [String: Any]?) -> String? {
        guard let raw = info?[facebookAppIDInfoPlistKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func appID(from bundle: Bundle) -> String? {
        appID(fromInfoDictionary: bundle.infoDictionary)
    }

    static func resolvedAppID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func shareURL(appID: String) -> URL? {
        guard let resolved = resolvedAppID(appID) else { return nil }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = shareHost
        components.queryItems = [
            URLQueryItem(name: sourceApplicationQueryName, value: resolved)
        ]
        return components.url
    }

    static func pasteboardPayload(from asset: MonthlyLogShareExportAsset) -> PasteboardPayload {
        PasteboardPayload(
            stickerImageData: asset.data,
            pasteboardType: stickerImagePasteboardKey,
            expirationInterval: pasteboardExpirationInterval
        )
    }

    static func pasteboardItems(from payload: PasteboardPayload) -> [[String: Any]] {
        [[payload.pasteboardType: payload.stickerImageData]]
    }
}

@MainActor
protocol InstagramStoriesURLOpening {
    func canOpenURL(_ url: URL) -> Bool
    func open(_ url: URL) async -> Bool
}

@MainActor
protocol InstagramStoriesPasteboardWriting {
    func setStoriesSticker(data: Data, expirationDate: Date)
}

@MainActor
struct SystemInstagramStoriesURLOpener: InstagramStoriesURLOpening {
    func canOpenURL(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}

@MainActor
struct SystemInstagramStoriesPasteboard: InstagramStoriesPasteboardWriting {
    func setStoriesSticker(data: Data, expirationDate: Date) {
        UIPasteboard.general.setItems(
            [[MonthlyLogShareInstagramStories.stickerImagePasteboardKey: data]],
            options: [.expirationDate: expirationDate]
        )
    }
}

/// Instagram Stories 起動のオーケストレーション。コピー・保存・共有シートは呼ばない。
@MainActor
enum MonthlyLogShareInstagramStoriesShare {
    static func perform(
        asset: MonthlyLogShareExportAsset?,
        template: MonthlyLogShareTemplate,
        appID: String?,
        now: Date = Date(),
        opener: InstagramStoriesURLOpening,
        pasteboard: InstagramStoriesPasteboardWriting
    ) async -> MonthlyLogShareInstagramStories.Outcome {
        guard template.supportsInstagramStoriesShare else {
            return .failed(.unsupportedTemplate)
        }
        guard let asset else {
            return .failed(.missingAsset)
        }
        guard let resolvedAppID = MonthlyLogShareInstagramStories.resolvedAppID(appID) else {
            return .failed(.missingAppID)
        }
        guard let url = MonthlyLogShareInstagramStories.shareURL(appID: resolvedAppID) else {
            return .failed(.openFailed)
        }
        guard opener.canOpenURL(url) else {
            return .failed(.instagramNotInstalled)
        }

        let payload = MonthlyLogShareInstagramStories.pasteboardPayload(from: asset)
        pasteboard.setStoriesSticker(
            data: payload.stickerImageData,
            expirationDate: now.addingTimeInterval(payload.expirationInterval)
        )

        let opened = await opener.open(url)
        return opened ? .shared : .failed(.openFailed)
    }
}
