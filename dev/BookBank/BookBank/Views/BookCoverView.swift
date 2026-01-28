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
    
    var body: some View {
        GeometryReader { geometry in
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                            .clipped()
                    case .failure(_):
                        placeholderView(width: geometry.size.width)
                    case .empty:
                        ProgressView()
                            .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                            .background(Color.gray.opacity(0.1))
                    @unknown default:
                        placeholderView(width: geometry.size.width)
                    }
                }
            } else {
                placeholderView(width: geometry.size.width)
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
