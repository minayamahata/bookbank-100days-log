//
//  CachedAsyncImage.swift
//  BookBank
//
//  Created on 2026/02/02
//

import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    /// 画像の表示モード（既定は .fill。検索結果など全体を収めたい場合は .fit を渡す）
    var contentMode: ContentMode = .fill

    @State private var loadedImage: Image?
    @State private var isLoading: Bool
    @State private var loadFailed: Bool

    init(url: URL?, width: CGFloat, height: CGFloat, contentMode: ContentMode = .fill) {
        self.url = url
        self.width = width
        self.height = height
        self.contentMode = contentMode

        if let url, let cached = BookCoverImageCache.shared.image(for: url) {
            _loadedImage = State(initialValue: Image(uiImage: cached))
            _isLoading = State(initialValue: false)
            _loadFailed = State(initialValue: false)
        } else if url != nil {
            _loadedImage = State(initialValue: nil)
            _isLoading = State(initialValue: true)
            _loadFailed = State(initialValue: false)
        } else {
            _loadedImage = State(initialValue: nil)
            _isLoading = State(initialValue: false)
            _loadFailed = State(initialValue: true)
        }
    }

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipped()
            } else if loadFailed {
                placeholderView
            } else {
                ProgressView()
                    .frame(width: width, height: height)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            Task { await loadImage() }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
    }

    @MainActor
    private func loadImage() async {
        guard loadedImage == nil else { return }

        guard let url else {
            loadFailed = true
            isLoading = false
            return
        }

        if let cached = BookCoverImageCache.shared.image(for: url) {
            loadedImage = Image(uiImage: cached)
            isLoading = false
            loadFailed = false
            return
        }

        isLoading = true
        loadFailed = false

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            if let uiImage = UIImage(data: data) {
                BookCoverImageCache.shared.setImage(uiImage, for: url)
                loadedImage = Image(uiImage: uiImage)
            } else {
                loadFailed = true
            }
        } catch is CancellationError {
            isLoading = true
            return
        } catch {
            loadFailed = true
        }

        isLoading = false
    }
}
