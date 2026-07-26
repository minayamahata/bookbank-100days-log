import Foundation

/// 楽観更新（先に画面へ反映し、あとから永続化する操作）の失敗時ロールバック規約。
///
/// 設計メモ 4.5節: リポジトリの書き込みが失敗したら、永続化されなかった値を画面に残さない。
/// ただし**無条件に書き戻すと、書き戻しの間に届いた新しい値を踏み潰す**。
/// 失敗の応答を待つ間に `observeBooks()` のyieldや別操作が同じ `@State` を更新しうるため、
/// 「現在値がまだ自分の楽観値のままか」を確認してから戻す（鮮度ガード）。
///
/// - Note: Task の直列化・キャンセルは行わない（範囲外・2026-07-26 オーナー判断）。
///   鮮度ガードは「自分より新しい値を壊さない」ことだけを保証する。
enum OptimisticUpdate {
    /// 失敗時に書き戻すべき値を返す。書き戻してはいけない場合は `nil`。
    ///
    /// - Parameters:
    ///   - current: いま画面が保持している値
    ///   - optimistic: 自分が先に書き込んだ楽観値
    ///   - previous: 楽観値を書く直前の値（ロールバック先）
    /// - Returns: `current` がまだ `optimistic` と等しければ `previous`。
    ///   すでに別の値へ進んでいれば `nil`（＝触らない）
    static func rollbackValue<T: Equatable>(current: T, optimistic: T, previous: T) -> T? {
        current == optimistic ? previous : nil
    }
}
