//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData

struct BookshelfView: View {
    @Environment(\.modelContext) private var context
    
    // すべての本を取得（登録日降順）
    @Query(sort: \UserBook.registeredAt, order: .reverse) private var allBooks: [UserBook]
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if allBooks.isEmpty {
                    // 空状態
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("本棚はまだ空です")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("本を登録して本棚を埋めましょう")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // 本棚グリッド
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(allBooks) { book in
                            NavigationLink(destination: UserBookDetailView(book: book)) {
                                BookCoverView(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2) // 左右の余白を2pxに
                    .padding(.bottom, 100) // タブバー分の余白を確実に確保
                }
            }
            .ignoresSafeArea(edges: .bottom) // タブバーの下まで表示
            .navigationTitle("本棚")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// 本の表紙ビュー
struct BookCoverView: View {
    let book: UserBook
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // 表紙画像（画面幅の25%、アスペクト比2:3）
                if let imageURL = book.imageURL,
                   let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill) // object-fit: cover
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .clipped()
                        case .failure(_):
                            // 読み込み失敗
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .overlay {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                }
                        case .empty:
                            // 読み込み中
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // 画像がない場合
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                }
                
                // お気に入りマーク（右上に配置）
                if book.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
            }
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .aspectRatio(2/3, contentMode: .fit) // アスペクト比2:3（横:縦）
        .cornerRadius(2) // 2pxの角丸
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook.createOverall()
    container.mainContext.insert(passbook)
    
    // サンプル本を追加
    for i in 1...10 {
        let book = UserBook(
            title: "サンプル本 \(i)",
            author: "著者\(i)",
            price: 1500,
            passbook: passbook
        )
        if i % 3 == 0 {
            book.isFavorite = true
        }
        container.mainContext.insert(book)
    }
    
    return BookshelfView()
        .modelContainer(container)
}
