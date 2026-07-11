import Foundation

/// 評価対象パラメータ（docs/n0-spike-plan.md 前提3）。
/// 初期値はノード設計書の (仮) 値。CLIフラグで上書きして反復評価する。
public struct SpikeParameters: Sendable {
    /// 1ノードあたりの保持エッジ数上限（設計書 5.2節）
    public var edgeLimitK: Int = 8
    /// 本ごとに保存するキーワード上限（設計書 3.2節）
    public var keywordLimitM: Int = 30
    /// 動的フィルタ: df/N がこの値を超える語は除外（設計書 3.2節）
    public var idfThreshold: Double = 0.25
    /// この冊数未満では動的フィルタをスキップ（設計書 3.2節の注意）
    public var idfMinimumBookCount: Int = 10
    /// エッジスコアの下限（未満は保存しない・設計書 5.2節）
    public var scoreFloor: Double = 0.15
    /// S-B: 最長共通接頭辞が短い方のタイトルに占める最低比率（設計書 2.2節）
    public var prefixRatio: Double = 0.6
    /// S-B: 接頭辞の最低文字数（CJK。英語は単語数条件を使う）
    public var prefixMinChars: Int = 4
    /// S-B: 英語の接頭辞の最低単語数
    public var prefixMinWordsEnglish: Int = 2
    /// 重み（設計書 5.2節のエッジスコア定義）
    public var weightSeries: Double = 1.0
    public var weightAuthor: Double = 0.6
    public var weightKeyword: Double = 0.15
    public var keywordContributionLimit: Int = 3
    public var weightMemoMonth: Double = 0.05

    public init() {}
}
