import Foundation
import Testing
@testable import BookBank

/// 新機能のお知らせ 自動表示方針と保存のテスト（docs/whats-new-message-design.md 5章・9章）
/// 通常規則のテストは一時スイッチの値に依存しないよう `alwaysShowOverride` を明示して呼ぶ。
@MainActor
struct WhatsNewPolicyTests {
    /// 本番の UserDefaults.standard を汚さない専用スイート
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "WhatsNewPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test func doesNotAutoShowBeforeOnboardingCompletes() {
        #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: false,
            isConfirmed: false,
            autoShowCount: 0,
            hasAutoShownThisLaunch: false,
            alwaysShowOverride: false
        ))
    }

    @Test func autoShowsWhileCountIsBelowThree() {
        for count in 0...2 {
            #expect(WhatsNewAutoShowPolicy.shouldAutoShow(
                hasCompletedOnboarding: true,
                isConfirmed: false,
                autoShowCount: count,
                hasAutoShownThisLaunch: false,
                alwaysShowOverride: false
            ), "回数\(count)では自動表示対象")
        }
    }

    @Test func doesNotAutoShowAfterThreeTimes() {
        for count in [3, 4, 100] {
            #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
                hasCompletedOnboarding: true,
                isConfirmed: false,
                autoShowCount: count,
                hasAutoShownThisLaunch: false,
                alwaysShowOverride: false
            ), "回数\(count)では自動表示しない")
        }
    }

    @Test func doesNotAutoShowOnceConfirmedEvenBelowThree() {
        #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: true,
            autoShowCount: 1,
            hasAutoShownThisLaunch: false,
            alwaysShowOverride: false
        ))
    }

    @Test func doesNotAutoShowTwiceInTheSameLaunch() {
        var session = WhatsNewLaunchSession()
        #expect(WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: false,
            autoShowCount: 0,
            hasAutoShownThisLaunch: session.hasAutoShown,
            alwaysShowOverride: false
        ))
        session.markAutoShown()
        #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: false,
            autoShowCount: 1,
            hasAutoShownThisLaunch: session.hasAutoShown,
            alwaysShowOverride: false
        ), "同じ起動中は二重表示しない")
    }

    /// 実機チェック用の一時スイッチ: 確認済み・回数上限を無視するが、
    /// オンボーディング未完了と1起動1回のガードは維持する
    @Test func temporaryOverrideIgnoresConfirmationAndCountOnly() {
        #expect(WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: true,
            autoShowCount: 100,
            hasAutoShownThisLaunch: false,
            alwaysShowOverride: true
        ), "スイッチ中は確認済み・3回超でも表示する")
        #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: false,
            isConfirmed: false,
            autoShowCount: 0,
            hasAutoShownThisLaunch: false,
            alwaysShowOverride: true
        ), "スイッチ中もオンボーディング未完了では表示しない")
        #expect(!WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: false,
            autoShowCount: 0,
            hasAutoShownThisLaunch: true,
            alwaysShowOverride: true
        ), "スイッチ中も1起動1回は維持する")
    }

    @Test func otherVersionConfirmationDoesNotBlockCurrentVersion() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldStore = WhatsNewStore(version: "1.6.0", defaults: defaults)
        oldStore.markConfirmed()

        let currentStore = WhatsNewStore(version: "1.7.0", defaults: defaults)
        #expect(!currentStore.isConfirmed, "別バージョンの確認済みは1.7.0へ波及しない")
        #expect(WhatsNewAutoShowPolicy.shouldAutoShow(
            hasCompletedOnboarding: true,
            isConfirmed: currentStore.isConfirmed,
            autoShowCount: currentStore.autoShowCount,
            hasAutoShownThisLaunch: false,
            alwaysShowOverride: false
        ))
    }

    @Test func recordAutoShowStartedIncrementsCountWithoutConfirming() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WhatsNewStore(version: "1.7.0", defaults: defaults)
        #expect(store.autoShowCount == 0)

        // 表示開始で+1（「×」で閉じても確認済みにはならない）
        store.recordAutoShowStarted()
        #expect(store.autoShowCount == 1)
        #expect(!store.isConfirmed, "「×」では確認済みにならない")

        store.recordAutoShowStarted()
        store.recordAutoShowStarted()
        #expect(store.autoShowCount == 3)
    }

    @Test func markConfirmedConfirmsWithoutChangingCount() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WhatsNewStore(version: "1.7.0", defaults: defaults)
        store.recordAutoShowStarted()

        // 「はじめる」= 確認済み。設定からの手動表示はこの経路だけを使い、回数へ加算しない
        store.markConfirmed()
        #expect(store.isConfirmed, "「はじめる」で確認済みになる")
        #expect(store.autoShowCount == 1, "手動表示・確認は自動表示回数へ加算しない")
    }

    @Test func keysAreVersionScoped() {
        #expect(WhatsNewStore.autoShowCountKey(version: "1.7.0") == "whatsNew.autoShowCount.1.7.0")
        #expect(WhatsNewStore.confirmedKey(version: "1.7.0") == "whatsNew.confirmed.1.7.0")
        #expect(WhatsNewMessage.version == "1.7.0")
        #expect(WhatsNewAutoShowPolicy.maxAutoShowCount == 3)
    }
}
