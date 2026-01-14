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
    
    // MARK: - State
    
    /// 検索キーワード
    @State private var searchText: String = ""
    
    /// 検索結果
    @State private var searchResults: [BookSearchResult] = []
    
    /// 検索中フラグ
    @State private var isSearching: Bool = false
    
    /// 手動登録画面の表示フラグ
    @State private var isShowingManualEntry: Bool = false
    
    /// 検索を実行したかどうか（検索結果が0件かどうかを判定するため）
    @State private var hasSearched: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                } else if !searchResults.isEmpty {
                    // 検索結果の表示
                    List(searchResults) { result in
                        Button(action: {
                            saveBook(from: result)
                        }) {
                            BookSearchResultRow(result: result)
                        }
                    }
                } else {
                    // 初期状態（検索前）
                    VStack(spacing: 16) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("本のタイトルやISBNで検索")
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
            .searchable(text: $searchText, prompt: "タイトルまたはISBN")
            .onSubmit(of: .search) {
                performSearch()
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
        
        // TODO: API連携を実装
        // 現時点ではモックデータで動作確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // ここに実際のAPI呼び出しを実装
            searchResults = [] // 空の結果（後でAPI実装時に置き換え）
            isSearching = false
        }
    }
    
    /// 検索結果から本を保存
    private func saveBook(from result: BookSearchResult) {
        let newBook = UserBook(
            title: result.title,
            author: result.author,
            isbn: result.isbn,
            publisher: result.publisher,
            publishedYear: result.publishedYear,
            price: result.price,
            thumbnailURL: result.thumbnailURL,
            source: .api,
            passbook: passbook
        )
        
        context.insert(newBook)
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("Error saving book: \(error)")
        }
    }
}

// MARK: - BookSearchResult Model

/// 検索結果の書籍情報（APIレスポンス用）
struct BookSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let author: String?
    let isbn: String?
    let publisher: String?
    let publishedYear: Int?
    let price: Int?
    let thumbnailURL: String?
}

// MARK: - BookSearchResultRow

/// 検索結果の1行表示
struct BookSearchResultRow: View {
    let result: BookSearchResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // サムネイル（将来的に画像表示）
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 70)
                .overlay {
                    Image(systemName: "book")
                        .foregroundColor(.gray)
                }
            
            // 書籍情報
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let author = result.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let price = result.price {
                    Text("¥\(price.formatted())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    BookSearchView(passbook: Passbook.createOverall())
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
