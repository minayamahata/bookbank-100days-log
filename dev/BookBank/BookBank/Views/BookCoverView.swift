//
//  BookCoverView.swift
//  BookBank
//
//  Created on 2026/01/24
//

import SwiftUI

/// 本棚グリッド用の本の表紙ビュー
struct BookCoverView: View {
    let book: BookDTO

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
                LocalCoverImage(book: book) { coverImage in
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                            .clipped()
                    } else if let imageURL = book.coverImageURL,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(
                            url: url,
                            width: geometry.size.width,
                            height: geometry.size.width * 1.5
                        )
                    } else {
                        placeholderView(width: geometry.size.width)
                    }
                }

                // アイコンバッジ（お気に入り・メモ）
                if book.isFavorite || hasMemo {
                    HStack(spacing: 2) {
                        if hasMemo {
                            Image("icon-memo")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 8, height: 8)
                                .foregroundColor(.black)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                )
                        }
                        if book.isFavorite {
                            Image("icon-favorite")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 8, height: 8)
                                .foregroundColor(.black)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                )
                        }
                    }
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
                Text(book.title)
                    .font(.app(.caption2))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
    }
}

#Preview {
    Group {
        if let book = PreviewSupport.book(source: .manual) {
            BookCoverView(book: book)
                .frame(width: 100)
        } else {
            Text("No preview book")
        }
    }
    .bookBankPreviewEnvironment()
}
