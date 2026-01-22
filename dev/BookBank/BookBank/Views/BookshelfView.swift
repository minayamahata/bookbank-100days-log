//
//  BookshelfView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData
import UIKit

struct BookshelfView: View {
    @Environment(\.modelContext) private var context
    
    // 表示対象の口座
    let passbook: Passbook
    
    // すべての本を取得（登録日降順）
    @Query(sort: \UserBook.registeredAt, order: .reverse) private var allBooks: [UserBook]
    
    // この口座の本のみをフィルタリング
    private var userBooks: [UserBook] {
        allBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID
        }
    }
    
    // グリッドの列定義（4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            if userBooks.isEmpty {
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
                    ForEach(userBooks) { book in
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

// 本の表紙ビュー
struct BookCoverView: View {
    let book: UserBook
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // 表紙画像（画面幅の25%、アスペクト比2:3）
                if let imageURL = book.imageURL,
                   let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill) // object-fit: cover
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .clipped()
                        case .failure:
                            // 読み込み失敗
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .overlay {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                }
                        case .loading:
                            // 読み込み中
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.5)
                                .overlay {
                                    ProgressView()
                                }
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

// MARK: - CachedAsyncImage

/// 画像読み込みの状態
enum CachedImagePhase {
    case loading
    case success(Image)
    case failure
}

/// メモリキャッシュ付きの非同期画像ローダー
struct CachedAsyncImage<Content: View>: View {
    let url: URL
    let content: (CachedImagePhase) -> Content
    
    @State private var phase: CachedImagePhase = .loading
    
    init(url: URL, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
    }
    
    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }
    
    private func loadImage() async {
        // まずメモリキャッシュを確認
        if let cachedImage = ImageCache.shared.get(forKey: url.absoluteString) {
            phase = .success(Image(uiImage: cachedImage))
            return
        }
        
        // キャッシュになければダウンロード
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // HTTPレスポンスの確認
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                phase = .failure
                return
            }
            
            // 画像データの変換
            guard let uiImage = UIImage(data: data) else {
                phase = .failure
                return
            }
            
            // メモリキャッシュに保存
            ImageCache.shared.set(uiImage, forKey: url.absoluteString)
            
            // 成功
            phase = .success(Image(uiImage: uiImage))
        } catch {
            phase = .failure
        }
    }
}

// MARK: - ImageCache

/// 画像のメモリキャッシュ
final class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // キャッシュの制限を設定
        cache.countLimit = 100 // 最大100枚
        cache.totalCostLimit = 50 * 1024 * 1024 // 最大50MB
    }
    
    func get(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func set(_ image: UIImage, forKey key: String) {
        // 画像のおおよそのメモリサイズを計算
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    func removeAll() {
        cache.removeAllObjects()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
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
    
    return BookshelfView(passbook: passbook)
        .modelContainer(container)
}
