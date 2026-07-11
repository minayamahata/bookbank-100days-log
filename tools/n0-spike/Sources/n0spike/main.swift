import Foundation
import N0SpikeCore

// N0スパイク評価ハーネス CLI
// 使い方:
//   swift run n0spike <input.json> [--out report.md]
//     [--k 8] [--m 30] [--idf 0.25] [--floor 0.15] [--prefix-ratio 0.6] [--prefix-chars 4]

var arguments = Array(CommandLine.arguments.dropFirst())
guard let inputPath = arguments.first, !inputPath.hasPrefix("--") else {
    print("""
    usage: n0spike <input.json> [--out report.md] [--k 8] [--m 30] [--idf 0.25] \
    [--floor 0.15] [--prefix-ratio 0.6] [--prefix-chars 4]
    """)
    exit(1)
}
arguments.removeFirst()

var outputPath: String?
var parameters = SpikeParameters()
var index = 0
while index < arguments.count {
    let flag = arguments[index]
    func nextValue() -> String? {
        index + 1 < arguments.count ? arguments[index + 1] : nil
    }
    switch flag {
    case "--out": outputPath = nextValue(); index += 2
    case "--k": parameters.edgeLimitK = Int(nextValue() ?? "") ?? parameters.edgeLimitK; index += 2
    case "--m": parameters.keywordLimitM = Int(nextValue() ?? "") ?? parameters.keywordLimitM; index += 2
    case "--idf": parameters.idfThreshold = Double(nextValue() ?? "") ?? parameters.idfThreshold; index += 2
    case "--floor": parameters.scoreFloor = Double(nextValue() ?? "") ?? parameters.scoreFloor; index += 2
    case "--prefix-ratio": parameters.prefixRatio = Double(nextValue() ?? "") ?? parameters.prefixRatio; index += 2
    case "--prefix-chars": parameters.prefixMinChars = Int(nextValue() ?? "") ?? parameters.prefixMinChars; index += 2
    default:
        print("unknown flag: \(flag)")
        exit(1)
    }
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    let input = try JSONDecoder().decode(ShelfInput.self, from: data)

    let start = Date()
    let series = SeriesClustering.cluster(books: input.books, parameters: parameters)
    let keywords = KeywordExtraction.extract(
        books: input.books, memos: input.monthlyMemos, parameters: parameters
    )
    let graph = EdgeComputation.compute(
        books: input.books, series: series, keywords: keywords,
        memos: input.monthlyMemos, parameters: parameters
    )
    let elapsed = Date().timeIntervalSince(start)

    let report = Report.generate(
        books: input.books, series: series, keywords: keywords,
        graph: graph, parameters: parameters
    ) + "\n---\n計算時間: \(String(format: "%.2f", elapsed))秒\n"

    if let outputPath {
        try report.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        print("レポートを書き出しました: \(outputPath)")
    } else {
        print(report)
    }
} catch {
    print("エラー: \(error)")
    exit(1)
}
