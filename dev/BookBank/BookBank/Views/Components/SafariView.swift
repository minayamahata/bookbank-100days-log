//
//  SafariView.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SafariServices
import SwiftUI

/// sheet 表示用の URL ラッパー
struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SFSafariViewController の SwiftUI ラッパー
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
