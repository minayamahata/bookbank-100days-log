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
    
    @State private var loadedImage: Image?
    @State private var isLoading = false
    @State private var loadFailed = false
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                loadedImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
                    .background(Color.gray.opacity(0.1))
            } else if loadFailed {
                placeholderView
            } else {
                Color.clear
                    .frame(width: width, height: height)
                    .onAppear {
                        loadImage()
                    }
            }
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
    
    private func loadImage() {
        guard let url = url else {
            loadFailed = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        loadedImage = Image(uiImage: uiImage)
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        loadFailed = true
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    loadFailed = true
                    isLoading = false
                }
            }
        }
    }
}
