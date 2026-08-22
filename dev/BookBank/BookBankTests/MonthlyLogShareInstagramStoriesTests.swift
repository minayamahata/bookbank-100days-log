import Foundation
import Photos
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import BookBank

@MainActor
final class MockInstagramStoriesURLOpener: InstagramStoriesURLOpening {
    var canOpen = true
    var openResult = true
    var canOpenCallCount = 0
    var openCallCount = 0
    var lastOpenedURL: URL?

    func canOpenURL(_ url: URL) -> Bool {
        canOpenCallCount += 1
        lastOpenedURL = url
        return canOpen
    }

    func open(_ url: URL) async -> Bool {
        openCallCount += 1
        lastOpenedURL = url
        return openResult
    }
}

@MainActor
final class MockInstagramStoriesPasteboard: InstagramStoriesPasteboardWriting {
    var setCallCount = 0
    var lastData: Data?
    var lastExpirationDate: Date?

    func setStoriesSticker(data: Data, expirationDate: Date) {
        setCallCount += 1
        lastData = data
        lastExpirationDate = expirationDate
    }
}

@MainActor
struct MonthlyLogShareInstagramStoriesTests {
    private var samplePNG: Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData() ?? Data()
    }

    private var sampleJPEG: Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.jpegData(compressionQuality: 0.95) ?? Data()
    }

    @Test func exactlyThreeTemplatesSupportInstagramStories() {
        let eligible = MonthlyLogShareTemplate.allCases.filter(\.supportsInstagramStoriesShare)
        #expect(eligible.count == 3)
        #expect(
            Set(eligible) == Set<MonthlyLogShareTemplate>([
                .circledCalendar, .minimalSummary, .monthInBooks
            ])
        )
    }

    @Test func circledCalendarSupportsInstagramStories() {
        #expect(MonthlyLogShareTemplate.circledCalendar.supportsInstagramStoriesShare)
    }

    @Test func minimalSummarySupportsInstagramStories() {
        #expect(MonthlyLogShareTemplate.minimalSummary.supportsInstagramStoriesShare)
    }

    @Test func monthInBooksSupportsInstagramStories() {
        #expect(MonthlyLogShareTemplate.monthInBooks.supportsInstagramStoriesShare)
    }

    @Test func calendarSummaryDoesNotSupportInstagramStories() {
        #expect(!MonthlyLogShareTemplate.calendarSummary.supportsInstagramStoriesShare)
    }

    @Test func largeMonthDoesNotSupportInstagramStories() {
        #expect(!MonthlyLogShareTemplate.largeMonth.supportsInstagramStoriesShare)
    }

    @Test func verticalMonthDoesNotSupportInstagramStories() {
        #expect(!MonthlyLogShareTemplate.verticalMonth.supportsInstagramStoriesShare)
    }

    @Test func eligibilityDoesNotDependOnDisplayOrder() {
        // 表示順を入れ替えても、index ではなくテンプレート自身の属性で決まる
        let reordered: [MonthlyLogShareTemplate] = [
            .monthInBooks, .calendarSummary, .circledCalendar,
            .largeMonth, .minimalSummary, .verticalMonth
        ]
        #expect(reordered[0].supportsInstagramStoriesShare)
        #expect(!reordered[1].supportsInstagramStoriesShare)
        #expect(reordered[2].supportsInstagramStoriesShare)
        #expect(!reordered[3].supportsInstagramStoriesShare)
        #expect(reordered[4].supportsInstagramStoriesShare)
        #expect(!reordered[5].supportsInstagramStoriesShare)

        let eligible = reordered.filter(\.supportsInstagramStoriesShare)
        #expect(eligible == [.monthInBooks, .circledCalendar, .minimalSummary])
    }

    @Test func buildsOfficialStoriesURL() {
        let url = MonthlyLogShareInstagramStories.shareURL(appID: "123456789")
        #expect(url?.scheme == MonthlyLogShareInstagramStories.urlScheme)
        #expect(url?.host == MonthlyLogShareInstagramStories.shareHost)
        #expect(
            url?.absoluteString
                == "instagram-stories://share?source_application=123456789"
        )
    }

    @Test func missingAppIDIsHandledSafely() {
        #expect(MonthlyLogShareInstagramStories.shareURL(appID: "") == nil)
        #expect(MonthlyLogShareInstagramStories.shareURL(appID: "   ") == nil)
        #expect(MonthlyLogShareInstagramStories.appID(fromInfoDictionary: nil) == nil)
        #expect(MonthlyLogShareInstagramStories.appID(fromInfoDictionary: [:]) == nil)
        #expect(MonthlyLogShareInstagramStories.appID(fromInfoDictionary: ["FacebookAppID": ""]) == nil)
        #expect(MonthlyLogShareInstagramStories.appID(fromInfoDictionary: ["FacebookAppID": "  "]) == nil)
        #expect(MonthlyLogShareInstagramStories.appID(fromInfoDictionary: ["FacebookAppID": "987"]) == "987")
        #expect(MonthlyLogShareInstagramStories.resolvedAppID(nil) == nil)
    }

    @Test func missingAppIDDoesNotOpenOrWritePasteboard() async {
        let opener = MockInstagramStoriesURLOpener()
        let pasteboard = MockInstagramStoriesPasteboard()
        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: MonthlyLogShareExportAsset(data: samplePNG, format: .png),
            template: .circledCalendar,
            appID: nil,
            opener: opener,
            pasteboard: pasteboard
        )
        #expect(outcome == .failed(.missingAppID))
        #expect(opener.canOpenCallCount == 0)
        #expect(opener.openCallCount == 0)
        #expect(pasteboard.setCallCount == 0)
    }

    @Test func instagramNotInstalledIsHandledSafely() async {
        let opener = MockInstagramStoriesURLOpener()
        opener.canOpen = false
        let pasteboard = MockInstagramStoriesPasteboard()
        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: MonthlyLogShareExportAsset(data: samplePNG, format: .png),
            template: .minimalSummary,
            appID: "123456789",
            opener: opener,
            pasteboard: pasteboard
        )
        #expect(outcome == .failed(.instagramNotInstalled))
        #expect(opener.openCallCount == 0)
        #expect(pasteboard.setCallCount == 0)
    }

    @Test func pasteboardPayloadUsesSelectedAssetData() {
        let png = samplePNG
        let jpeg = sampleJPEG
        let pngPayload = MonthlyLogShareInstagramStories.pasteboardPayload(
            from: MonthlyLogShareExportAsset(data: png, format: .png)
        )
        let jpegPayload = MonthlyLogShareInstagramStories.pasteboardPayload(
            from: MonthlyLogShareExportAsset(data: jpeg, format: .jpeg)
        )
        #expect(pngPayload.stickerImageData == png)
        #expect(jpegPayload.stickerImageData == jpeg)
        #expect(pngPayload.pasteboardType == "com.instagram.sharedSticker.stickerImage")
        #expect(jpegPayload.pasteboardType == "com.instagram.sharedSticker.stickerImage")
        #expect(pngPayload.expirationInterval == 60 * 5)
    }

    @Test func pasteboardAcceptsPNGAndJPEG() {
        let png = samplePNG
        let jpeg = sampleJPEG
        let pngBoard = UIPasteboard.withUniqueName()
        let jpegBoard = UIPasteboard.withUniqueName()
        let pngPayload = MonthlyLogShareInstagramStories.pasteboardPayload(
            from: MonthlyLogShareExportAsset(data: png, format: .png)
        )
        let jpegPayload = MonthlyLogShareInstagramStories.pasteboardPayload(
            from: MonthlyLogShareExportAsset(data: jpeg, format: .jpeg)
        )
        pngBoard.setItems(
            MonthlyLogShareInstagramStories.pasteboardItems(from: pngPayload),
            options: [:]
        )
        jpegBoard.setItems(
            MonthlyLogShareInstagramStories.pasteboardItems(from: jpegPayload),
            options: [:]
        )
        #expect(
            pngBoard.data(forPasteboardType: MonthlyLogShareInstagramStories.stickerImagePasteboardKey)
                == png
        )
        #expect(
            jpegBoard.data(forPasteboardType: MonthlyLogShareInstagramStories.stickerImagePasteboardKey)
                == jpeg
        )
    }

    @Test func shareWritesSelectedAssetAndOpensStoriesURL() async {
        let jpeg = sampleJPEG
        let opener = MockInstagramStoriesURLOpener()
        let pasteboard = MockInstagramStoriesPasteboard()
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: MonthlyLogShareExportAsset(data: jpeg, format: .jpeg),
            template: .monthInBooks,
            appID: "123456789",
            now: now,
            opener: opener,
            pasteboard: pasteboard
        )
        #expect(outcome == .shared)
        #expect(pasteboard.setCallCount == 1)
        #expect(pasteboard.lastData == jpeg)
        #expect(pasteboard.lastExpirationDate == now.addingTimeInterval(60 * 5))
        #expect(opener.openCallCount == 1)
        #expect(opener.lastOpenedURL?.absoluteString == "instagram-stories://share?source_application=123456789")
    }

    @Test func instagramShareHasNoCopySaveOrShareSheetSideEffects() async {
        let copyBoard = UIPasteboard.withUniqueName()
        let copied = samplePNG
        MonthlyLogShareExport.copyToPasteboard(
            MonthlyLogShareExportAsset(data: copied, format: .png),
            pasteboard: copyBoard
        )
        let saver = MockPhotoLibrarySaver(status: .authorized)
        let opener = MockInstagramStoriesURLOpener()
        let storiesPasteboard = MockInstagramStoriesPasteboard()
        let storiesAsset = MonthlyLogShareExportAsset(data: sampleJPEG, format: .jpeg)

        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: storiesAsset,
            template: .circledCalendar,
            appID: "123456789",
            opener: opener,
            pasteboard: storiesPasteboard
        )

        #expect(outcome == .shared)
        #expect(copyBoard.data(forPasteboardType: UTType.png.identifier) == copied)
        #expect(copyBoard.data(forPasteboardType: UTType.jpeg.identifier) == nil)
        #expect(saver.saveCallCount == 0)
        #expect(saver.requestCallCount == 0)
        #expect(storiesPasteboard.lastData == storiesAsset.data)
        #expect(storiesPasteboard.lastData != copied)
    }

    @Test func unsupportedTemplateDoesNotShare() async {
        let opener = MockInstagramStoriesURLOpener()
        let pasteboard = MockInstagramStoriesPasteboard()
        for template in [MonthlyLogShareTemplate.calendarSummary, .largeMonth, .verticalMonth] {
            let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
                asset: MonthlyLogShareExportAsset(data: samplePNG, format: .png),
                template: template,
                appID: "123456789",
                opener: opener,
                pasteboard: pasteboard
            )
            #expect(outcome == .failed(.unsupportedTemplate))
        }
        #expect(opener.canOpenCallCount == 0)
        #expect(opener.openCallCount == 0)
        #expect(pasteboard.setCallCount == 0)
    }

    @Test func missingAssetDoesNotShare() async {
        let opener = MockInstagramStoriesURLOpener()
        let pasteboard = MockInstagramStoriesPasteboard()
        let outcome = await MonthlyLogShareInstagramStoriesShare.perform(
            asset: nil,
            template: .circledCalendar,
            appID: "123456789",
            opener: opener,
            pasteboard: pasteboard
        )
        #expect(outcome == .failed(.missingAsset))
        #expect(pasteboard.setCallCount == 0)
        #expect(opener.openCallCount == 0)
    }
}
