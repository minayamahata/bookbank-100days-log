import Foundation
import UniformTypeIdentifiers

/// コピー・保存・共有で共用する出力画像。Data と PNG/JPEG 種別を一体で持つ。
struct MonthlyLogShareExportAsset: Equatable, Sendable {
    enum Format: Equatable, Hashable, Sendable {
        case png
        case jpeg
    }

    let data: Data
    let format: Format

    var utType: UTType {
        switch format {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        }
    }

    var fileExtension: String {
        switch format {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }
}
