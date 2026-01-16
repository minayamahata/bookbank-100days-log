//
//  BookSearchView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import SwiftUI
import SwiftData

/// 本の検索画面
/// API検索で本を探し、見つからない場合は手動登録に誘導する
struct BookSearchView: View {
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// 登録先の口座
    let passbook: Passbook
    
    // MARK: - SwiftData Query
    
    /// 全ての登録済み書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    // MARK: - State
    
    /// 検索キーワード
    @State private var searchText: String = ""
    
    /// 検索結果
    @State private var searchResults: [RakutenBook] = []
    
    /// 検索中フラグ
    @State private var isSearching: Bool = false
    
    /// 手動登録画面の表示フラグ
    @State private var isShowingManualEntry: Bool = false
    
    /// 検索を実行したかどうか（検索結果が0件かどうかを判定するため）
    @State private var hasSearched: Bool = false
    
    /// エラーメッセージ
    @State private var errorMessage: String?
    
    /// 現在のページ番号
    @State private var currentPage: Int = 1
    
    /// さらに読み込み可能かどうか
    @State private var canLoadMore: Bool = true
    
    /// 追加読み込み中フラグ
    @State private var isLoadingMore: Bool = false
    
    /// トースト通知の表示フラグ
    @State private var showToast: Bool = false
    
    /// トーストに表示する金額
    @State private var toastAmount: Int = 0
    
    /// 未登録のみ表示フラグ
    @State private var showUnregisteredOnly: Bool = false
    
    /// 楽天Books APIサービス
    private let rakutenService = RakutenBooksService()
    
    // MARK: - Computed Properties
    
