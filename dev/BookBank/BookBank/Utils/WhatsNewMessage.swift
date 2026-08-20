//
//  WhatsNewMessage.swift
//  BookBank
//
//  新機能のお知らせの内容定義（docs/whats-new-message-design.md）。
//  ページの件数・順番・画像名はここが正。文言は Localizable.xcstrings のキーで持つ。
//

import Foundation

/// お知らせの1ページ。順番は `WhatsNewMessage.pages` の並びで固定。
struct WhatsNewPage: Equatable, Identifiable, Sendable {
    /// ページ番号の表記（"01"〜"04"。言語によらずこの表記で固定）
    let id: String
    let titleKey: String
    let descriptionKey: String
    let imageName: String
}

enum WhatsNewMessage {
    /// お知らせ対象バージョン（build番号ではない固定値）
    static let version = "1.7.0"

    /// 見出しのフォーマットキー（ja: 「新機能 %@」）
    static let headerKey = "whats_new.header"
    static let nextKey = "whats_new.next"
    static let getStartedKey = "whats_new.get_started"
    static let closeAccessibilityKey = "whats_new.accessibility.close"
    /// ドット行のアクセシビリティ（ja: 「ページ %lld / %lld」）
    static let pageIndicatorAccessibilityKey = "whats_new.accessibility.page"

    static let pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "01",
            titleKey: "whats_new.title.01",
            descriptionKey: "whats_new.description.01",
            imageName: "img_news-01"
        ),
        WhatsNewPage(
            id: "02",
            titleKey: "whats_new.title.02",
            descriptionKey: "whats_new.description.02",
            imageName: "img_news-02"
        ),
        WhatsNewPage(
            id: "03",
            titleKey: "whats_new.title.03",
            descriptionKey: "whats_new.description.03",
            imageName: "img_news-03"
        ),
        WhatsNewPage(
            id: "04",
            titleKey: "whats_new.title.04",
            descriptionKey: "whats_new.description.04",
            imageName: "img_news-04"
        ),
        WhatsNewPage(
            id: "05",
            titleKey: "whats_new.title.05",
            descriptionKey: "whats_new.description.05",
            imageName: "img_news-05"
        )
    ]
}
