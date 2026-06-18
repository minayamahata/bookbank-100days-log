//
//  AppMenuButton.swift
//  BookBank
//
//  Created on 2026/06/07
//

import SwiftUI

/// ナビゲーションバー用のハンバーガーメニューボタン
struct AppMenuButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
        }
        .tint(.primary)
    }
}
