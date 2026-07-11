#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - N0スパイク用デバッグエクスポート
//
// ノードグラフ機能（R5）のN0スパイク（docs/n0-spike-plan.md 3.2節）のための
// 本棚データJSONエクスポート。DEBUGビルド限定で、リリースには一切含まれない。
// 出力スキーマは tools/n0-spike/Sources/N0SpikeCore/Models.swift の ShelfInput と一致させること。
// メモは私有データのため、出力JSONをリポジトリにコミットしてはならない（同節）。

/// ShelfInput.books の1件に対応
private struct N0ExportBook: Encodable {
    let uuid: String
    let title: String
    let author: String?
    let seriesName: String?
    let memo: String?
    let isbn: String?
    let publishedYear: Int?
    let registeredAt: String?
    let passbookName: String?
}

/// ShelfInput.monthlyMemos の1件に対応
private struct N0ExportMemo: Encodable {
    let year: Int
    let month: Int
    let text: String
}

private struct N0ExportShelf: Encodable {
    let books: [N0ExportBook]
    let monthlyMemos: [N0ExportMemo]
}

/// 全書籍＋月別メモをN0スパイクの入力JSON文字列に変換する
@MainActor
func generateN0SpikeExportJSON(context: ModelContext) throws -> String {
    let isoFormatter = ISO8601DateFormatter()

    let books = try context.fetch(FetchDescriptor<UserBook>()).map { book in
        N0ExportBook(
            uuid: book.uuid,
            title: book.title,
            author: book.author,
            seriesName: book.seriesName,
            memo: book.memo,
            isbn: book.isbn,
            publishedYear: book.publishedYear,
            registeredAt: isoFormatter.string(from: book.registeredAt),
            passbookName: book.passbook?.name
        )
    }
    let memos = try context.fetch(FetchDescriptor<MonthlyMemo>()).map { memo in
        N0ExportMemo(year: memo.year, month: memo.month, text: memo.text)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(N0ExportShelf(books: books, monthlyMemos: memos))
    return String(decoding: data, as: UTF8.self)
}

/// fileExporter 用のJSONドキュメント
struct N0SpikeJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
#endif
