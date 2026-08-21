import Foundation

/// 共有画像の背景モード。表示順は白・黒・透明で、初期選択は白。
/// 写真モードは 2026-08-21 のオーナー判断で撤去した（試作のみで提供していない）。
enum MonthlyLogShareBackgroundMode: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case white
    case black
    case transparent

    var id: Int { rawValue }

    static let defaultMode: MonthlyLogShareBackgroundMode = .white

    var palette: MonthlyLogSharePalette {
        switch self {
        case .white:
            return .dark
        case .black, .transparent:
            return .light
        }
    }

    /// 透明だけ PNG、白・黒は JPEG で出力する。
    var exportFormat: MonthlyLogShareExportAsset.Format {
        self == .transparent ? .png : .jpeg
    }

    var localizationKey: String {
        switch self {
        case .white:
            return "monthly_log_share.background.white"
        case .black:
            return "monthly_log_share.background.black"
        case .transparent:
            return "monthly_log_share.background.transparent"
        }
    }
}
