import SwiftUI

extension Color {
    /// 色の輝度（明るさ）を計算（0.0〜1.0）
    var luminance: Double {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }
    
    var contrastingTextColor: Color {
        luminance > 0.5 ? .black : .white
    }
    
    var contrastingSecondaryTextColor: Color {
        luminance > 0.5 ? .black.opacity(0.6) : .white.opacity(0.7)
    }
}
