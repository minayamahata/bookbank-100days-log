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
    
    /// 本の並び順を保持するJSON文字列（各本の stableID を配列で保持）
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
        self.title = title
        self.listDescription = listDescription
        self.createdAt = Date()
        self.updatedAt = Date()
        self.bookOrderData = nil
        self.books = []
    }
}

// MARK: - Computed Properties

extension ReadingList {
    /// 本の安定した識別子を生成（title + createdAt のハッシュ）
    static func stableID(for book: UserBook) -> String {
        "\(book.title)_\(book.createdAt.timeIntervalSince1970)"
    }
    
    /// bookOrderData をデコードして ID 配列を取得
    private var bookOrderIDs: [String] {
        guard let data = bookOrderData?.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
    
    /// bookOrder に基づいてソートされた本のリスト
    var orderedBooks: [UserBook] {
        let ids = bookOrderIDs
        guard !ids.isEmpty else { return books }
        let idToBook = Dictionary(
            books.map { (Self.stableID(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ordered: [UserBook] = []
        var usedIDs = Set<String>()
        for id in ids {
            if let book = idToBook[id] {
                ordered.append(book)
                usedIDs.insert(id)
            }
        }
        for book in books {
            if !usedIDs.contains(Self.stableID(for: book)) {
                ordered.append(book)
            }
        }
        return ordered
    }
    
    /// 本の並び順を保存
    func saveBookOrder(_ orderedBooks: [UserBook]) {
        let ids = orderedBooks.map { Self.stableID(for: $0) }
        if let data = try? JSONEncoder().encode(ids) {
            bookOrderData = String(data: data, encoding: .utf8)
        }
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
