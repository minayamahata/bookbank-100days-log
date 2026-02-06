//
//  BookSearchView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import SwiftUI
import SwiftData

/// 検索結果の並べ替えオプション
enum SortOption: String, CaseIterable {
    case newestFirst = "発売日が新しい順"
    case oldestFirst = "発売日が古い順"
}

/// 本の検索画面
/// API検索で本を探し、見つからない場合は手動登録に誘導する
struct BookSearchView: View {
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// 登録先の口座（初期値）
    let passbook: Passbook
    
    /// 口座選択を許可するかどうか
    let allowPassbookChange: Bool
    
    // MARK: - SwiftData Query
    
    /// 全ての登録済み書籍を取得
    @Query private var allUserBooks: [UserBook]
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// カスタム口座のみ取得
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }

    /// 選択中の口座のテーマカラー
    private var themeColor: Color {
        if let passbook = selectedPassbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
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

    /// 選択中の並べ替えオプション
    @State private var selectedSortOption: SortOption = .newestFirst
    
    /// 選択中の口座
    @State private var selectedPassbook: Passbook?
    
    /// 検索バーのフォーカス状態
    @FocusState private var isSearchFocused: Bool
    
    /// バーコードスキャナーの表示フラグ
    @State private var isShowingBarcodeScanner: Bool = false
    
    /// ISBN検索中フラグ
    @State private var isSearchingByISBN: Bool = false
    
    /// フィルタリング・ソート済みの検索結果（キャッシュ）
    @State private var filteredResults: [RakutenBook] = []
    
    /// 登録済みISBNのキャッシュ（高速化用）
    @State private var registeredISBNs: Set<String> = []
    
    /// 楽天Books APIサービス
    private let rakutenService = RakutenBooksService()
    
    // MARK: - Initialization
    
    init(passbook: Passbook, allowPassbookChange: Bool = false) {
        self.passbook = passbook
        self.allowPassbookChange = allowPassbookChange
        _selectedPassbook = State(initialValue: passbook)
    }
    
    // MARK: - Cache Update
    
    /// 登録済みISBNキャッシュを更新
    private func updateRegisteredISBNsCache() {
        registeredISBNs = Set(allUserBooks.compactMap { $0.isbn }.filter { !$0.isEmpty })
    }
    
    /// フィルタリング・ソート済みの検索結果を更新
    private func updateFilteredResults() {
        var results = showUnregisteredOnly
            ? searchResults.filter { !isBookRegistered($0) }
            : searchResults

        switch selectedSortOption {
        case .newestFirst:
            results.sort { a, b in
                let dateA = parseSalesDate(a.salesDate)
                let dateB = parseSalesDate(b.salesDate)
                switch (dateA, dateB) {
                case let (da?, db?): return da > db
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        case .oldestFirst:
            results.sort { a, b in
                let dateA = parseSalesDate(a.salesDate)
                let dateB = parseSalesDate(b.salesDate)
                switch (dateA, dateB) {
                case let (da?, db?): return da < db
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        }

        filteredResults = results
    }

    /// salesDateの文字列をDateに変換
    private func parseSalesDate(_ dateString: String) -> Date? {
        // 不要な文字を除去（「頃」「上旬」「中旬」「下旬」「以降」「予定」など）
        let cleanedString = dateString
            .replacingOccurrences(of: "頃", with: "")
            .replacingOccurrences(of: "上旬", with: "")
            .replacingOccurrences(of: "中旬", with: "")
            .replacingOccurrences(of: "下旬", with: "")
            .replacingOccurrences(of: "以降", with: "")
            .replacingOccurrences(of: "予定", with: "")
            .replacingOccurrences(of: "初旬", with: "")
            .replacingOccurrences(of: "末", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")

        // "2012年09月07日" 形式
        formatter.dateFormat = "yyyy年MM月dd日"
        if let date = formatter.date(from: cleanedString) { return date }

        // "2012年09月" 形式
        formatter.dateFormat = "yyyy年MM月"
        if let date = formatter.date(from: cleanedString) { return date }

        // "2012年" 形式
        formatter.dateFormat = "yyyy年"
        if let date = formatter.date(from: cleanedString) { return date }
        
        // 数字だけ抽出してみる（例：「2012年09月07日発売」→「20120907」）
        let numbers = cleanedString.filter { $0.isNumber }
        if numbers.count >= 8 {
            // YYYYMMDD形式
            formatter.dateFormat = "yyyyMMdd"
            if let date = formatter.date(from: String(numbers.prefix(8))) { return date }
        } else if numbers.count >= 6 {
            // YYYYMM形式
            formatter.dateFormat = "yyyyMM"
            if let date = formatter.date(from: String(numbers.prefix(6))) { return date }
        } else if numbers.count >= 4 {
            // YYYY形式
            formatter.dateFormat = "yyyy"
            if let date = formatter.date(from: String(numbers.prefix(4))) { return date }
        }

        return nil
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー（固定位置）
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("タイトルまたは著者名", text: $searchText)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                // バーコードスキャンボタン
                Button(action: {
                    isShowingBarcodeScanner = true
                }) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 検索結果リスト or 空状態
            if isSearching {
                // 検索中の表示
                VStack(spacing: 16) {
                    ProgressView()
                    Text(isSearchingByISBN ? "バーコードで検索中..." : "検索中...")
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
            } else if !filteredResults.isEmpty {
                // 検索結果の表示
                List {
                    // フィルター・口座選択・並べ替えオプション（1列）
                    HStack {
                        // 登録済みを除外
                        Toggle(isOn: $showUnregisteredOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: showUnregisteredOnly ? "checkmark.square.fill" : "square")
                                    .foregroundColor(showUnregisteredOnly ? .blue : .secondary)
                                Text("登録済みを除外")
                                    .font(.system(size: 13))
                            }
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .onChange(of: showUnregisteredOnly) {
                            updateFilteredResults()
                        }

                        Spacer()
                        
                        // 口座選択（allowPassbookChangeがtrueの場合のみ表示）
                        if allowPassbookChange {
                            Menu {
                                ForEach(customPassbooks) { passbook in
                                    Button(action: {
                                        selectedPassbook = passbook
                                    }) {
                                        if selectedPassbook?.persistentModelID == passbook.persistentModelID {
                                            Label(passbook.name, systemImage: "checkmark")
                                        } else {
                                            Text(passbook.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    ZStack {
                                        Image("icon-tab-account-fill")
                                            .renderingMode(.template)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .foregroundColor(themeColor.opacity(0.1))
                                        
                                        Image("icon-tab-account")
                                            .renderingMode(.template)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .foregroundColor(themeColor)
                                    }
                                    .frame(width: 16, height: 16)
                                    
                                    Text(selectedPassbook?.name ?? "口座")
                                        .font(.system(size: 13))
                                        .foregroundColor(themeColor)
                                }
                                .fixedSize()
                            }
                        }

                        // 並べ替え
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    selectedSortOption = option
                                    updateFilteredResults()
                                }) {
                                    if selectedSortOption == option {
                                        Label(option.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(option.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image("icon-sort")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(.primary)
                                
                                Text(selectedSortOption.rawValue)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                            }
                            .fixedSize()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.appGroupedBackground)
                    .listRowSeparator(.hidden)
                    
                    ForEach(filteredResults) { result in
                        let isAlreadyRegistered = isBookRegistered(result)
                        
                        Button(action: {
                            if !isAlreadyRegistered {
                                saveBook(from: result)
                            }
                        }) {
                            BookSearchResultRow(result: result, isRegistered: isAlreadyRegistered, themeColor: themeColor)
                        }
                        .disabled(isAlreadyRegistered)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                    }
                    
                    // リストの最後に「次の30件」ボタン
                    if canLoadMore {
                        Button(action: {
                            loadMoreResults()
                        }) {
                            HStack {
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(isLoadingMore ? "読み込み中..." : "次の30件を読み込む")
                            }
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .padding(.vertical, 12)
                        }
                        .disabled(isLoadingMore)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                    }
                }
                .listStyle(.plain)
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
            } else if hasSearched && !searchResults.isEmpty && filteredResults.isEmpty {
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
                Spacer()
            }
        }
        .navigationTitle("本を検索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 画面表示時に自動的に検索バーにフォーカス
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
        }
        .overlay(alignment: .top) {
            // トースト通知
            if showToast {
                ToastView(amount: toastAmount, themeColor: themeColor)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            // 手動登録ボタン
            ToolbarItem(placement: .primaryAction) {
                Button("手動登録") {
                    isShowingManualEntry = true
                }
                .font(.footnote)
                .foregroundColor(.primary)
            }
        }
        .sheet(isPresented: $isShowingManualEntry) {
            if let targetPassbook = selectedPassbook {
                AddBookView(passbook: targetPassbook, allowPassbookChange: allowPassbookChange) {
                    // 手動登録が完了したら検索画面も閉じて通帳画面に戻る
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingBarcodeScanner) {
            BarcodeScannerView { isbn in
                // バーコードからISBNを取得したらAPIで検索
                searchByISBN(isbn)
            }
        }
        .alert("本が見つかりません", isPresented: .constant(errorMessage == "ISBN検索で本が見つかりませんでした")) {
            Button("手動で登録") {
                errorMessage = nil
                isShowingManualEntry = true
            }
            Button("閉じる", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text("このISBNの本が楽天ブックスに登録されていません。手動で登録してください。")
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
        filteredResults = []
        
        // 検索前にキャッシュを更新
        updateRegisteredISBNsCache()
        
        Task {
            do {
                // 楽天Books APIで検索（タイトル・著者名両方）
                let results = try await rakutenService.search(searchText, page: 1)
                searchResults = results
                canLoadMore = results.count >= 30
                updateFilteredResults()
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                searchResults = []
                filteredResults = []
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
                updateFilteredResults()
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
        guard let targetPassbook = selectedPassbook else { return }
        let newBook = result.toUserBook(passbook: targetPassbook)
        
        context.insert(newBook)
        
        do {
            try context.save()
            
            // キャッシュを更新
            if !result.isbn.isEmpty {
                registeredISBNs.insert(result.isbn)
            }
            updateFilteredResults()
            
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
    
    /// 本が既に登録済みかチェック（全口座を対象）
    private func isBookRegistered(_ book: RakutenBook) -> Bool {
        // ISBNで判定（キャッシュを使用して高速化）
        if !book.isbn.isEmpty {
            return registeredISBNs.contains(book.isbn)
        }
        // ISBNがない場合のみ従来のループ（稀なケース）
        return allUserBooks.contains { userBook in
            userBook.title == book.title && userBook.author == book.author
        }
    }
    
    /// ISBNで本を検索
    private func searchByISBN(_ isbn: String) {
        isSearching = true
        hasSearched = true
        errorMessage = nil
        isSearchingByISBN = true
        searchResults = []
        filteredResults = []
        searchText = isbn  // 検索バーにISBNを表示
        
        // 検索前にキャッシュを更新
        updateRegisteredISBNsCache()
        
        Task {
            do {
                // 楽天Books APIでISBN検索
                let results = try await rakutenService.searchByISBN(isbn)
                
                if results.isEmpty {
                    // 本が見つからない場合
                    errorMessage = "ISBN検索で本が見つかりませんでした"
                    searchResults = []
                    filteredResults = []
                } else {
                    searchResults = results
                    updateFilteredResults()
                    
                    // 1件だけの場合は自動的に詳細を表示（登録済みでない場合のみ）
                    if results.count == 1, let book = results.first {
                        if !isBookRegistered(book) {
                            // 自動的に登録
                            saveBook(from: book)
                        }
                    }
                }
                
                isSearching = false
                isSearchingByISBN = false
            } catch {
                errorMessage = "検索中にエラーが発生しました: \(error.localizedDescription)"
                searchResults = []
                filteredResults = []
                isSearching = false
                isSearchingByISBN = false
                print("ISBN検索エラー: \(error)")
            }
        }
    }
}

// MARK: - ToastView

/// トースト通知ビュー（リキッドガラス）
struct ToastView: View {
    let amount: Int
    var themeColor: Color = .blue

    var body: some View {
        Text("\(amount.formatted())円 入金しました！")
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(themeColor))
            .clipShape(Capsule())
    }
}

// MARK: - BookSearchResultRow

/// 検索結果の1行表示
struct BookSearchResultRow: View {
    let result: RakutenBook
    let isRegistered: Bool
    var themeColor: Color = .blue
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // サムネイル画像（登録済みバッジをオーバーレイ）
            ZStack(alignment: .bottom) {
                if let imageUrlString = result.largeImageUrl ?? result.mediumImageUrl,
                   let imageUrl = URL(string: imageUrlString) {
                    AsyncImage(url: imageUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                            }
                    }
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    // 画像がない場合
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 75)
                        .overlay {
                            Image(systemName: "book")
                                .foregroundColor(.gray)
                        }
                }
                
                // 登録済みバッジ（画像の下部にオーバーレイ）
                if isRegistered {
                    Text("登録済み")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(Color.black)
                }
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .opacity(isRegistered ? 0.6 : 1.0)
            
            VStack(alignment: .leading, spacing: 2) {
                // タイトル
                Text(result.title)
                    .font(.subheadline)
                    .foregroundColor(isRegistered ? .secondary : .primary)
                    .lineLimit(2)
                
                // 著者名
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 価格
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(result.itemPrice.formatted())")
                    .font(.subheadline)
                Text("円")
                    .font(.caption2)
            }
            .foregroundColor(isRegistered ? .secondary : themeColor)
        }
        .opacity(isRegistered ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    BookSearchView(passbook: Passbook.createOverall())
        .modelContainer(for: [Passbook.self, UserBook.self, Subscription.self])
}
