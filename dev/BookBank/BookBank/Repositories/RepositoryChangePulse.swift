import Foundation

/// リポジトリ横断の変更通知（設計メモ 4.3節 案A）。
/// どのリポジトリでも書き込み成功後に `notify()` し、全アクティブな observe ストリームが再fetchする。
@MainActor
final class RepositoryChangePulse {
    typealias Observer = () -> Void

    private var observers: [UUID: Observer] = [:]

    @discardableResult
    func addObserver(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    func notify() {
        for observer in observers.values {
            observer()
        }
    }
}
