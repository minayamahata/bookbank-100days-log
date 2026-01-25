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
    
    @Bindable var book: UserBook
    
    @State private var showMemoEditor = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // 表紙画像 + お気に入りボタン（カードの外）
                ZStack(alignment: .topTrailing) {
                    if let imageURL = book.imageURL,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 8)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .frame(height: 200)
                                .overlay {
                                    ProgressView()
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                    } else {
                        // 画像がない場合
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .frame(height: 120)
                            .overlay {
                                VStack {
                                    Image(systemName: "book.closed")
                                        .font(.system(size: 30))
                                        .foregroundColor(.secondary)
                                    Text("画像なし")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                            .padding(.horizontal, 20)
                    }

                    // お気に入りボタン（画像の右上）
                    Button(action: {
                        book.isFavorite.toggle()
                        try? context.save()
                    }) {
                        Image(systemName: book.isFavorite ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundColor(book.isFavorite ? .yellow : .white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding(12)
                }
                
                // タイトル・著者・価格（カードの外、センタリング）
                VStack(spacing: 6) {
                    Text(book.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    if !book.displayAuthor.isEmpty {
                        Text(book.displayAuthor)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let price = book.priceAtRegistration {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(price.formatted())")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("円")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Text(formatDate(book.registeredAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

                // 白いカード（情報部分のみ）
                VStack(alignment: .leading, spacing: 8) {
                    // 詳細情報
                    VStack(alignment: .leading, spacing: 8) {
                        if let passbookName = book.passbook?.name {
                            DetailInfoRow(label: "登録口座", value: passbookName)
                        }

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
                    .font(.caption)

                    Divider()
                        .padding(.vertical, 16)

                    // メモセクション（タップでモーダル表示）
                    Button(action: {
                        print("👆 [メモ] タップされました - モーダルを開く")
                        showMemoEditor = true
                    }) {
                        ZStack(alignment: .topLeading) {
                            // 背景
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                                .frame(minHeight: 120)

                            // メモ表示または プレースホルダー
                            if let memo = book.memo, !memo.isEmpty {
                                Text(memo)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            } else {
                                Text("メモはまだありません")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("本の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                }
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
        .sheet(isPresented: $showMemoEditor) {
            MemoEditorView(memo: Binding(
                get: { book.memo ?? "" },
                set: { _ in }
            )) { newMemo in
                saveMemo(newMemo)
            }
        }
    }
    
    private func deleteBook() {
        context.delete(book)
        try? context.save()
        dismiss()
    }
    
    /// メモを保存（モーダルから呼ばれる）
    private func saveMemo(_ newMemo: String) {
        let startTime = Date()
        print("💾 [メモ] 保存開始: \"\(newMemo)\"")
        
        // ローカルに保存（SwiftData）
        book.memo = newMemo.isEmpty ? nil : newMemo
        
        do {
            try context.save()
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            print("✅ [メモ] 保存完了 (\(String(format: "%.1f", elapsed))ms)")
        } catch {
            print("❌ [メモ] 保存エラー: \(error.localizedDescription)")
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
