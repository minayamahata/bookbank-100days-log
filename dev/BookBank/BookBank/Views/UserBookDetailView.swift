//
//  UserBookDetailView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI
import SwiftData

struct UserBookDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Bindable var book: UserBook

    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]

    @State private var showMemoEditor = false
    @State private var showDeleteAlert = false

    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }

    private var themeColor: Color {
        if let passbook = book.passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
    private var isBlackTheme: Bool {
        if let passbook = book.passbook {
            return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
        }
        return false
    }
    
    private var favoriteActiveColor: Color {
        if colorScheme == .dark && isBlackTheme {
            return .black
        }
        return themeColor
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    coverSection(screenWidth: geometry.size.width)
                    
                    // ボトムシート風コンテンツ
                    VStack(spacing: 24) {
                        // ハンドル
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 10)
                        
                        titleSection
                        detailSection
                    }
                    .frame(minHeight: geometry.size.height - 280)
                    .background(Color(.systemBackground))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 40,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 40
                        )
                    )
                    .offset(y: -40)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.appGroupedBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image("icon-delete")
                }
                .tint(.white)
            }
        }
        .alert("本を削除しますか？", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                deleteBook()
            }
        } message: {
            Text("この操作は取り消せません。\n「\(book.title)」を削除してもよろしいですか？")
        }
        .tint(.primary)
        .sheet(isPresented: $showMemoEditor) {
            MemoEditorView(memo: Binding(
                get: { book.memo ?? "" },
                set: { _ in }
            )) { newMemo in
                saveMemo(newMemo)
            }
        }
    }
    
    // MARK: - Subviews

    private func coverSection(screenWidth: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            // 背景（本の画像をぼかしたもの）
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                GeometryReader { geo in
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 30)
                            .scaleEffect(1.2)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } placeholder: {
                        Color.black
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .clipped()
                .overlay(Color.black.opacity(0.3))
            } else {
                Color.black
            }

            // 本のカバー画像（前面）
            if let imageURL = book.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: screenWidth - 80,
                            maxHeight: 160
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 8)
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: 20)
            } else {
                Text("画像なし")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .frame(height: 370)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            // お気に入りボタン（右下に配置、削除ボタンと右揃え）
            Button(action: {
                book.isFavorite.toggle()
                try? context.save()
            }) {
                Image("icon-favorite")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(book.isFavorite ? favoriteActiveColor : Color.gray.opacity(0.4))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                    )
            }
            .padding(.bottom, 70)
            .padding(.trailing, 16)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.title2)
                .multilineTextAlignment(.leading)

            if !book.displayAuthor.isEmpty {
                Text(book.displayAuthor)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let price = book.priceAtRegistration {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(price.formatted())")
                        .font(.title3)
                    Text("円")
                        .font(.subheadline)
                }
                .fontWeight(.medium)
                .foregroundColor(themeColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 8) {
                if let passbookName = book.passbook?.name {
                    DetailInfoRow(label: "登録口座", value: passbookName)
                }

                DetailInfoRow(label: "登録日", value: formatDate(book.registeredAt))

                if let publisher = book.publisher {
                    DetailInfoRow(label: "出版社", value: publisher)
                }

                if let publishedYear = book.publishedYear {
                    DetailInfoRow(label: "出版年", value: "\(publishedYear)年")
                }

                if let bookFormat = book.bookFormat {
                    DetailInfoRow(label: "発行形態", value: bookFormat)
                }

                if let pageCount = book.pageCount {
                    DetailInfoRow(label: "ページ数", value: "\(pageCount)ページ")
                }
            }
            .font(.subheadline)
            .padding(.bottom, 24)

            Button(action: {
                showMemoEditor = true
            }) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .frame(minHeight: 120)

                    if let memo = book.memo, !memo.isEmpty {
                        Text(memo)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(20)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    } else {
                        Text("メモはまだありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func deleteBook() {
        context.delete(book)
        try? context.save()
        dismiss()
    }
    
    /// メモを保存（モーダルから呼ばれる）
    private func saveMemo(_ newMemo: String) {
        book.memo = newMemo.isEmpty ? nil : newMemo
        
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("❌ [メモ] 保存エラー: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// 日付をYYYY.MM.DD形式でフォーマット
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

// 詳細情報の行を表示するヘルパーView（ミニマル版）
struct DetailInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
            Spacer()
        }
    }
}

#Preview {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
        
        let passbook = Passbook.createOverall()
        container.mainContext.insert(passbook)
        
        let book = UserBook(
            title: "SwiftUI実践入門",
            author: "山田太郎",
            isbn: "9784123456789",
            publisher: "技術評論社",
            publishedYear: 2024,
            price: 3200,
            imageURL: nil,
            source: .api,
            passbook: passbook
        )
        book.memo = "とても分かりやすい本でした。特にSwiftDataの解説が良かったです。"
        book.isFavorite = true
        container.mainContext.insert(book)
        
        return NavigationStack {
            UserBookDetailView(book: book)
                .modelContainer(container)
        }
    } catch {
        return Text("Preview error: \(error.localizedDescription)")
    }
}
