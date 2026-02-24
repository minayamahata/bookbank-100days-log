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
    
    /// カラースキーム（ライト/ダークモード）
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    /// テーマカラーが黒（index 0）かどうか
    private var isBlackTheme: Bool {
        if let colorIndex = passbook.colorIndex {
            return colorIndex == 0
        }
        if let index = customPassbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
            return index == 0
        }
        return false
    }
    
    // MARK: - Initialization
    
    init(passbook: Passbook) {
        self.passbook = passbook
        // registeredAt の降順でソート（新しい本が上に表示される）
        _allUserBooks = Query(sort: \UserBook.registeredAt, order: .reverse)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // 口座情報セクション
                    accountInfoSection
                    
                    // コンテンツカード
                    VStack(alignment: .leading, spacing: 0) {
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
                        
                        // 空きスペースを下に寄せ、入金履歴を常に上に固定
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geometry.size.height)
                    .background(Color(.systemBackground))
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
        }
        .id(passbook.persistentModelID) // 口座が変わったら強制的にViewを再生成
        .background(ThemedBackgroundView(themeColor: themeColor, isBlackTheme: isBlackTheme))
        .navigationTitle("通帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    // MARK: - Account Info Section
    
    private var accountInfoSection: some View {
        VStack(spacing: 0) {
            Text("\(todayString) 時点")
                .font(.footnote)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.bottom, 32)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(totalValue.formatted())")
                    .font(.system(size: 48, weight: .medium))
                Text("円")
                    .font(.system(size: 18, weight: .medium))
            }
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .white, location: 0),
                        Gradient.Stop(color: .white, location: 0.6),
                        Gradient.Stop(color: themeColor.opacity(0.1), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Text("登録書籍: \(bookCount)冊")
                .font(.subheadline)
                .foregroundColor(.white)
            
            // アクションボタン
            HStack(spacing: 12) {
                NavigationLink(destination: BookSearchView(passbook: passbook, allowPassbookChange: true)) {
                    Text("本を登録する")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark && isBlackTheme ? .black : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.tint(colorScheme == .dark && isBlackTheme ? .white : themeColor))
                        .clipShape(Capsule())
                }
                
                NavigationLink(destination: BookshelfView(passbook: passbook)) {
                    Text("本棚を見る")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark && isBlackTheme ? .black : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.tint(colorScheme == .dark && isBlackTheme ? .white : themeColor))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 44)
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        LazyVStack(spacing: 6) {
            if userBooks.isEmpty {
                Text("最近どんな本を読んだ？")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(userBooks) { book in
                    NavigationLink(destination: UserBookDetailView(book: book)) {
                        HStack(alignment: .center, spacing: 12) {
                            // サムネイル
                            if let imageURL = book.imageURL,
                               let url = URL(string: imageURL) {
                                CachedAsyncImage(
                                    url: url,
                                    width: 47,
                                    height: 70
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 47, height: 70)
                                    .overlay {
                                        Image(systemName: "book.closed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDate(book.registeredAt))
                                    .font(.system(size: 10))
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
                                    Text("円")
                                        .font(.caption2)
                                }
                                .foregroundColor(themeColor)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : themeColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
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

