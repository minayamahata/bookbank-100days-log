//
//  WhatsNewPolicy.swift
//  BookBank
//
//  新機能のお知らせの自動表示方針と保存（docs/whats-new-message-design.md 5章）。
//  方針は純粋関数、保存は UserDefaults 注入可の小さな型で持ち、Viewから分離する。
//

import Foundation

/// 自動表示の判定（純粋関数）。
enum WhatsNewAutoShowPolicy {
    /// 自動表示の上限回数
    static let maxAutoShowCount = 3

    /// 実機チェック用の一時スイッチ（2026-08-20 オーナー指示）。
    /// true の間は確認済み・回数上限を無視して毎起動表示する（1起動1回は維持・回数は加算しない）。
    /// 実機チェック完了により false へ復帰済み（2026-08-20。リリース版は必ず false のまま）
    static let temporarilyAlwaysAutoShow = false

    /// - Parameters:
    ///   - hasCompletedOnboarding: オンボーディング完了済みか（未完了中は表示しない）
    ///   - isConfirmed: 「はじめる」で確認済みか
    ///   - autoShowCount: これまでに自動表示した回数
    ///   - hasAutoShownThisLaunch: 同じ起動内で既に自動表示したか（1起動につき1回）
    ///   - alwaysShowOverride: 一時スイッチ。true なら確認済み・回数上限を無視する
    static func shouldAutoShow(
        hasCompletedOnboarding: Bool,
        isConfirmed: Bool,
        autoShowCount: Int,
        hasAutoShownThisLaunch: Bool,
        alwaysShowOverride: Bool = temporarilyAlwaysAutoShow
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard !hasAutoShownThisLaunch else { return false }
        if alwaysShowOverride { return true }
        guard !isConfirmed else { return false }
        return autoShowCount < maxAutoShowCount
    }
}

/// お知らせの保存状態。キーはバージョン単位で、将来の別バージョンを追加できる。
struct WhatsNewStore {
    let version: String
    let defaults: UserDefaults

    init(version: String = WhatsNewMessage.version, defaults: UserDefaults = .standard) {
        self.version = version
        self.defaults = defaults
    }

    static func autoShowCountKey(version: String) -> String {
        "whatsNew.autoShowCount.\(version)"
    }

    static func confirmedKey(version: String) -> String {
        "whatsNew.confirmed.\(version)"
    }

    /// 自動表示した回数
    var autoShowCount: Int {
        defaults.integer(forKey: Self.autoShowCountKey(version: version))
    }

    /// 「はじめる」で確認済みか
    var isConfirmed: Bool {
        defaults.bool(forKey: Self.confirmedKey(version: version))
    }

    /// 自動表示が実際に始まった時点で呼ぶ（表示中に終了してもその回は数える）。
    /// 同一起動内の再加算防止は呼び出し側の起動内状態が担う。
    func recordAutoShowStarted() {
        defaults.set(autoShowCount + 1, forKey: Self.autoShowCountKey(version: version))
    }

    /// 「はじめる」で確認済みにする。自動表示回数には影響しない。
    /// 「×」で閉じたときは呼ばない（確認済みにしない）。
    func markConfirmed() {
        defaults.set(true, forKey: Self.confirmedKey(version: version))
    }
}

/// 同一起動内の状態。二重表示と回数の再加算を防ぐ。
/// バックグラウンド復帰ではプロセスが生きているため値が残り、再表示しない。
struct WhatsNewLaunchSession {
    private(set) var hasAutoShown = false

    mutating func markAutoShown() {
        hasAutoShown = true
    }
}

/// アプリ本体が使う起動内状態の置き場（`SplashPresentationState` とは別に持つ）。
enum WhatsNewSessionState {
    static var launchSession = WhatsNewLaunchSession()
}
