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
    /// 関連度順（API の取得順を維持。「もっと読み込む」で次のページが末尾に追加される）
    case relevance
    case newestFirst
    case oldestFirst

    var titleKey: LocalizedStringKey {
        switch self {
        case .relevance: return "book.sort.relevance"
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

    /// 検索にヒットした総件数（APIが返す推定値。取得できない場合は nil）
    @State private var totalResultCount: Int?
    
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

    /// 金額手入力の対象書籍（価格情報がない検索結果を登録するとき）
    @State private var priceInputBook: RakutenBook?

    /// 金額手入力欄の入力値（表示通貨のメジャー単位）
    @State private var priceInputText: String = ""
    
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
    
    /// 検索の世代カウンター。新しい検索（キーワード / ISBN）の開始でインクリメントし、
    /// 各非同期フローは開始時の世代を捕捉して、await後に一致する場合のみ結果を反映する（A-1）。
    /// キャンセルは即時性のための補助であり、正しさの保証はこの世代照合が担う。
    @State private var searchGeneration: Int = 0
    
    /// キーワード / ISBN 検索本体のタスクハンドル（新検索開始時にキャンセル）
    @State private var searchTask: Task<Void, Never>?
    
    /// 追加読み込みのタスクハンドル（新検索開始時にキャンセル）
    @State private var loadMoreTask: Task<Void, Never>?
    
    /// 発行形態の後追い補完のタスクハンドル（新検索開始時にキャンセル）
    @State private var enrichTask: Task<Void, Never>?
    
    /// 登録済みISBNのキャッシュ（高速化用）
    @State private var registeredISBNs: Set<String> = []
    
    /// 書籍検索サービス（設定に応じて楽天／NAVERを切替）
    private let searchService = BookSearchService()

    /// 現在の検索データベース設定
    @AppStorage(SearchDatabase.storageKey) private var searchDatabaseRaw = SearchDatabase.deviceDefault.rawValue

    /// 実際に検索に使われるプロバイダ
    private var activeSearchProvider: SearchProvider {
        (SearchDatabase(rawValue: searchDatabaseRaw) ?? .deviceDefault).resolvedProvider
    }

    /// 1ページあたりの取得件数（検索プロバイダごとの1リクエスト取得件数に合わせる）
    /// - 楽天: hits=30/ページ
    /// - Google Books: 1リクエスト最大20件（`GoogleBooksService.pageSize`）
    /// - NAVER: display=20固定・ページング不可（20<30 で「もっと読み込む」を出さない）
    private var pageSize: Int {
        switch activeSearchProvider {
        case .rakuten: return 30
        case .google: return GoogleBooksService.pageSize
        case .naver: return 30
        }
    }

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

    /// 選択中の並べ替えオプションで並べ替える
    /// - Note: 発売日は比較のたびに解析すると重いため、各要素で一度だけ解析してから並べ替える。
    private func sortedByCurrentOption(_ results: [RakutenBook]) -> [RakutenBook] {
        switch selectedSortOption {
        case .relevance:
            // API の取得順（関連度順）をそのまま維持
            return results
        case .newestFirst:
            return sortedByDate(results, ascending: false)
        case .oldestFirst:
            return sortedByDate(results, ascending: true)
        }
    }

    /// 発売日で並べ替える（日付なしは末尾）。日付解析は要素ごとに1回だけ行う。
    private func sortedByDate(_ results: [RakutenBook], ascending: Bool) -> [RakutenBook] {
        return results
            .map { (book: $0, date: SalesDateParser.date(from: $0.salesDate)) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (a?, b?): return ascending ? a < b : a > b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
            .map(\.book)
    }

    /// フィルタリング・ソート済みの検索結果を全件再構築する
    /// （初回検索・並べ替え変更・フィルター変更など、明示的な操作時に使用）
    private func updateFilteredResults() {
        filteredResults = sortedByCurrentOption(applyActiveFilters(to: searchResults))
    }

    /// 追加取得したページを（ページ内で並べ替えたうえで）現在の表示の末尾に追加する
    /// 全体を再ソートしないため、「もっと読み込む」で次のページが常に下に並ぶ。
    private func appendPageToFilteredResults(_ newResults: [RakutenBook]) {
        let page = sortedByCurrentOption(applyActiveFilters(to: newResults))
        let existingIDs = Set(filteredResults.map(\.id))
        filteredResults.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
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

    /// 書籍検索API クレジット表記（検索データベースに応じて出典を切替）
    private var apiCreditView: some View {
        let creditURL: URL
        let creditTextKey: LocalizedStringKey
        switch activeSearchProvider {
        case .naver:
            creditURL = URL(string: "https://developers.naver.com/products/service-api/search/search.md")!
            creditTextKey = "book.search.api_credit_naver"
        case .google:
            creditURL = URL(string: "https://developers.google.com/books")!
            creditTextKey = "book.search.api_credit_google"
        case .rakuten:
            creditURL = URL(string: "https://webservice.rakuten.co.jp/")!
            creditTextKey = "book.search.api_credit"
        }
        return HStack(spacing: 8) {
            Link(destination: creditURL) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text(creditTextKey)
                        .font(.caption2)
                }
                .foregroundColor(.primary)
            }

            Spacer(minLength: 8)

            // 検索にヒットした総件数（クレジット行の右側）
            if hasSearched, let total = totalResultCount, total > 0 {
                Text(
                    L10n.format(
                        "book.search.result_count",
                        locale: languageManager.resolvedLocale,
                        total
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
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

                                // NAVER / Google Books は発行形態（文庫・単行本・コミック）を返さないため非表示
                                if activeSearchProvider == .rakuten {
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
        .alert(
            "book.search.price_input.title",
            isPresented: Binding(
                get: { priceInputBook != nil },
                set: { if !$0 { priceInputBook = nil; priceInputText = "" } }
            ),
            presenting: priceInputBook
        ) { book in
            TextField("book.search.price_input.placeholder", text: $priceInputText)
                .keyboardType(.decimalPad)
            Button("book.search.price_input.register") {
                registerWithManualPrice(book)
            }
            Button("common.cancel", role: .cancel) {
                priceInputBook = nil
                priceInputText = ""
            }
        } message: { _ in
            Text("book.search.price_input.message")
        }
    }
    
    // MARK: - Actions
    
    /// 新しい検索（キーワード / ISBN）の開始時に検索状態を一括リセットする。
    /// キーワード検索・ISBN検索の両方がここを通ることで、リセット漏れ（A-2 / A-7）を防ぐ。
    /// `showUnregisteredOnly` / `selectedSortOption` / `searchText` は意図的に維持する（現状挙動）。
    private func beginNewSearch(canLoadMore: Bool = true) {
        // 世代を進め、進行中の検索・追加読み込み・補完タスクをキャンセルする。
        // キャンセルは補助であり、正しさは各フローの世代照合が担保する（設計メモ 4.1）。
        searchGeneration += 1
        searchTask?.cancel()
        loadMoreTask?.cancel()
        enrichTask?.cancel()
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        currentPage = 1
        self.canLoadMore = canLoadMore
        isLoadingMore = false
        isAutoLoadingForFilters = false
        isSearchingByISBN = false
        searchResults = []
        filteredResults = []
        totalResultCount = nil
        selectedFormatFilter = nil
        
        // 検索前にキャッシュを更新
        updateRegisteredISBNsCache()
    }
    
    /// 検索を実行
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        beginNewSearch()
        // 開始時の世代とリクエスト値をローカルに捕捉（実行時に @State を読み直さない）
        let generation = searchGeneration
        let keyword = searchText
        
        searchTask = Task {
            do {
                // 設定に応じた検索データベースで検索（タイトル・著者名両方）
                let page = try await searchService.search(keyword, page: 1)
                // await をまたいで新しい検索が始まっていたら、結果を捨てて状態に触れない
                guard generation == searchGeneration else { return }
                searchResults = page.books
                totalResultCount = page.totalCount
                canLoadMore = page.hasMorePages
                updateFilteredResults()
                isSearching = false
                // 発行形態は表示をブロックせず後追いで補完する
                enrichFormatsInBackground(for: page.books)
            } catch {
                // 旧世代（キャンセル含む）のエラーは UI に反映しない
                guard generation == searchGeneration else { return }
                errorMessage = error.localizedDescription
                searchResults = []
                filteredResults = []
                totalResultCount = nil
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
        // 開始時の世代・要求ページ・キーワードをローカル捕捉。
        // currentPage は先行インクリメントせず、成功時にのみ requestedPage で確定する（設計メモ 4.2）。
        let generation = searchGeneration
        let requestedPage = currentPage + 1
        let keyword = searchText
        
        loadMoreTask = Task {
            do {
                let page = try await searchService.search(keyword, page: requestedPage)
                // 世代不一致なら結果もフラグも触らない（新検索の beginNewSearch が既にリセット済み）
                guard generation == searchGeneration else { return }
                let results = page.books
                if let total = page.totalCount {
                    totalResultCount = total
                }
                
                // 重複を除外して追加（ISBN で判定。ISBN がない本＝Google Books に多い＝は
                // 空文字が衝突して巻き込まれないよう、常に新規として残す）
                let existingISBNs = Set(searchResults.map { $0.isbn }.filter { !$0.isEmpty })
                let newResults = results.filter { $0.isbn.isEmpty || !existingISBNs.contains($0.isbn) }
                let filteredCountBefore = filteredResults.count
                
                searchResults.append(contentsOf: newResults)
                currentPage = requestedPage
                canLoadMore = page.hasMorePages
                appendPageToFilteredResults(newResults)
                enrichFormatsInBackground(for: newResults)
                
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
                // 世代不一致（キャンセル含む）ならフラグに触らない（新検索が既にリセット済み）
                guard generation == searchGeneration else { return }
                // 一時的な失敗（レート制限など）でページングを恒久停止させない。
                // currentPage は成功時にしか進めていないためロールバック不要。
                // canLoadMore は維持して「もっと読み込む」で再試行できるようにする。
                isLoadingMore = false
                isAutoLoadingForFilters = false
            }
        }
    }

    /// 発行形態（size）を後追いで取得し、表示中の結果へ反映する。
    /// 楽天のみ追加APIが必要（Google／NAVER は size を返さないため何もしない）。
    private func enrichFormatsInBackground(for books: [RakutenBook]) {
        guard activeSearchProvider == .rakuten else { return }
        let targets = books.filter { $0.displayFormat == nil && !$0.isbn.isEmpty }
        guard !targets.isEmpty else { return }
        // 呼び出し元と同じ世代を捕捉。await後に新検索が始まっていたら反映しない。
        let generation = searchGeneration

        enrichTask = Task {
            let enriched = await searchService.enrichFormats(for: targets)
            guard generation == searchGeneration else { return }

            var sizeByISBN: [String: String] = [:]
            for book in enriched where !book.isbn.isEmpty {
                if let size = book.displayFormat {
                    sizeByISBN[book.isbn] = size
                }
            }
            guard !sizeByISBN.isEmpty else { return }

            // 元データにサイズを反映
            searchResults = searchResults.map { book in
                if book.displayFormat == nil, !book.isbn.isEmpty, let size = sizeByISBN[book.isbn] {
                    return book.withSize(size)
                }
                return book
            }

            // 発行形態フィルター中は該当が増えるため再抽出、それ以外は並びを保ったままサイズだけ更新
            if selectedFormatFilter != nil {
                updateFilteredResults()
            } else {
                filteredResults = filteredResults.map { book in
                    if book.displayFormat == nil, !book.isbn.isEmpty, let size = sizeByISBN[book.isbn] {
                        return book.withSize(size)
                    }
                    return book
                }
            }
        }
    }
    
    /// 検索結果を登録（画像なしでもそのまま登録可能）
    /// - Note: 価格情報がない書籍は即登録せず、金額手入力アラートを表示する。
    private func registerBook(from result: RakutenBook) {
        if result.itemPrice == nil {
            priceInputText = ""
            priceInputBook = result
        } else {
            saveBook(from: result)
        }
    }

    /// 手入力した金額（表示通貨建て）で検索結果を登録
    /// - Note: 未入力・数値でない・負数の場合は登録せず、入力アラートを開き直す。
    private func registerWithManualPrice(_ result: RakutenBook) {
        let currency = currencyManager.displayCurrency
        guard let minorUnits = currency.minorUnits(fromInput: priceInputText),
              minorUnits >= 0 else {
            // アラートはボタンタップで自動的に閉じるため、少し待ってから開き直す
            priceInputText = ""
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                priceInputBook = result
            }
            return
        }
        saveBook(from: result, overridePrice: minorUnits, overrideCurrency: currency)
        priceInputBook = nil
        priceInputText = ""
    }

    /// 検索結果から本を保存
    /// - Parameters:
    ///   - overridePrice: 手入力金額（最小通貨単位）。nil の場合は API の価格をそのまま使う。
    ///   - overrideCurrency: 手入力金額の通貨。指定時は保存通貨を上書きする。
    private func saveBook(
        from result: RakutenBook,
        overridePrice: Int? = nil,
        overrideCurrency: AppCurrency? = nil
    ) {
        guard let targetPassbook = selectedPassbook else { return }
        // 二重タップ等での同一書籍の重複登録を防ぐ（ボタンの disabled だけに頼らず保存直前に再チェック）
        guard !isBookRegistered(result) else { return }
        let newBook = result.toUserBook(passbook: targetPassbook)

        // 手入力パス（通貨指定あり）では金額・通貨を上書きする。
        // overridePrice が nil のまま登録された場合は「金額不明」として保存する。
        if let overrideCurrency {
            newBook.price = overridePrice
            newBook.priceAtRegistration = overridePrice
            newBook.currencyCode = overrideCurrency.code
        }

        context.insert(newBook)
        
        do {
            try context.save()
            
            // キャッシュを更新
            if !result.isbn.isEmpty {
                registeredISBNs.insert(result.isbn)
            }
            // 現在の並び順を崩さないよう全体は再構築しない。
            // 「登録済みを除外」中のときだけ、登録した本をその場で取り除く。
            if showUnregisteredOnly {
                filteredResults.removeAll { isBookRegistered($0) }
            }
            
            // トースト通知を表示（画面は閉じない）
            toastAmount = overridePrice ?? result.itemPrice ?? 0
            toastCurrency = overrideCurrency ?? (AppCurrency(code: result.sourceCurrencyCode) ?? .jpy)
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
        // ISBN検索はページングを持たないため canLoadMore=false（設計メモ 4.4節）。
        beginNewSearch(canLoadMore: false)
        searchText = isbn  // 検索バーにISBNを表示
        isSearchingByISBN = true
        // 開始時の世代を捕捉（実行時に @State を読み直さない）
        let generation = searchGeneration
        
        searchTask = Task {
            do {
                // 設定に応じた検索データベースでISBN検索
                let results = try await searchService.searchByISBN(isbn)
                // await をまたいで新しい検索が始まっていたら、結果を捨てて状態に触れない
                guard generation == searchGeneration else { return }
                
                if results.isEmpty {
                    // 本が見つからない場合
                    errorMessage = "ISBN検索で本が見つかりませんでした"
                    searchResults = []
                    filteredResults = []
                } else {
                    searchResults = results
                    totalResultCount = results.count
                    updateFilteredResults()
                    enrichFormatsInBackground(for: results)
                    
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
                // 旧世代（キャンセル含む）のエラーは UI に反映しない
                guard generation == searchGeneration else { return }
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
                    // メモリキャッシュ利用。再検索・再描画時もスピナーを出さず即表示する
                    CachedAsyncImage(url: imageUrl, width: 50, height: 75, contentMode: .fit)
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
            
            // 価格（楽天は JPY、NAVER は KRW、Google は返れば各通貨）
            // 価格情報がない場合（Google Play 非販売など）は「-」を表示し、登録時に手入力する
            if let price = result.itemPrice {
                FormattedPriceText(
                    amount: price,
                    sourceCurrency: AppCurrency(code: result.sourceCurrencyCode) ?? .jpy,
                    font: .subheadline
                )
                    .foregroundColor(isRegistered ? .secondary : themeColor)
            } else {
                Text(verbatim: "-")
                    .font(.subheadline)
                    .foregroundColor(isRegistered ? .secondary : themeColor)
            }
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
