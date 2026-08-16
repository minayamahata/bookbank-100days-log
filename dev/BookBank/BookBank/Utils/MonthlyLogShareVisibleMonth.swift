import Foundation
import CoreGraphics
import SwiftUI
import UIKit

/// 画面上でいちばん大きく見えている月を選ぶ（スクリーンショット検知用）。
enum MonthlyLogShareVisibleMonth {
    struct Candidate: Equatable, Sendable {
        let year: Int
        let month: Int
        let frame: CGRect
    }

    struct YearMonth: Equatable, Sendable {
        let year: Int
        let month: Int
    }

    /// 交差面積が最大の月。同率なら画面中央へ近い月を優先する。
    static func select(candidates: [Candidate], viewport: CGRect) -> YearMonth? {
        guard !candidates.isEmpty, !viewport.isNull, viewport.width > 0, viewport.height > 0 else {
            return nil
        }

        let scored: [(Candidate, CGFloat, CGFloat)] = candidates.map { candidate in
            let intersection = candidate.frame.intersection(viewport)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            let dx = candidate.frame.midX - viewport.midX
            let dy = candidate.frame.midY - viewport.midY
            let distance = dx * dx + dy * dy
            return (candidate, area, distance)
        }

        let visible = scored.filter { $0.1 > 0 }
        let pool = visible.isEmpty ? scored : visible
        guard let best = pool.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 > rhs.2
        }) else {
            return nil
        }
        return YearMonth(year: best.0.year, month: best.0.month)
    }

    static func currentMonth(calendar: Calendar, now: Date = Date()) -> YearMonth {
        let components = calendar.dateComponents([.year, .month], from: now)
        return YearMonth(year: components.year ?? 1970, month: components.month ?? 1)
    }
}

/// スクリーンショット通知から共有画面を開いてよいか。
///
/// `isCalendarVisible` は `BookshelfView.showCalendarView`。
/// `isCalendarInForeground` は `BookshelfCalendarView` が実際に前面か（push先では false）。
struct MonthlyLogShareScreenshotGate: Equatable, Sendable {
    var isAppActive: Bool
    var isCalendarVisible: Bool
    var isCalendarInForeground: Bool
    var isSharePresented: Bool
    var isPreparing: Bool
    var isMonthlyMemoPresented: Bool
    var isDaySheetPresented: Bool
    var hasOtherCoveringModal: Bool

    /// カレンダーモードかつ、カレンダーViewが実際に前面
    var isCalendarActuallyFront: Bool {
        isCalendarVisible && isCalendarInForeground
    }

    var isBlockedByCoveringUI: Bool {
        isSharePresented
            || isMonthlyMemoPresented
            || isDaySheetPresented
            || hasOtherCoveringModal
    }

    /// 通知時点で準備を始めてよいか
    var shouldStartPreparation: Bool {
        isAppActive
            && isCalendarActuallyFront
            && !isPreparing
            && !isBlockedByCoveringUI
    }

    /// 表紙準備完了後、セッションを載せてよいか（準備中フラグは許可）
    var canCommitPreparedSession: Bool {
        isAppActive
            && isCalendarActuallyFront
            && !isSharePresented
            && !isMonthlyMemoPresented
            && !isDaySheetPresented
            && !hasOtherCoveringModal
    }

    var shouldPresent: Bool { shouldStartPreparation }
}

struct MonthlyLogShareMonthFrameKey: PreferenceKey {
    static var defaultValue: [MonthlyLogShareVisibleMonth.Candidate] = []

    static func reduce(
        value: inout [MonthlyLogShareVisibleMonth.Candidate],
        nextValue: () -> [MonthlyLogShareVisibleMonth.Candidate]
    ) {
        value.append(contentsOf: nextValue())
    }
}

enum MonthlyLogShareScreenshotRouting {
    static func shouldPresent(
        notification: Notification,
        gate: MonthlyLogShareScreenshotGate
    ) -> Bool {
        guard notification.name == UIApplication.userDidTakeScreenshotNotification else {
            return false
        }
        return gate.shouldStartPreparation
    }

    static func shouldStartPreparation(gate: MonthlyLogShareScreenshotGate) -> Bool {
        gate.shouldStartPreparation
    }

    static func canCommitPreparedSession(gate: MonthlyLogShareScreenshotGate) -> Bool {
        gate.canCommitPreparedSession
    }
}

/// 表紙準備 Task の開始・キャンセル。遅れて届いた結果では共有画面を出さない。
@Observable
@MainActor
final class MonthlyLogSharePreparation {
    private(set) var isPreparing = false
    private var task: Task<Void, Never>?
    private var generation = 0

    func start(
        shouldStart: @autoclosure () -> Bool,
        prepare: @escaping () async throws -> MonthlyLogShareSession?,
        canCommit: @escaping () -> Bool,
        commit: @escaping (MonthlyLogShareSession) -> Void
    ) {
        guard shouldStart() else { return }
        cancel()
        generation += 1
        let current = generation
        isPreparing = true
        task = Task { [weak self] in
            defer {
                if let self, current == self.generation {
                    self.isPreparing = false
                    self.task = nil
                }
            }
            do {
                let session = try await prepare()
                guard !Task.isCancelled else { return }
                guard let self, current == self.generation else { return }
                guard canCommit(), let session else { return }
                commit(session)
            } catch {
                return
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isPreparing = false
    }
}
