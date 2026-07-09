//
//  ReadingList.swift
//  BookBank
//
//  Created on 2026/01/31
//

import Foundation
import SwiftData

/// 読了リストモデル
/// ユーザーが作成するキュレーションリスト（Spotifyのプレイリストのような機能）
@Model
final class ReadingList {
    
    // MARK: - Properties
    
    /// 安定ID（UUID文字列）。R3で追加したFirestore docID用の「眠った土台」。
    /// R6では listId＝uuid。R3ではどのViewからも参照されない。
    /// 既存行の一意性はデフォルト式ではなく UUIDBackfillMigration が保証する（設計メモ 4.2）。
    var uuid: String = UUID().uuidString
    
    /// リストのタイトル（例：「2024年ベスト」）
    var title: String
    
    /// 説明文（任意）
    var listDescription: String?
    
    /// 作成日時
    var createdAt: Date
    
    /// 更新日時
    var updatedAt: Date
    
    /// テーマカラーのインデックス（nilの場合はデフォルト色）
    var colorIndex: Int?
    
    /// 本の並び順（各本の UserBook.uuid を並び順どおりに保持）。R3で bookOrderData から移行。
    var bookIds: [String] = []
    
    /// 【レガシー】旧・並び順JSON（stableID配列）。R3で bookIds へ移行済みで読み書きは停止。
    /// ReadingListOrderMigration が変換時に一度だけ読むためだけに残す。
    /// 物理削除はSwiftData廃止時に行う（設計メモ 前提6・変換失敗時のフォールバック源）。
    var bookOrderData: String?
    
    // MARK: - Relationships
    
    /// リストに含まれる本（参照）
    /// 本が削除されると自動的にリストからも消える
    var books: [UserBook]
    
    // MARK: - Initialization
    
    init(
        title: String,
        listDescription: String? = nil
    ) {
        self.uuid = UUID().uuidString
        self.title = title
        self.listDescription = listDescription
        self.createdAt = Date()
        self.updatedAt = Date()
        self.bookIds = []
        self.bookOrderData = nil
        self.books = []
    }
}

// MARK: - Computed Properties

extension ReadingList {
    /// bookIds（UserBook.uuid の配列）に基づいてソートされた本のリスト。
    /// bookIds に記載のない本は末尾に追記する（現行のフォールバックを維持）。
    var orderedBooks: [UserBook] {
        guard !bookIds.isEmpty else { return books }
        let uuidToBook = Dictionary(
            books.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ordered: [UserBook] = []
        var usedUUIDs = Set<String>()
        for id in bookIds {
            if let book = uuidToBook[id] {
                ordered.append(book)
                usedUUIDs.insert(id)
            }
        }
        for book in books {
            if !usedUUIDs.contains(book.uuid) {
                ordered.append(book)
            }
        }
        return ordered
    }
    
    /// 本の並び順を保存（UserBook.uuid の配列として保持）
    func saveBookOrder(_ orderedBooks: [UserBook]) {
        bookIds = orderedBooks.map { $0.uuid }
    }
    
    /// リスト内の書籍数
    var bookCount: Int {
        books.count
    }
    
    /// 合計金額（登録時価格の合計）
    var totalValue: Int {
        books.compactMap { $0.priceAtRegistration }.reduce(0, +)
    }
    
    /// 表示用の合計金額
    var displayTotalValue: String {
        "¥\(totalValue.formatted())"
    }
}
