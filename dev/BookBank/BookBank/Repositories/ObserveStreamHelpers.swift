import Foundation

/// `observe〜` 用の前回yield値保持（ジェネリッククロージャ内に型をネストできない制約への対処）
private final class EquatingStreamState<T>: @unchecked Sendable {
    var last: T?
}

/// `observe〜` 用: 購読開始時に現在値を yield し、パルスのたびに再fetch。前回と等値なら再yieldしない。
@MainActor
func makeEquatingStream<T: Equatable>(
    pulse: RepositoryChangePulse,
    fetch: @escaping @MainActor () -> T
) -> AsyncStream<T> {
    AsyncStream { continuation in
        let state = EquatingStreamState<T>()

        let emit: () -> Void = {
            let next = fetch()
            if state.last != next {
                state.last = next
                continuation.yield(next)
            }
        }

        emit()
        let observerID = pulse.addObserver(emit)
        continuation.onTermination = { @Sendable _ in
            Task { @MainActor in
                pulse.removeObserver(observerID)
            }
        }
    }
}
