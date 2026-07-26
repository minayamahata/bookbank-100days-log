//
//  LocalCoverImage.swift
//  BookBank
//

import SwiftUI
import UIKit

/// 手動登録の表紙画像（`coverImageData`）を bookId 経由で解決して子ビューへ渡すコンテナ。
///
/// 設計メモ 前提4により画像バイナリは `BookDTO` に載らない。通常は
/// `SwiftDataBookRepository.fetchSorted()` が同じターンで `LocalCoverDataCache` を満たすため、
/// `init` の同期ヒットで**初回フレームから**画像が出る（現行の `book.coverUIImage` と同じ見え）。
///
/// キャッシュミス（LRU退避後の再描画など）だけ `loadCoverImage(bookId:)` へ非同期フォールバックする。
/// `content` には解決済みの `UIImage`（画像なし・未解決は nil）が渡るので、
/// 呼び出し側は従来の「ローカル画像 → URL → プレースホルダ」の分岐をそのまま残せる。
struct LocalCoverImage<Content: View>: View {
    let book: BookDTO
    @ViewBuilder var content: (UIImage?) -> Content

    @Environment(AppRepositories.self) private var repos
    @State private var image: UIImage?

    init(book: BookDTO, @ViewBuilder content: @escaping (UIImage?) -> Content) {
        self.book = book
        self.content = content
        _image = State(
            initialValue: book.hasCoverImage ? LocalCoverDataCache.shared.image(for: book.id) : nil
        )
    }

    /// 表紙が差し替わったとき（`updatedAt` 更新 or 有無の変化）に再解決するための鍵
    private var reloadKey: String {
        "\(book.id)|\(book.hasCoverImage)|\(book.updatedAt.timeIntervalSince1970)"
    }

    var body: some View {
        content(image)
            .task(id: reloadKey) {
                await resolve()
            }
    }

    private func resolve() async {
        guard book.hasCoverImage else {
            if image != nil { image = nil }
            return
        }
        if let cached = LocalCoverDataCache.shared.image(for: book.id) {
            if image !== cached { image = cached }
            return
        }
        // キャッシュミス（LRU退避等）: 非同期フォールバック
        guard let data = await repos.books.loadCoverImage(bookId: book.id), !data.isEmpty else {
            if image != nil { image = nil }
            return
        }
        image = LocalCoverDataCache.shared.storeAndDecode(data, for: book.id)
    }
}
