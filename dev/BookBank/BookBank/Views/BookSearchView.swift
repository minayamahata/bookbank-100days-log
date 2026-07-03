//
//  BookSearchView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import SwiftUI
import SwiftData

/// 検索結果の並べ替えオプション
enum SortOption: CaseIterable {
    case newestFirst
    case oldestFirst

    var titleKey: LocalizedStringKey {
        switch self {
        case .newestFirst: return "book.sort.newest"
        case .oldestFirst: return "book.sort.oldest"
        }
    }
}

/// 本の検索画面
/// API検索で本を探し、見つからない場合は手動登録に誘導する
struct BookSearchView: View {
    
    // MARK: - Environment
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss

    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(\.floatingButtonState) private var floatingButtonState
    
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
    
    /// 選択中の口座が黒テーマかどうか
    private var isBlackTheme: Bool {
        if let passbook = selectedPassbook {
            return PassbookColor.isBlackTheme(for: passbook, in: customPassbooks)
        }
        return false
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

    /// フィルター適用時の自動追加読み込み中フラグ
    @State private var isAutoLoadingForFilters: Bool = false
    
    /// トースト通知の表示フラグ
    @State private var showToast: Bool = false
    
    /// トーストに表示する金額
    @State private var toastAmount: Int = 0

    /// トーストに表示する金額の通貨（登録元の書籍の通貨）
    @State private var toastCurrency: AppCurrency = .jpy
    
    /// 未登録のみ表示フラグ
    @State private var showUnregisteredOnly: Bool = false

    /// 発行形態フィルター（文庫・単行本・コミック）
    @State private var selectedFormatFilter: BookFormatKind?
    
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
    
    /// 書籍検索サービス（設定に応じて楽天／NAVERを切替）
    private let searchService = BookSearchService()

    /// 現在の検索データベース設定
    @AppStorage(SearchDatabase.storageKey) private var searchDatabaseRaw = SearchDatabase.auto.rawValue

    /// 実際に検索に使われるプロバイダ
    private var activeSearchProvider: SearchProvider {
        (SearchDatabase(rawValue: searchDatabaseRaw) ?? .auto).resolvedProvider
    }

    /// 1ページあたりの取得件数
    private let pageSize = 30

    /// フィルター自動読み込みの最大ページ数
    private let maxAutoLoadPages = 10
    
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
    
    /// 登録済み除外・発行形態フィルターを適用
    private func applyActiveFilters(to results: [RakutenBook]) -> [RakutenBook] {
        var filtered = results
        if showUnregisteredOnly {
            filtered = filtered.filter { !isBookRegistered($0) }
        }
        if let formatFilter = selectedFormatFilter {
            filtered = filtered.filter { $0.formatKind == formatFilter }
        }
        return filtered
    }

    /// フィルタリング・ソート済みの検索結果を更新
    private func updateFilteredResults() {
        var results = applyActiveFilters(to: searchResults)

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

    /// クライアント側フィルターが有効か
    private var hasActiveFilters: Bool {
        showUnregisteredOnly || selectedFormatFilter != nil
    }

    /// 「次の30件」ボタンを表示するか
    private var shouldShowLoadMore: Bool {
        canLoadMore && !isAutoLoadingForFilters
    }

    /// フィルター変更後に結果を更新し、必要なら追加ページを自動読み込み
    private func applyFilterChange() {
        updateFilteredResults()
        loadMoreIfNeededForFilters()
    }

    /// フィルター適用後、表示件数が足りなければ追加ページを自動読み込み
    private func loadMoreIfNeededForFilters(
        consecutiveEmptyPages: Int = 0,
        pagesLoaded: Int = 0
    ) {
        guard hasActiveFilters else { return }
        guard filteredResults.count < pageSize, canLoadMore else { return }
        guard !isLoadingMore, !isSearching, !isAutoLoadingForFilters else { return }
        guard consecutiveEmptyPages < 5, pagesLoaded < maxAutoLoadPages else { return }

        loadMoreResults(
            autoContinue: true,
            consecutiveEmptyPages: consecutiveEmptyPages,
            pagesLoaded: pagesLoaded
        )
    }

    /// 発行形態フィルターのタイトル
    private func formatFilterTitle(_ kind: BookFormatKind) -> LocalizedStringKey {
        switch kind {
        case .bunko: return "book.format.bunko"
        case .tankobon: return "book.format.tankobon"
        case .comic: return "book.format.comic"
        case .other: return "book.format.other"
        }
    }

    /// フィルター用カプセルボタン
    private func filterCapsule(
        _ title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color(.systemBackground) : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary)
                    } else {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// 発行形態フィルターのカプセルボタン
    private func formatFilterCapsule(_ kind: BookFormatKind) -> some View {
        let isSelected = selectedFormatFilter == kind
        return filterCapsule(formatFilterTitle(kind), isSelected: isSelected) {
            selectedFormatFilter = isSelected ? nil : kind
            applyFilterChange()
        }
    }

    /// トーストに表示するメッセージ
    private var toastMessage: String {
        let formattedAmount = MoneyDisplay.formattedPrice(
            amount: toastAmount,
            sourceCurrency: toastCurrency,
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        ) ?? toastAmount.formatted()
        return L10n.format("book.search.deposit_toast", locale: languageManager.resolvedLocale, formattedAmount)
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

    /// 書籍検索API クレジット表記（検索データベースに応じて出典を切替）
    private var apiCreditView: some View {
        let isNaver = activeSearchProvider == .naver
        let creditURL = isNaver
            ? URL(string: "https://developers.naver.com/products/service-api/search/search.md")!
            : URL(string: "https://webservice.rakuten.co.jp/")!
        return Link(destination: creditURL) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(isNaver ? "book.search.api_credit_naver" : "book.search.api_credit")
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索バー（固定位置）
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                
                TextField("book.search.placeholder", text: $searchText)
                    .font(.system(size: 17))
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
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                }
                
                // バーコードスキャンボタン
                Button(action: {
                    isShowingBarcodeScanner = true
                }) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)

            apiCreditView
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            // 検索結果リスト or 空状態
            if isSearching {
                // 検索中の表示
                VStack(spacing: 16) {
                    ProgressView()
                    Text(isSearchingByISBN ? "book.search.barcode_searching" : "book.search.searching")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && hasSearched {
                // 検索結果が0件の場合
                VStack(spacing: 24) {
                    Text("book.search.not_found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("book.search.try_other")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        isShowingManualEntry = true
                    }) {
                        Text("book.search.manual_register")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if hasSearched && !searchResults.isEmpty {
                // 検索結果の表示
                List {
                    // フィルター・口座選択・並べ替え
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                filterCapsule("book.search.exclude_registered", isSelected: showUnregisteredOnly) {
                                    showUnregisteredOnly.toggle()
                                    applyFilterChange()
                                }

                                // NAVERは発行形態（文庫・単行本・コミック）を返さないため非表示
                                if activeSearchProvider != .naver {
                                    formatFilterCapsule(.bunko)
                                    formatFilterCapsule(.tankobon)
                                    formatFilterCapsule(.comic)
                                }
                            }
                            .padding(.vertical, 1)
                        }

                        if isAutoLoadingForFilters {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("book.search.loading_filtered")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(alignment: .center, spacing: 16) {
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
                                        .frame(width: 20, height: 20)

                                        Text("book.search.register_destination")
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)

                                        Text(
                                            L10n.format(
                                                "book.search.register_destination_account",
                                                locale: languageManager.resolvedLocale,
                                                selectedPassbook?.name ?? L10n.string("account.title", locale: languageManager.resolvedLocale)
                                            )
                                        )
                                        .font(.system(size: 14))
                                        .foregroundColor(themeColor)
                                    }
                                    .fixedSize()
                                }
                            }

                            Spacer(minLength: 0)

                            // 並べ替え
                            Menu {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Button(action: {
                                        selectedSortOption = option
                                        updateFilteredResults()
                                    }) {
                                        if selectedSortOption == option {
                                            Label(option.titleKey, systemImage: "checkmark")
                                        } else {
                                            Text(option.titleKey)
                                        }
                                    }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image("icon-sort")
                                        .renderingMode(.template)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.primary)

                                    Text("book.search.sort_label")
                                        .font(.system(size: 10))
                                        .foregroundColor(.primary)
                                }
                                .fixedSize()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 20)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    
                    if filteredResults.isEmpty {
                        Group {
                            if showUnregisteredOnly && searchResults.allSatisfy({ isBookRegistered($0) }) {
                                Text("book.search.all_registered_message")
                            } else {
                                Text("book.search.no_format_match")
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                    }

                    ForEach(filteredResults) { result in
                        let isAlreadyRegistered = isBookRegistered(result)
                        
                        Button(action: {
                            if !isAlreadyRegistered {
                                registerBook(from: result)
                            }
                        }) {
                            BookSearchResultRow(result: result, isRegistered: isAlreadyRegistered, themeColor: themeColor)
                        }
                        .disabled(isAlreadyRegistered)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                    }
                    
                    // リストの最後に「次の30件」ボタン
                    if shouldShowLoadMore {
                        Button(action: {
                            loadMoreResults()
                        }) {
                            HStack {
                                if isLoadingMore {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(isLoadingMore ? "common.loading" : "book.search.load_more")
                            }
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .padding(.vertical, 12)
                        }
                        .disabled(isLoadingMore || isAutoLoadingForFilters)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                    }
                }
                .listStyle(.plain)
            } else if hasSearched && searchResults.isEmpty {
                // 検索結果が0件（フィルター前）
                VStack(spacing: 24) {
                    Text("book.search.not_found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("book.search.try_other")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        isShowingManualEntry = true
                    }) {
                        Text("book.search.manual_register")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // 初期状態（検索前）
                Spacer()
            }
        }
        .navigationTitle("book.search.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            // 開き方（NavigationLink / navPath）に依存せず確実に＋ボタンを隠す
            floatingButtonState.isHidden = true
            // 画面表示時に自動的に検索バーにフォーカス
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            floatingButtonState.isHidden = false
        }
        .overlay(alignment: .top) {
            // トースト通知
            if showToast {
                ToastView(message: toastMessage, themeColor: themeColor, isBlackTheme: isBlackTheme)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            // 手動登録ボタン
            ToolbarItem(placement: .primaryAction) {
                Button("book.search.manual") {
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
        .alert("book.search.not_found.alert_title", isPresented: .constant(errorMessage == "ISBN検索で本が見つかりませんでした")) {
            Button("book.search.manual_register") {
                errorMessage = nil
                isShowingManualEntry = true
            }
            Button("common.close", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text("book.search.isbn_not_found")
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
        selectedFormatFilter = nil
        
        // 検索前にキャッシュを更新
        updateRegisteredISBNsCache()
        
        Task {
            do {
                // 設定に応じた検索データベースで検索（タイトル・著者名両方）
                let results = try await searchService.search(searchText, page: 1)
                searchResults = results
                canLoadMore = results.count >= pageSize
                updateFilteredResults()
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                searchResults = []
                filteredResults = []
                isSearching = false
                #if DEBUG
                print("検索エラー: \(error)")
                #endif
            }
        }
    }
    
    /// 追加で検索結果を読み込む
    private func loadMoreResults(
        autoContinue: Bool = false,
        consecutiveEmptyPages: Int = 0,
        pagesLoaded: Int = 0
    ) {
        guard canLoadMore && !isLoadingMore else { return }
        
        isLoadingMore = true
        if autoContinue {
            isAutoLoadingForFilters = true
        }
        currentPage += 1
        
        Task {
            do {
                let results = try await searchService.search(searchText, page: currentPage)
                
                // 重複を除外して追加
                let existingISBNs = Set(searchResults.map { $0.isbn })
                let newResults = results.filter { !existingISBNs.contains($0.isbn) }
                let filteredCountBefore = filteredResults.count
                
                searchResults.append(contentsOf: newResults)
                canLoadMore = results.count >= pageSize
                updateFilteredResults()
                
                isLoadingMore = false
                if autoContinue {
                    isAutoLoadingForFilters = false
                    let addedCount = filteredResults.count - filteredCountBefore
                    let nextConsecutiveEmptyPages = addedCount == 0 ? consecutiveEmptyPages + 1 : 0
                    loadMoreIfNeededForFilters(
                        consecutiveEmptyPages: nextConsecutiveEmptyPages,
                        pagesLoaded: pagesLoaded + 1
                    )
                }
            } catch {
                #if DEBUG
                print("追加読み込みエラー: \(error)")
                #endif
                isLoadingMore = false
                isAutoLoadingForFilters = false
                canLoadMore = false
            }
        }
    }
    
    /// 検索結果を登録（画像なしでもそのまま登録可能）
    private func registerBook(from result: RakutenBook) {
        saveBook(from: result)
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
            toastCurrency = AppCurrency(code: result.sourceCurrencyCode) ?? .jpy
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
            #if DEBUG
            print("Error saving book: \(error)")
            #endif
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
        selectedFormatFilter = nil
        searchText = isbn  // 検索バーにISBNを表示
        
        // 検索前にキャッシュを更新
        updateRegisteredISBNsCache()
        
        Task {
            do {
                // 設定に応じた検索データベースでISBN検索
                let results = try await searchService.searchByISBN(isbn)
                
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
                            registerBook(from: book)
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
                #if DEBUG
                print("ISBN検索エラー: \(error)")
                #endif
            }
        }
    }
}

// MARK: - ToastView

/// トースト通知ビュー（リキッドガラス）
struct ToastView: View {
    let message: String
    var themeColor: Color = .blue
    var isBlackTheme: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme

    /// テキストの色（黒テーマ+ダークモードでは黒、それ以外は白）
    private var textColor: Color {
        if isBlackTheme && colorScheme == .dark {
            return .black
        }
        return .white
    }

    var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(textColor)
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
                if result.hasCoverImageURL,
                   let imageUrlString = result.largeImageUrl ?? result.mediumImageUrl,
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
                            Text("book.cover_none")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                }
                
                // 登録済みバッジ（画像の下部にオーバーレイ）
                if isRegistered {
                    Text("book.search.registered")
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

                // 発行形態（文庫・単行本・コミック等）
                if let format = result.displayFormat {
                    Text(format)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 価格（楽天は JPY、NAVER は KRW）
            FormattedPriceText(
                amount: result.itemPrice,
                sourceCurrency: AppCurrency(code: result.sourceCurrencyCode) ?? .jpy,
                font: .subheadline
            )
                .foregroundColor(isRegistered ? .secondary : themeColor)
        }
        .opacity(isRegistered ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BookSearchView(passbook: Passbook.createOverall())
    }
    .bookBankPreviewEnvironment()
}
