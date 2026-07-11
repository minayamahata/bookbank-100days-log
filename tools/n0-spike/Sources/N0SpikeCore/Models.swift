import Foundation

/// 入力JSON（アプリのデバッグエクスポート or 5言語テストデータ）のスキーマ。
/// docs/n0-spike-plan.md 3.1節の必要フィールドに対応する。
public struct ShelfInput: Codable {
    public var books: [InputBook]
    public var monthlyMemos: [InputMemo]

    public init(books: [InputBook], monthlyMemos: [InputMemo] = []) {
        self.books = books
        self.monthlyMemos = monthlyMemos
    }
}

public struct InputBook: Codable {
    public var uuid: String
    public var title: String
    public var author: String?
    public var seriesName: String?
    public var memo: String?
    public var isbn: String?
    public var publishedYear: Int?
    /// ISO8601文字列（月の突合には先頭の "yyyy-MM" だけを使う）
    public var registeredAt: String?
    /// 参考情報（レポート表示用・計算には使わない）
    public var passbookName: String?
    /// テストデータのみ: 期待されるシリーズクラスタの正解ラベル（実本棚データでは nil）
    public var expectedSeriesKey: String?

    public init(
        uuid: String,
        title: String,
        author: String? = nil,
        seriesName: String? = nil,
        memo: String? = nil,
        isbn: String? = nil,
        publishedYear: Int? = nil,
        registeredAt: String? = nil,
        passbookName: String? = nil,
        expectedSeriesKey: String? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.author = author
        self.seriesName = seriesName
        self.memo = memo
        self.isbn = isbn
        self.publishedYear = publishedYear
        self.registeredAt = registeredAt
        self.passbookName = passbookName
        self.expectedSeriesKey = expectedSeriesKey
    }

    /// "yyyy-MM"（登録月）。registeredAt が欠損・短い場合は nil
    public var registeredMonth: String? {
        guard let value = registeredAt, value.count >= 7 else { return nil }
        return String(value.prefix(7))
    }
}

public struct InputMemo: Codable {
    public var year: Int
    public var month: Int
    public var text: String

    public init(year: Int, month: Int, text: String) {
        self.year = year
        self.month = month
        self.text = text
    }

    public var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }
}
