import Foundation
import Photos
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import BookBank

@MainActor
final class MockPhotoLibrarySaver: PhotoLibrarySaving {
    var status: PHAuthorizationStatus
    var requestResult: PHAuthorizationStatus
    var saveError: Error?
    var saveCallCount = 0
    var requestCallCount = 0
    var holdSave = false
    private var saveContinuation: CheckedContinuation<Void, Error>?

    init(
        status: PHAuthorizationStatus = .authorized,
        requestResult: PHAuthorizationStatus = .authorized
    ) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> PHAuthorizationStatus { status }

    func requestAuthorization() async -> PHAuthorizationStatus {
        requestCallCount += 1
        status = requestResult
        return requestResult
    }

    func saveImageData(_ data: Data) async throws {
        saveCallCount += 1
        if holdSave {
            try await withCheckedThrowingContinuation { continuation in
                saveContinuation = continuation
            }
        }
        if let saveError {
            throw saveError
        }
    }

    func finishHeldSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

@MainActor
struct MonthlyLogShareActionsTests {
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

    @Test func saveSucceedsWhenAuthorized() async {
        let saver = MockPhotoLibrarySaver(status: .authorized)
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: samplePNG)
        #expect(outcome == .saved)
        #expect(saver.saveCallCount == 1)
        #expect(saver.requestCallCount == 0)
    }

