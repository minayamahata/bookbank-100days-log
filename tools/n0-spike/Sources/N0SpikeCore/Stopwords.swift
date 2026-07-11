import Foundation

/// 静的ストップワード辞書（5言語・設計書 3.2節 手順4）。
/// 書籍タイトル頻出の一般語を中心とした初版。N0の評価で追記する（計画メモ 第7章）。
/// R5でリソースファイルに昇格させる。
public enum Stopwords {

    public static let japanese: Set<String> = [
        "本", "物語", "話", "入門", "講座", "教科書", "事典", "辞典", "図鑑", "全集",
        "選集", "作品", "作品集", "短編", "短編集", "長編", "小説", "エッセイ", "评论",
        "評論", "研究", "考察", "世界", "日本", "現代", "時代", "歴史", "完全", "最新",
        "改訂", "新版", "新装", "文庫", "新書", "単行本", "上", "下", "巻", "編", "著",
        "訳", "監修", "版", "集", "論", "学", "書", "手帖", "手帳", "ノート", "読本",
        "案内", "ガイド", "ブック", "シリーズ", "セット", "こと", "もの", "ため", "とき",
        "方法", "技術", "基礎", "基本", "実践", "理論", "紹介", "解説", "特集", "冊",
        "はじめて", "はじめ", "ちくま", "岩波", "講談", "文春", "新潮", "角川",
        // メモ由来の雑音（形式名詞・複合助詞・機能語の断片）。
        // 5言語テストデータの実走で頻度表・エッジに浮上したものを追記（手順4・2026-07-11）
        "これ", "それ", "あれ", "どれ", "ここ", "そこ", "いう", "という", "なっ",
        "られ", "させ", "たい", "つい", "ついて", "について", "きっかけ", "ところ",
        "あたり", "わけ", "ほう", "よう"
    ]

    public static let english: Set<String> = [
        "book", "books", "novel", "story", "stories", "tale", "tales", "guide",
        "introduction", "handbook", "manual", "edition", "revised", "complete",
        "collection", "collected", "selected", "works", "series", "volume",
        "chronicles", "history", "world", "life", "new", "first", "second",
        "art", "way", "little", "great", "big", "good", "best", "man", "woman",
        "time", "year", "years", "day", "days", "night", "house", "home"
    ]

    public static let korean: Set<String> = [
        "책", "소설", "이야기", "입문", "가이드", "사전", "전집", "단편", "장편",
        "에세이", "연구", "세계", "한국", "현대", "역사", "완전", "최신", "개정판",
        "신판", "문고", "권", "편", "저", "역", "판", "집", "론", "학", "방법",
        "기술", "기초", "기본", "실전", "이론", "해설", "특집"
    ]

    public static let simplifiedChinese: Set<String> = [
        "书", "小说", "故事", "入门", "指南", "词典", "全集", "短篇", "长篇",
        "随笔", "研究", "世界", "中国", "现代", "历史", "完全", "最新", "修订",
        "新版", "文库", "卷", "编", "著", "译", "版", "集", "论", "学", "方法",
        "技术", "基础", "基本", "实践", "理论", "解说", "特辑", "第一", "第二"
    ]

    public static let traditionalChinese: Set<String> = [
        "書", "小說", "故事", "入門", "指南", "詞典", "全集", "短篇", "長篇",
        "隨筆", "研究", "世界", "中國", "臺灣", "台灣", "現代", "歷史", "完全",
        "最新", "修訂", "新版", "文庫", "卷", "編", "著", "譯", "版", "集", "論",
        "學", "方法", "技術", "基礎", "基本", "實踐", "理論", "解說", "特輯"
    ]

    /// 言語コード（"ja" / "en" / "ko" / "zh-Hans" / "zh-Hant"）に対応する辞書を返す。
    /// 未知の言語は英語辞書にフォールバックする。
    public static func forLanguage(_ code: String) -> Set<String> {
        switch code {
        case "ja": return japanese
        case "ko": return korean
        case "zh-Hans": return simplifiedChinese
        case "zh-Hant": return traditionalChinese
        default: return english
        }
    }
}
