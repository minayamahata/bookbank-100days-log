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
        self.books = []
    }
}

// MARK: - Computed Properties

extension ReadingList {
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