    @Test func saveRequestsAccessWhenUndeterminedThenSaves() async {
        let saver = MockPhotoLibrarySaver(status: .notDetermined, requestResult: .authorized)
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: samplePNG)
        #expect(outcome == .saved)
        #expect(saver.requestCallCount == 1)
    }

    @Test func saveDeniedDoesNotWrite() async {
        let saver = MockPhotoLibrarySaver(status: .denied)
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: samplePNG)
        #expect(outcome == .denied)
        #expect(saver.saveCallCount == 0)
    }

    @Test func saveRestrictedDoesNotWrite() async {
        let saver = MockPhotoLibrarySaver(status: .restricted)
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: samplePNG)
        #expect(outcome == .restricted)
        #expect(saver.saveCallCount == 0)
    }

    @Test func saveFailureIsReported() async {
        let saver = MockPhotoLibrarySaver(status: .authorized)
        saver.saveError = PhotoLibrarySaveError.failed
        let controller = MonthlyLogShareSaveController(saver: saver)
        let outcome = await controller.save(data: samplePNG)
        #expect(outcome == .failed)
    }

    @Test func ignoresRepeatedSaveWhileBusy() async {
        let saver = MockPhotoLibrarySaver(status: .authorized)
        saver.holdSave = true
        let controller = MonthlyLogShareSaveController(saver: saver)

        async let first = controller.save(data: samplePNG)
        try? await Task.sleep(for: .milliseconds(30))
        let second = await controller.save(data: samplePNG)
        saver.finishHeldSave()
        let firstOutcome = await first

        #expect(firstOutcome == .saved)
        #expect(second == .ignoredBecauseBusy)
        #expect(saver.saveCallCount == 1)
    }

    @Test func copyStoresPNGDataNotUIImage() {
        let board = UIPasteboard.withUniqueName()
        let data = samplePNG
        let asset = MonthlyLogShareExportAsset(data: data, format: .png)
        MonthlyLogShareExport.copyToPasteboard(asset, pasteboard: board)
        #expect(board.data(forPasteboardType: UTType.png.identifier) == data)
        #expect(board.data(forPasteboardType: UTType.jpeg.identifier) == nil)
        #expect(UIImage(data: data) != nil)
    }

    @Test func copyStoresJPEGDataWithJPEGType() {
        let board = UIPasteboard.withUniqueName()
        let data = sampleJPEG
        let asset = MonthlyLogShareExportAsset(data: data, format: .jpeg)
        MonthlyLogShareExport.copyToPasteboard(asset, pasteboard: board)
        #expect(board.data(forPasteboardType: UTType.jpeg.identifier) == data)
        #expect(board.data(forPasteboardType: UTType.png.identifier) == nil)
    }

    @Test func writesShareableTemporaryPNG() throws {
        let url = try MonthlyLogShareExport.writeTemporaryFile(
            MonthlyLogShareExportAsset(data: samplePNG, format: .png)
        )
        defer { MonthlyLogShareExport.removeTemporaryFile(url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
        let loaded = try Data(contentsOf: url)
        #expect(UIImage(data: loaded) != nil)
    }

    @Test func writesShareableTemporaryJPEG() throws {
        let url = try MonthlyLogShareExport.writeTemporaryFile(
            MonthlyLogShareExportAsset(data: sampleJPEG, format: .jpeg)
        )
        defer { MonthlyLogShareExport.removeTemporaryFile(url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "jpg")
        let loaded = try Data(contentsOf: url)
        #expect(UIImage(data: loaded) != nil)
    }

    private func allowingGate() -> MonthlyLogShareScreenshotGate {
        MonthlyLogShareScreenshotGate(
            isAppActive: true,
            isCalendarVisible: true,
            isCalendarInForeground: true,
            isSharePresented: false,
            isPreparing: false,
            isMonthlyMemoPresented: false,
            isDaySheetPresented: false,
            hasOtherCoveringModal: false
        )
    }

    @Test func screenshotGateRequiresEveryCondition() {
        let allowing = allowingGate()
        #expect(allowing.shouldPresent)
        #expect(allowing.shouldStartPreparation)
        #expect(allowing.canCommitPreparedSession)

        var inactive = allowing
        inactive.isAppActive = false
        #expect(!inactive.shouldPresent)

        var notCalendar = allowing
        notCalendar.isCalendarVisible = false
        #expect(!notCalendar.shouldPresent)

        var sharing = allowing
        sharing.isSharePresented = true
        #expect(!sharing.shouldPresent)

        var memo = allowing
        memo.isMonthlyMemoPresented = true
        #expect(!memo.shouldPresent)

        var daySheet = allowing
        daySheet.isDaySheetPresented = true
        #expect(!daySheet.shouldPresent)

        var other = allowing
        other.hasOtherCoveringModal = true
        #expect(!other.shouldPresent)
    }

    @Test func screenshotRequiresCalendarActuallyInForeground() {
        let allowing = allowingGate()
        #expect(allowing.isCalendarActuallyFront)
        #expect(MonthlyLogShareScreenshotRouting.shouldStartPreparation(gate: allowing))

        var pushedDetail = allowing
        pushedDetail.isCalendarVisible = true
        pushedDetail.isCalendarInForeground = false
        #expect(!pushedDetail.isCalendarActuallyFront)
        #expect(!MonthlyLogShareScreenshotRouting.shouldStartPreparation(gate: pushedDetail))
        #expect(!MonthlyLogShareScreenshotRouting.canCommitPreparedSession(gate: pushedDetail))
    }

    @Test func screenshotDeniedOnSearchOrOtherTab() {
        var searchOrOtherTab = allowingGate()
        searchOrOtherTab.isCalendarInForeground = false
        #expect(!MonthlyLogShareScreenshotRouting.shouldStartPreparation(gate: searchOrOtherTab))
    }

    @Test func commitRechecksForegroundAfterPreparation() {
        var preparing = allowingGate()
        preparing.isPreparing = true
        #expect(!preparing.shouldStartPreparation, "準備中の二重開始はしない")
        #expect(preparing.canCommitPreparedSession, "準備中でも前面なら提示できる")

        preparing.isCalendarInForeground = false
        #expect(!preparing.canCommitPreparedSession, "詳細へ離れたら遅れて出さない")
    }

    @Test func cancelClearsPreparingAndDropsLateResult() async {
        let preparation = MonthlyLogSharePreparation()
        let hold = AsyncHold()
        final class Box: @unchecked Sendable {
            var committed = false
        }
        let box = Box()

        preparation.start(
            shouldStart: true,
            prepare: {
                await hold.wait()
                try Task.checkCancellation()
                return Self.dummySession()
            },
            canCommit: { true },
            commit: { _ in box.committed = true }
        )
        #expect(preparation.isPreparing)

        preparation.cancel()
        #expect(!preparation.isPreparing)

        hold.resume()
        try? await Task.sleep(for: .milliseconds(40))
        #expect(!box.committed)
        #expect(!preparation.isPreparing)
    }

    @Test func screenshotNotificationHonorsGate() {
        let allowing = allowingGate()
        final class Observation: @unchecked Sendable {
            var value = false
        }
        let observed = Observation()
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { notification in
            observed.value = MonthlyLogShareScreenshotRouting.shouldPresent(
                notification: notification,
                gate: allowing
            )
        }
        defer { NotificationCenter.default.removeObserver(token) }

        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        #expect(observed.value)

        var blocked = allowing
        blocked.isCalendarVisible = false
        let blockedNotification = Notification(name: UIApplication.userDidTakeScreenshotNotification)
        #expect(
            MonthlyLogShareScreenshotRouting.shouldPresent(
                notification: blockedNotification,
                gate: blocked
            ) == false
        )
        #expect(
            MonthlyLogShareScreenshotRouting.shouldPresent(
                notification: Notification(name: UIApplication.didBecomeActiveNotification),
                gate: allowing
            ) == false
        )
    }

    @Test func visibleMonthPrefersLargestIntersectionThenCenter() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 200)
        let july = MonthlyLogShareVisibleMonth.Candidate(
            year: 2026,
            month: 7,
            frame: CGRect(x: 0, y: -80, width: 100, height: 100)
        )
        let august = MonthlyLogShareVisibleMonth.Candidate(
            year: 2026,
            month: 8,
            frame: CGRect(x: 0, y: 20, width: 100, height: 160)
        )
        let selected = MonthlyLogShareVisibleMonth.select(candidates: [july, august], viewport: viewport)
        #expect(selected == MonthlyLogShareVisibleMonth.YearMonth(year: 2026, month: 8))

        let left = MonthlyLogShareVisibleMonth.Candidate(
            year: 2026,
            month: 1,
            frame: CGRect(x: 0, y: 50, width: 50, height: 100)
        )
        let right = MonthlyLogShareVisibleMonth.Candidate(
            year: 2026,
            month: 2,
            frame: CGRect(x: 50, y: 80, width: 50, height: 100)
        )
        let tie = MonthlyLogShareVisibleMonth.select(
            candidates: [left, right],
            viewport: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
        #expect(tie == MonthlyLogShareVisibleMonth.YearMonth(year: 2026, month: 1))
    }

    private static func dummySession() -> MonthlyLogShareSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        let snapshot = MonthlyLogShareSnapshot(
            year: 2026,
            month: 8,
            occurrences: [],
            books: [],
            bookCount: 0,
            totalDisplayAmount: 0,
            displayCurrency: .jpy,
            localeIdentifier: "ja",
            firstWeekday: 1,
            timeZoneIdentifier: "Asia/Tokyo",
            layout: MonthlyCalendarLayout.make(year: 2026, month: 8, books: [], calendar: calendar)
        )
        return MonthlyLogShareSession(year: 2026, month: 8, snapshot: snapshot, covers: [:])
    }
}

@MainActor
final class AsyncHold {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
