//
//  UserBookDetailView.swift
//  BookBank
//
//  Created on 2026/01/17
//

import SwiftUI

struct UserBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.floatingButtonState) private var floatingButtonState
    @Environment(LanguageManager.self) private var languageManager
    @Environment(AppRepositories.self) private var repos

    /// 表示対象の本（値型のコピー）。
    /// 生の `@Model` を保持しないため、表示中に元レコードが削除されても getter がトラップしない
    /// （設計メモ 8.4節のクラッシュに対する構造的対策）。
    let initialBook: BookDTO

    /// ストリームで追従する現在値。削除後は最後に観測した値を保持し続ける（読み取りは常に安全）。
    @State private var book: BookDTO

    @State private var allPassbooks: [PassbookDTO] = []
    /// 口座ストリーム到達済みか（色のリスト位置フォールバックは全件が揃ってからのみ有効）
    @State private var hasLoadedPassbooks = false

    init(book: BookDTO) {
        self.initialBook = book
        _book = State(initialValue: book)
    }

    @State private var showMemoEditor = false
    @State private var showDeleteAlert = false
    @State private var showEditBook = false

    /// 詳細パネル（ボトムシート）のスナップ位置
    private enum SheetDetent {
        case collapsed
        case expanded
    }

    @State private var sheetDetent: SheetDetent = .collapsed
    @State private var dragOffset: CGFloat = 0

    /// カバー画像の高さ
    private let coverHeight: CGFloat = 370
    /// 折りたたみ時のシート上端位置（カバーを大きく見せる）
    private let collapsedTop: CGFloat = 330
    /// 展開時のシート上端位置（カバー上部だけ覗かせる）
    private let expandedTop: CGFloat = 110

    /// 現在のシート上端位置（ドラッグ量を反映しつつ範囲内に収める）
    private var currentSheetTop: CGFloat {
        let base = sheetDetent == .collapsed ? collapsedTop : expandedTop
        return min(max(base + dragOffset, expandedTop), collapsedTop)
    }

    /// 口座一覧。ストリーム未到達の初回フレームは同期スナップショットで補う
    /// （ステップ3の `@Model` フォールバックの置き換え・色の1フレーム差を作らない）
    private var resolvedPassbooks: [PassbookDTO] {
        hasLoadedPassbooks ? allPassbooks : repos.passbooks.latestSnapshot
    }

    private var customPassbooks: [PassbookDTO] {
        resolvedPassbooks.filter { $0.type == .custom && $0.isActive }
    }

    private var bookPassbookDTO: PassbookDTO? {
        guard let passbookId = book.passbookId else { return nil }
        return customPassbooks.first(where: { $0.id == passbookId })
            ?? resolvedPassbooks.first(where: { $0.id == passbookId })
    }

    private var themeColor: Color {
        if let passbook = bookPassbookDTO {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }

    private var isBlackTheme: Bool {
        if let passbook = bookPassbookDTO {
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

    /// メモ内のつながりの色。黒テーマ＋ダークモードではテーマ色が背景に沈むため白へ退避する
    private var linkColor: Color {
        if colorScheme == .dark && isBlackTheme {
            return .white
        }
        return themeColor
    }

    var body: some View {
        let _ = languageManager.currentLanguage

        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 背景：本のカバー（固定）
                coverSection(screenWidth: geometry.size.width)

                // ハンドルでドラッグして開閉できる詳細パネル
                // 高さは画面いっぱいで固定し、位置(offset)だけ動かすことで
                // ドラッグ中の再レイアウトを避けて滑らかにする
                bookSheet
                    .frame(height: geometry.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                    .offset(y: currentSheetTop)
                    .animation(.spring(response: 0.35, dampingFraction: 0.88), value: sheetDetent)
                    .transaction { transaction in
                        if dragOffset != 0 {
                            transaction.animation = nil
                        }
                    }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.appGroupedBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image("icon-delete")
                }
                .tint(.white)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: {
                showEditBook = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                    Text("common.edit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(colorScheme == .dark && isBlackTheme ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassEffect(.regular.tint(colorScheme == .dark && isBlackTheme ? .white : themeColor))
                .clipShape(Capsule())
            }
            .padding(.trailing, 16)
            .padding(.bottom, 22)
        }
        .alert("book.delete.title", isPresented: $showDeleteAlert) {
            Button("common.cancel", role: .cancel) { }
            Button("common.delete", role: .destructive) {
                deleteBook()
            }
        } message: {
            Text(L10n.format("book.delete.message", locale: languageManager.resolvedLocale, book.title))
        }
        .tint(.primary)
        .sheet(isPresented: $showEditBook) {
            EditBookView(book: book)
        }
        .sheet(isPresented: $showMemoEditor) {
            MemoEditorView(
                memo: Binding(
                    get: { book.memo ?? "" },
                    set: { _ in }
                ),
                    allowsLinks: true,
                    accentColor: linkColor
            ) { newMemo in
                saveMemo(newMemo)
            }
        }
        .onAppear { floatingButtonState.isHidden = true }
        .onDisappear { floatingButtonState.isHidden = false }
        .task {
            for await value in repos.passbooks.observePassbooks() {
                allPassbooks = value
                hasLoadedPassbooks = true
            }
        }
        .task(id: initialBook.id) {
            // SwiftUI が同一identityのViewを別の本で再利用した場合に @State が前の本のまま
            // 残らないよう、購読前に必ず引数の値へ合わせる
            if book.id != initialBook.id { book = initialBook }
            // 以後は id で observeBooks から解決し、他画面での編集を追従する。
            // 削除されたら最後に観測した値を保持する（値型のコピーなので読み取りは常に安全＝設計メモ 8.4節）
            for await books in repos.books.observeBooks() {
                if let updated = books.first(where: { $0.id == initialBook.id }) {
                    book = updated
                }
            }
        }
    }

    // MARK: - 詳細パネル（ドラッグ可能なボトムシート）

    private var bookSheet: some View {
        VStack(spacing: 0) {
            sheetHandle

            ScrollView {
                VStack(spacing: 24) {
                    titleSection
                    detailSection
                }
                .padding(.top, 4)
                .padding(.bottom, 90)
            }
            .scrollDisabled(sheetDetent == .collapsed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 40,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 40
            )
        )
        // シート全面をドラッグ対象にする
        // 折りたたみ時: シートのどこを掴んでも開閉できる（スクロールは無効）
        // 展開時: 中身のスクロール／ボタンを優先（閉じる操作はハンドルが担当）
        .contentShape(Rectangle())
        .gesture(
            sheetDragGesture,
            including: sheetDetent == .collapsed ? .gesture : .subviews
        )
    }

    /// ハンドル（この帯の部分をドラッグで開閉できる）
    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(sheetDragGesture)
    }

    /// ハンドルのドラッグで折りたたみ／展開を切り替える
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                snapSheet(velocity: velocity)
            }
    }

    private func snapSheet(velocity: CGFloat) {
        let base = sheetDetent == .collapsed ? collapsedTop : expandedTop
        let projected = base + dragOffset
        let midpoint = (collapsedTop + expandedTop) / 2

        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            if sheetDetent == .collapsed {
                if velocity < -120 || projected < midpoint {
                    sheetDetent = .expanded
                }
            } else {
                if velocity > 120 || projected > midpoint {
                    sheetDetent = .collapsed
                }
            }
            dragOffset = 0
        }
    }
    
    // MARK: - Subviews

    private func coverSection(screenWidth: CGFloat) -> some View {
        LocalCoverImage(book: book) { localCover in
        ZStack(alignment: .topTrailing) {
            // 背景（本の画像をぼかしたもの）
            if let coverImage = localCover {
                GeometryReader { geo in
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30)
                        .scaleEffect(1.2)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .clipped()
                .overlay(Color.black.opacity(0.3))
            } else if let imageURL = book.coverImageURL,
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
            if let coverImage = localCover {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        maxWidth: max(screenWidth - 80, 0),
                        maxHeight: 160
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: 20)
            } else if let imageURL = book.coverImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: max(screenWidth - 80, 0),
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
                Text("book.cover_none")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        }
        .frame(height: 370)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            // お気に入りボタン（右下に配置、削除ボタンと右揃え）
            Button(action: {
                toggleFavorite()
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

            if book.priceAtRegistration != nil {
                BookPriceText(book: book, font: .title3, fontWeight: .medium)
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
                if let passbookName = bookPassbookDTO?.name {
                    DetailInfoRow(label: "account.registered", value: passbookName)
                }

                DetailInfoRow(label: "book.registration_date", value: formatDate(book.registeredAt))

                if let publisher = book.publisher {
                    DetailInfoRow(label: "book.publisher", value: publisher)
                }

                if let publishedYear = book.publishedYear {
                    DetailInfoRow(
                        label: "book.published_year",
                        value: L10n.format("book.year_suffix", locale: languageManager.resolvedLocale, String(publishedYear))
                    )
                }

                if let bookFormat = book.bookFormat {
                    DetailInfoRow(label: "book.format", value: bookFormat)
                }

                if let pageCount = book.pageCount {
                    DetailInfoRow(
                        label: "book.page_count",
                        value: L10n.format("book.pages_suffix", locale: languageManager.resolvedLocale, Int64(pageCount))
                    )
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
                        MemoFormattedText(memo: memo, accentColor: linkColor)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(20)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    } else {
                        Text("book.memo.empty")
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

    /// お気に入りの切替（現行どおり `updatedAt` は更新しない・前提12）
    private func toggleFavorite() {
        let previous = book
        var updated = book
        updated.isFavorite.toggle()
        book = updated
        Task {
            do {
                try await repos.books.updateBook(updated)
            } catch {
                rollback(optimistic: updated, previous: previous)
            }
        }
    }

    /// 楽観更新の失敗時ロールバック（鮮度ガードつき・設計メモ 4.5節）。
    /// 待っている間にストリームや別操作が新しい値を入れていたら踏み潰さない。
    /// `bookNotFound` も特別扱いしない（8.4節の「削除後は最後に観測した値を保持」を維持）
    private func rollback(optimistic: BookDTO, previous: BookDTO) {
        if let value = OptimisticUpdate.rollbackValue(
            current: book,
            optimistic: optimistic,
            previous: previous
        ) {
            book = value
        }
    }

    private func deleteBook() {
        let id = book.id
        Task {
            do {
                try await repos.books.deleteBook(id: id)
            } catch {
                // 削除に失敗したら画面を閉じない（レビュー S4-13）
                return
            }
            dismiss()
        }
    }

    /// メモを保存（モーダルから呼ばれる。現行どおり `updatedAt` は更新しない・前提12）
    private func saveMemo(_ newMemo: String) {
        let previous = book
        var updated = book
        updated.memo = newMemo.isEmpty ? nil : newMemo
        book = updated
        Task {
            do {
                try await repos.books.updateBook(updated)
            } catch {
                rollback(optimistic: updated, previous: previous)
            }
        }
    }


    /// 日付を言語に応じた表記でフォーマット
    private func formatDate(_ date: Date) -> String {
        AppDateFormat.display(date)
    }
}

// 詳細情報の行を表示するヘルパーView（ミニマル版）
struct DetailInfoRow: View {
    let label: LocalizedStringKey
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
    Group {
        if let book = PreviewSupport.book(source: .manual) {
            NavigationStack {
                UserBookDetailView(book: book)
            }
        } else {
            Text("No preview book")
        }
    }
    .bookBankPreviewEnvironment()
}
