import Foundation
import UIKit

/// 手動登録の表紙画像（`UserBook.coverImageData`）のメモリキャッシュ。
///
/// 設計メモ 前提4により画像バイナリは `BookDTO`・ストリームに載せない。一方で
/// `BookRepository.loadCoverImage(bookId:)` は `async`（R6のStorage取得を受けるため）であり、
/// View から呼ぶ限り最初の1フレームは画像が出ない＝「見た目不変」（前提13）に反する。
///
/// そこで `SwiftDataBookRepository.fetchSorted()` が DTO を組み立てる同じターンで、
/// 未キャッシュのバイナリをここへ**同期投入**する。View は `init` で同期ヒットできるため、
/// 初回フレームから現行（`UserBook.coverUIImage` の同期読み）と同一の見えになる。
///
/// - Important: **R4（SwiftData期）限定の暫定配置であり、R6では解体が必要**。
///   Firestore/Storage 実装は `fetchSorted` 相当の中で表紙を同期読みできないため、
///   R6では「非同期ロード＋プレースホルダ」を正式な見えとして設計し直すことになる
///   （設計メモ 4.6節）。
///
/// バイト数を cost に使った LRU で上限を切る。退避された分は
/// 次の fetch で再投入されるか、`LocalCoverImage` の非同期フォールバックが拾う。
final class LocalCoverDataCache: @unchecked Sendable {
    static let shared = LocalCoverDataCache()

    private let dataCache = NSCache<NSString, NSData>()
    /// デコード済み画像。現行は body 評価のたびに `UIImage(data:)` していたため、
    /// ここで持つのはコスト面の改善方向（見えは不変）。
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        dataCache.totalCostLimit = 50 * 1024 * 1024
        imageCache.countLimit = 300
        imageCache.totalCostLimit = 50 * 1024 * 1024
    }

    // MARK: - 投入・破棄

    func setData(_ data: Data, for bookId: String) {
        dataCache.setObject(data as NSData, forKey: bookId as NSString, cost: data.count)
        imageCache.removeObject(forKey: bookId as NSString)
    }

    /// 未登録のときだけ投入する（既存のキャッシュを新しい値で潰さない）。
    /// ステップ5までのハイブリッド経路（`ReadingListDetailView` → 書籍詳細）で使う
    func setDataIfAbsent(_ data: Data, for bookId: String) {
        guard !hasData(for: bookId) else { return }
        setData(data, for: bookId)
    }

    /// 表紙の差し替え・削除・本の削除で呼ぶ（古い表紙が出続けるのを防ぐ）
    func invalidate(bookId: String) {
        dataCache.removeObject(forKey: bookId as NSString)
        imageCache.removeObject(forKey: bookId as NSString)
    }

    /// 全消去。**テストの tearDown 専用**（プロセス共有シングルトンがテスト間で状態を持ち越すのを防ぐ）。
    /// 脱シングルトン化（DI）はステップ6またはR6の解体時に行う（設計メモ 4.6節・レビュー S4-5）
    func removeAll() {
        dataCache.removeAllObjects()
        imageCache.removeAllObjects()
    }

    // MARK: - 取得

    func hasData(for bookId: String) -> Bool {
        dataCache.object(forKey: bookId as NSString) != nil
    }

    /// 同期取得（キャッシュミスは nil。呼び出し側が非同期フォールバックする）
    func image(for bookId: String) -> UIImage? {
        let key = bookId as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let data = dataCache.object(forKey: key) as Data? ,
              let image = UIImage(data: data) else {
            return nil
        }
        imageCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// 非同期フォールバックで得たバイナリを登録しつつ画像化する
    func storeAndDecode(_ data: Data, for bookId: String) -> UIImage? {
        setData(data, for: bookId)
        return image(for: bookId)
    }
}
