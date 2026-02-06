//
//  BookCoverView.swift
//  BookBank
//
//  Created on 2026/01/24
//

import SwiftUI
import SwiftData

/// 本棚グリッド用の本の表紙ビュー
struct BookCoverView: View {
    let book: UserBook
    
    /// メモがあるかどうか
    private var hasMemo: Bool {
        if let memo = book.memo, !memo.isEmpty {
            return true
        }
        return false
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // 本の表紙
                if let imageURL = book.imageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(
                        url: url,
                        width: geometry.size.width,
                        height: geometry.size.width * 1.5
                    )
                } else {
                    placeholderView(width: geometry.size.width)
                }
                
                // アイコンバッジ（お気に入り・メモ）
                if book.isFavorite || hasMemo {
                    HStack(spacing: 2) {
                        if hasMemo {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                        if book.isFavorite {
                            Image("icon-favorite")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
                    .padding(4)
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
    
    private func placeholderView(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: width * 1.5)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text(book.title)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "テスト", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    let book = UserBook(
        title: "サンプル本",
        author: "著者名",
        price: 1500,
        passbook: passbook
    )
    container.mainContext.insert(book)
    
    return BookCoverView(book: book)
        .frame(width: 100)
        .modelContainer(container)
}