    /// フィルタリングされた検索結果
    private var filteredSearchResults: [RakutenBook] {
        if showUnregisteredOnly {
            return searchResults.filter { !isBookRegistered($0) }
        }
        return searchResults
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // フィルターオプション
                if hasSearched && !searchResults.isEmpty {
                    HStack {
                        Toggle(isOn: $showUnregisteredOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: showUnregisteredOnly ? "checkmark.square.fill" : "square")
                                    .foregroundColor(showUnregisteredOnly ? .blue : .secondary)
                                Text("未登録のみを表示")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }
                
                // 検索結果リスト or 空状態
                if isSearching {
                    // 検索中の表示
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("検索中...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && hasSearched {
                    // 検索結果が0件の場合
                    VStack(spacing: 24) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("本が見つかりませんでした")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("別のキーワードで検索するか、\n手動で登録してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // 手動登録ボタン
                        Button(action: {
                            isShowingManualEntry = true
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("手動で登録する")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if !filteredSearchResults.isEmpty {
                    // 検索結果の表示
                    List {
                        ForEach(filteredSearchResults) { result in
                            let isAlreadyRegistered = isBookRegistered(result)
                            
                            Button(action: {
                                if !isAlreadyRegistered {
                                    saveBook(from: result)
                                }
                            }) {
                                BookSearchResultRow(result: result, isRegistered: isAlreadyRegistered)
                            }
                            .disabled(isAlreadyRegistered)
                            .onAppear {
                                // 最後の要素が表示されたら次のページを読み込む
                                if result.id == filteredSearchResults.last?.id && canLoadMore && !isLoadingMore {
                                    loadMoreResults()
                                }
                            }
                        }
                        
                        // 追加読み込み中のインジケーター
                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        }
                    }
                } else if hasSearched && searchResults.isEmpty {
                    // 検索結果が0件（フィルター前）
                    VStack(spacing: 24) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("本が見つかりませんでした")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("別のキーワードで検索するか、\n手動で登録してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // 手動登録ボタン
                        Button(action: {
                            isShowingManualEntry = true
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("手動で登録する")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if hasSearched && !searchResults.isEmpty && filteredSearchResults.isEmpty {
                    // フィルター適用後に0件
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("すべて登録済みです")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("この検索結果の本はすべて登録されています")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 初期状態（検索前）
                    VStack(spacing: 16) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("本のタイトルや著者名で検索")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("見つからない場合は手動で登録できます")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
        .navigationTitle("本を検索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "タイトルまたは著者名")
        .onSubmit(of: .search) {
            performSearch()
        }
        .overlay(alignment: .top) {
            // トースト通知
            if showToast {
                ToastView(amount: toastAmount)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
                // キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                // 手動登録ボタン（常に表示）
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isShowingManualEntry = true
                    }) {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $isShowingManualEntry) {
                AddBookView(passbook: passbook) {
                    // 手動登録が完了したら検索画面も閉じて通帳画面に戻る
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// 検索を実行
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        currentPage = 1
        canLoadMore = true
        searchResults = []
        
        Task {
            do {
                // 楽天Books APIで検索（タイトル・著者名両方）
                let results = try await rakutenService.search(searchText, page: 1)
                searchResults = results
                canLoadMore = results.count >= 30
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                searchResults = []
                isSearching = false
                print("検索エラー: \(error)")
            }
        }
    }
    
    /// 追加で検索結果を読み込む
    private func loadMoreResults() {
        guard canLoadMore && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        Task {
            do {
                let results = try await rakutenService.search(searchText, page: currentPage)
                
                // 重複を除外して追加
                let existingISBNs = Set(searchResults.map { $0.isbn })
                let newResults = results.filter { !existingISBNs.contains($0.isbn) }
                
                searchResults.append(contentsOf: newResults)
                canLoadMore = results.count >= 30
                isLoadingMore = false
            } catch {
                print("追加読み込みエラー: \(error)")
                isLoadingMore = false
                canLoadMore = false
            }
        }
    }
    
    /// 検索結果から本を保存
    private func saveBook(from result: RakutenBook) {
        let newBook = result.toUserBook(passbook: passbook)
        
        context.insert(newBook)
        
        do {
            try context.save()
            
            // トースト通知を表示（画面は閉じない）
            toastAmount = result.itemPrice
            withAnimation {
                showToast = true
            }
            
            // 2秒後にトーストを非表示
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    showToast = false
                }
            }
        } catch {
            print("Error saving book: \(error)")
        }
    }
    
    /// 本が既に登録済みかチェック
    private func isBookRegistered(_ book: RakutenBook) -> Bool {
        // ISBNで判定
        if !book.isbn.isEmpty {
            return allUserBooks.contains { $0.isbn == book.isbn }
        }
        // ISBNがない場合はタイトルと著者で判定
        return allUserBooks.contains { userBook in
            userBook.title == book.title && userBook.author == book.author
        }
    }
}

// MARK: - ToastView

/// トースト通知ビュー
struct ToastView: View {
    let amount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "yensign.circle.fill")
                .foregroundColor(.white)
                .font(.title3)
            
            Text("¥\(amount.formatted()) 入金しました！")
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.green)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - BookSearchResultRow

/// 検索結果の1行表示
struct BookSearchResultRow: View {
    let result: RakutenBook
    let isRegistered: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // サムネイル画像（大サイズを縮小表示）
            if let imageUrlString = result.largeImageUrl ?? result.mediumImageUrl,
               let imageUrl = URL(string: imageUrlString) {
                AsyncImage(url: imageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(width: 50, height: 70)
                .cornerRadius(4)
                .opacity(isRegistered ? 0.4 : 1.0)
            } else {
                // 画像がない場合
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 70)
                    .overlay {
                        Image(systemName: "book")
                            .foregroundColor(.gray)
                    }
                    .opacity(isRegistered ? 0.4 : 1.0)
            }
            
            // 書籍情報
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(isRegistered ? .secondary : .primary)
                    .lineLimit(2)
                
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Text("¥\(result.itemPrice.formatted())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isRegistered ? .secondary : .blue)
                    
                    if isRegistered {
                        Text("登録済み")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isRegistered ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    BookSearchView(passbook: Passbook.createOverall())
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
