//
//  FontLicenseView.swift
//  BookBank
//
//  Created on 2026/08/19
//

import SwiftUI

/// フォントライセンス画面（設定 > サービス案内）。
/// 使用フォント一覧と SIL OFL 1.1 全文をオフラインで表示する。
struct FontLicenseView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let _ = themeManager.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FontLicense.fontFamilies, id: \.self) { family in
                        Text(verbatim: family)
                            .font(.app(.body))
                            .foregroundColor(.primary)
                    }
                    Text(verbatim: FontLicense.copyrightNotice)
                        .font(.app(.footnote))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appCardBackground)
                )

                if let licenseText = FontLicense.licenseText() {
                    Text(verbatim: licenseText)
                        .font(.app(.footnote))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appCardBackground)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("service.font_license")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
    }
}

#Preview {
    NavigationStack {
        FontLicenseView()
    }
    .environment(ThemeManager())
}
