//
//  PassbookDetailView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/14.
//

import SwiftUI
import SwiftData

/// 通帳画面
/// 選択した口座の詳細と、登録されている書籍の一覧を表示
struct PassbookDetailView: View {
    
    // MARK: - Properties
    
    /// 表示対象の口座
    let passbook: Passbook
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// 画面を閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// この口座に紐づく書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// この口座に紐づく書籍のみをフィルタリング
    private var userBooks: [UserBook] {
        allUserBooks.filter { book in
            book.passbook?.persistentModelID == passbook.persistentModelID
        }
    }
    
    /// 合計金額
    private var totalValue: Int {
        passbook.totalValue
    }
    
    /// 今日の日付文字列
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    /// 登録書籍数
    private var bookCount: Int {
        passbook.bookCount
    }
    
    /// カスタム口座のリスト
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    /// この口座のテーマカラー
    private var themeColor: Color {
        PassbookColor.color(for: passbook, in: customPassbooks)
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 口座情報セクション
                accountInfoSection
                
                // コンテンツカード
                VStack(spacing: 0) {
                    // ヘッダー
                    HStack {
                        Text("入金履歴")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                    
                    // 書籍リスト
                    listContent
                }
                .background(Color(UIColor.systemBackground))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 40,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 40
                    )
                )
            }
        }
        .id(passbook.persistentModelID) // 口座が変わったら強制的にViewを再生成
        .background(themeColor.opacity(0.1).ignoresSafeArea())
        .navigationTitle("通帳")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Account Info Section
    
    private var accountInfoSection: some View {
        VStack(spacing: 8) {
            Text("\(todayString) 時点")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.bottom, 32)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(totalValue.formatted())")
                    .font(.system(size: 32, weight: .bold))
                Text("円")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(themeColor)

            Text("登録書籍: \(bookCount)冊")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 60)
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        LazyVStack(spacing: 0) {
            if userBooks.isEmpty {
                VStack(spacing: 30) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("まだ本が登録されていません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(userBooks) { book in
                    NavigationLink(destination: UserBookDetailView(book: book)) {
                        HStack(alignment: .center, spacing: 12) {
                            // サムネイル
                            if let imageURL = book.imageURL,
                               let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 50, height: 70)
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 70)
                                    .overlay {
                                        Image(systemName: "book.closed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDate(book.registeredAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(book.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                if !book.displayAuthor.isEmpty {
                                    Text(book.displayAuthor)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if let price = book.priceAtRegistration {
                                HStack(alignment: .lastTextBaseline, spacing: 1) {
                                    Text("\(price.formatted())")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("円")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(themeColor)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 100)
    }
    
    // MARK: - Actions
    
    /// 日付をYYYY.MM.DD形式でフォーマット
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return NavigationStack {
        PassbookDetailView(passbook: passbook)
    }
    .modelContainer(container)
}

