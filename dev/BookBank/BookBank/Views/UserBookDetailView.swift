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
    @Environment(AppShellState.self) private var appShellState

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
    @State private var showEditBook = false

    /// 詳細パネル（ボトムシート）のスナップ位置
    private enum SheetDetent {
        case collapsed
        case expanded
    }

    @State private var sheetDetent: SheetDetent = .collapsed
    @State private var dragOffset: CGFloat = 0

    /// 物理画面上端からコンテンツ開始位置（ナビバー下端）までの実測値。
    /// ルートは safe area を無視しないため、global の minY がそのままこの距離になる
    @State private var contentTopInset: CGFloat = 0

    /// コンテンツ領域の global 下端（シート高の下端補正の算出に使う）
    @State private var containerGlobalMaxY: CGFloat = 0

    /// 物理画面の global 下端（全端無視の背景で実測）
    @State private var screenGlobalMaxY: CGFloat = 0

    /// ツールバーの表示切り替え。シートのspringアニメーションに項目の出現・消失が
    /// 巻き込まれて左上へバウンドしないよう、`sheetDetent` とは別にアニメーション無効で更新する
    /// （`PassbookDetailView` のchrome切り替えと同じ構成。共有状態は使わずこのView内で完結させる）
    @State private var isChromeExpanded = false

    /// 詳細ScrollViewの先頭からのオフセット（先頭でのみ下方向ドラッグを折りたたみに使う）
    @State private var detailScrollOffset: CGFloat = 0

    /// カバー画像の高さ
    private let coverHeight: CGFloat = 370
    /// 折りたたみ時のシート上端位置（物理画面上端から。カバーを大きく見せる）
    private let collapsedTop: CGFloat = 330

    /// 上端距離を計測済みか。未計測の1フレームはシートを出さない（初回の位置ジャンプ防止）
    private var hasMeasuredTopInset: Bool {
        contentTopInset > 0
    }

    /// コンテンツ下端から物理画面下端までの距離（ホームインジケータ等）。
    /// 展開時に負方向へ動かした分と合わせてシート高を補い、画面下部に隙間を出さないために使う
    private var bottomCoverage: CGFloat {
        max(screenGlobalMaxY - containerGlobalMaxY, 0)
    }

    /// 折りたたみ時のシート上端（コンテンツ座標）。物理画面上の330ptに合わせる
    private var collapsedTopOffset: CGFloat {
        collapsedTop - contentTopInset
    }

    /// 展開時のシート上端（コンテンツ座標）。物理画面最上端に合わせる
    private var expandedTopOffset: CGFloat {
        -contentTopInset
    }

    /// 現在のシート上端位置（ドラッグ量を反映しつつ範囲内に収める）
    private var currentSheetTop: CGFloat {
        let base = sheetDetent == .collapsed ? collapsedTopOffset : expandedTopOffset
        return min(max(base + dragOffset, expandedTopOffset), collapsedTopOffset)
    }

    /// 展開度（0=折りたたみ・1=展開）。角丸・背景・ハンドル・FABの連続変化に使う
    private var expansionProgress: CGFloat {
        guard collapsedTopOffset > expandedTopOffset else {
            return sheetDetent == .expanded ? 1 : 0
        }
        return 1 - (currentSheetTop - expandedTopOffset) / (collapsedTopOffset - expandedTopOffset)
    }

    /// 上側の角丸（展開度に応じて40→0へ連続変化）
    private var topCornerRadius: CGFloat {
        40 * (1 - expansionProgress)
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: topCornerRadius
        )
    }

    private var isDetailAtTop: Bool {
        detailScrollOffset <= 4
    }

    private var sheetCollapsedBackground: Color {
        Color(.systemBackground)
    }

    /// 展開側の背景（`PassbookDepositSheet.sheetExpandedBackground` と同じ指定）
    private var sheetExpandedBackground: Color {
        colorScheme == .dark
            ? .appGroupedBackground
            : .appSectionBackground
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

    /// 展開時ナビバー左のchevronの色（テーマに対して視認できる色＝つながりと同じ退避判定）
    private var expandedChevronColor: Color {
        linkColor
    }

    /// 展開時ナビバー右の編集ボタンのグラス色（`PassbookDetailView.expandedAddTint` と同じ判定）
    private var expandedEditTint: Color {
        if colorScheme == .dark && isBlackTheme { return .white }
        return themeColor
    }

    /// 展開時ナビバー右の編集ボタンのアイコン色（`PassbookDetailView.expandedAddIconColor` と同じ判定）
    private var expandedEditIconColor: Color {
        if colorScheme == .dark && expandedEditTint.luminance > 0.5 { return .black }
        return .white
    }

    /// このメモに書かれたつながり（出現順・同じキーは1つ）。
    /// 表示はこのメモに書かれたままの綴り。チップ行（設計メモ 4.4節）に使う
    private var memoLinks: [MemoLink] {
        guard let memo = book.memo, !memo.isEmpty else { return [] }
        var seenKeys = Set<String>()
        return MemoLinkParser.parse(memo).filter { seenKeys.insert($0.key).inserted }
    }

    var body: some View {
        let _ = languageManager.currentLanguage

        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 背景：本のカバー（物理画面上端に固定。ステータスバー／ナビバーの背後まで表示する）
                // ルートは safe area を無視せず、カバー側だけ上端を無視して物理上端へ寄せる
                VStack(spacing: 0) {
                    coverSection(screenWidth: geometry.size.width)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)

                // ヘッダー吸い付き型の詳細パネル。位置(offset)だけ動かして
                // ドラッグ中の再レイアウトを避けつつ、負方向へ動かした分は
                // 高さで補って画面下部に隙間を出さない
                bookSheet
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height - currentSheetTop + bottomCoverage,
                        alignment: .top
                    )
                    .offset(y: currentSheetTop)
                    .animation(.spring(response: 0.35, dampingFraction: 0.88), value: sheetDetent)
                    .transaction { transaction in
                        if dragOffset != 0 {
                            transaction.animation = nil
                        }
                    }
                    // 上端距離の計測が済むまではアニメーションさせずに隠し、初回フレームの
                    // 位置ジャンプを防ぐ（カバー・FAB・ナビバーは計測に依存しないので出したまま）
                    .opacity(hasMeasuredTopInset ? 1 : 0)
                    .allowsHitTesting(hasMeasuredTopInset)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { _, frame in
            if frame.minY > 0, abs(contentTopInset - frame.minY) > 0.5 {
                contentTopInset = frame.minY
            }
            if abs(containerGlobalMaxY - frame.maxY) > 0.5 {
                containerGlobalMaxY = frame.maxY
            }
        }
        .background {
            // 背景色を全面に敷きつつ、物理画面の下端を実測する（シート高の下端補正用）
            Color.appGroupedBackground
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { _, maxY in
                    guard abs(screenGlobalMaxY - maxY) > 0.5 else { return }
                    screenGlobalMaxY = maxY
                }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isChromeExpanded)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isChromeExpanded {
                    Button {
                        collapseSheet()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(expandedChevronColor)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                if isChromeExpanded {
                    Button {
                        collapseSheet()
                    } label: {
                        navigationBarCoverThumbnail
                    }
                    .buttonStyle(.plain)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isChromeExpanded {
                    Button {
                        showEditBook = true
                    } label: {
                        Image("icon-edit")
                            .renderingMode(.template)
                            .foregroundStyle(expandedEditIconColor)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(expandedEditTint)
                }
            }
        }
        .onChange(of: sheetDetent) { _, detent in
            // ナビバー項目の入れ替えがスプリングに乗って左上へバウンドするのを防ぐため、
            // 表示判定のフラグはアニメーション無効で更新する（シートのスライドは別途継続する）
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isChromeExpanded = detent == .expanded
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: {
                showEditBook = true
            }) {
                HStack(spacing: 6) {
                    // 展開時ナビバーの編集ボタンと同じアイコンに統一（icon-edit）
                    Image("icon-edit")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
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
            // 展開度に応じてフェードアウト。ドラッグ開始直後から誤タップを防ぎ、展開時は操作不能にする
            .opacity(1 - expansionProgress)
            .allowsHitTesting(expansionProgress <= 0.001)
        }
        .tint(.primary)
        .sheet(isPresented: $showEditBook) {
            // 削除は編集画面の中にある。成功したら編集シートが閉じたあと、この詳細画面も閉じる
            EditBookView(book: book, onDeleted: { dismiss() })
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
        .onAppear {
            floatingButtonState.isHidden = true
            isChromeExpanded = sheetDetent == .expanded
        }
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
            // 折りたたみ時：シートのどこからでも上方向ドラッグで展開できる
            // （simultaneous なので、メモ欄などシート内ボタンのタップは奪わない）
            .simultaneousGesture(sheetDetent == .collapsed ? expandDragGesture : nil)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                detailScrollOffset = offset
            }
            // 展開時：ScrollViewが先頭にあるときだけ、下方向ドラッグで折りたためる
            .simultaneousGesture(sheetDetent == .expanded ? scrollCollapseDragGesture : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // 折りたたみ側から展開側へ、展開度に応じて連続的にクロスフェードする
            ZStack {
                sheetCollapsedBackground
                sheetExpandedBackground.opacity(expansionProgress)
            }
        }
        .clipShape(sheetShape)
        .contentShape(sheetShape)
    }

    /// ハンドルを含むヘッダー帯。展開度に応じて高さが伸び、展開時は最初のコンテンツが
    /// ナビゲーションバーの下に来るようにする（帯の下方向ドラッグで折りたためる）
    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .opacity(1 - expansionProgress)
            .frame(height: handleAreaHeight, alignment: .top)
            .contentShape(Rectangle())
            .gesture(sheetDetent == .collapsed ? expandDragGesture : nil)
            .simultaneousGesture(sheetDetent == .expanded ? collapseDragGesture : nil)
    }

    /// ヘッダー帯の高さ。折りたたみ時は従来のハンドル領域（44pt）のまま、
    /// 展開時はナビバー下端（実測した上端距離）まで伸びて、コンテンツがナビバーへ潜らないようにする
    private var handleAreaHeight: CGFloat {
        let collapsed: CGFloat = 44
        let expanded = max(contentTopInset, collapsed)
        return collapsed + (expanded - collapsed) * expansionProgress
    }

    /// 折りたたみ時：シートを上方向へドラッグして展開する
    private var expandDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                snapSheet(velocity: value.predictedEndTranslation.height - value.translation.height)
            }
    }

    /// 展開時：ヘッダー帯を下方向へドラッグして折りたたむ（スクロール位置に依存しない）
    private var collapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                guard value.translation.height > 0 else { return }
                snapSheet(velocity: value.predictedEndTranslation.height - value.translation.height)
            }
    }

    /// 展開時：詳細ScrollView用の折りたたみジェスチャー。
    /// ジェスチャーは常時アタッチしたまま「先頭で下方向のとき」だけ作用させることで、
    /// リスト途中の通常スクロールをシート操作として扱わない（`PassbookDepositSheet` と同じ構成）
    private var scrollCollapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard isDetailAtTop, value.translation.height > 0 else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                // 実際にシートを引き下げていたときのみスナップ（通常のスクロール終了では作用させない）
                guard dragOffset > 0 else { return }
                snapSheet(velocity: value.predictedEndTranslation.height - value.translation.height)
            }
    }

    /// 展開時ナビバー中央の書影（高さ36pt・2:3・角丸2pt。タップでシートを折りたたむ）
    /// ——ナビバーの標準高44pt内に収まるサイズなので、ヘッダーの高さは変わらない
    private var navigationBarCoverThumbnail: some View {
        LocalCoverImage(book: book) { coverImage in
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let imageURL = book.coverImageURL,
                      let url = URL(string: imageURL) {
                CachedAsyncImage(url: url, width: 36 * 2 / 3, height: 36)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 36 * 2 / 3, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .contentShape(Rectangle())
    }

    private func collapseSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            sheetDetent = .collapsed
            dragOffset = 0
        }
    }

    private func snapSheet(velocity: CGFloat) {
        let base = sheetDetent == .collapsed ? collapsedTopOffset : expandedTopOffset
        let projected = base + dragOffset
        let midpoint = (collapsedTopOffset + expandedTopOffset) / 2

        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            if sheetDetent == .collapsed {
                if velocity < -120 || projected < midpoint {
                    sheetDetent = .expanded
                }
            } else {
                if velocity > 120 || projected > midpoint || dragOffset > 40 {
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
                .fontWeight(.bold)
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

            Text("book.details.section")
                .font(.headline)
                .padding(.bottom, 8)

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

            // 詳細情報とメモの区切り
            Divider()
                .padding(.bottom, 24)

            // メモ見出し行。囲いを外してタップ位置が分かりづらくなったため、
            // 右端に編集アイコンを置く（カレンダーの月別メモボタンと同じ見た目）
            HStack {
                Text("book.memo")
                    .font(.headline)

                Spacer()

                Button {
                    showMemoEditor = true
                } label: {
                    Image("icn_log-edit")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // メモ欄は囲い（角丸カード・境界線・背景色）なしで本文だけを置く。
            // タップ領域は従来どおり最小高さ120ptを確保する
            Button(action: {
                showMemoEditor = true
            }) {
                Group {
                    if let memo = book.memo, !memo.isEmpty {
                        // 本文は編集画面と同じ .body。subheadline にすると引用（subheadline固定）と
                        // 同じ大きさになり、「引用は本文より少し小さい」の関係が消える
                        MemoFormattedText(memo: memo, accentColor: linkColor)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("book.memo.empty")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // つながりチップ行（設計メモ 4.4節）。メモ本文の着色は「表示」、操作はこのチップが担う。
            // つながりが1つも無い本では行ごと出ない＝使わない人の詳細画面は現状のまま
            if !memoLinks.isEmpty {
                memoLinkChipRow
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    /// メモの下のつながりチップ行。タップで本棚（総合口座）へ移動し、同じつながりで絞り込む。
    /// つながりの印（icn_node）は行頭に1つだけ置き、チップ自体は無地にする
    /// ——1冊に複数のつながりがあると、チップごとのアイコンはうるさいため
    private var memoLinkChipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("icn_node")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(memoLinks, id: \.key) { link in
                    Button(action: { filterBookshelf(by: link) }) {
                        Text(link.display)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(linkColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    // MARK: - Actions

    /// つながりチップから本棚へ。総合口座モードに切り替えて全冊から絞り込む
    /// （2026-08-12 オーナー確定——つながりは口座をまたぐのが普通なので、口座で切らない）。
    /// この詳細ページ自身も閉じる——`filterBookshelf` のNavigationPathリセットでは
    /// `NavigationLink(destination:)` 等でpushされたこの画面はpopされないため、
    /// 本棚タブから来た場合に「その場で絞り込み済みの本棚へ飛ぶ」見え方にならない
    /// （2026-08-14 オーナー指摘）
    private func filterBookshelf(by link: MemoLink) {
        dismiss()
        appShellState.filterBookshelf(
            by: MemoLinkSelection(key: link.key, display: link.display)
        )
    }

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
    .environment(AppShellState())
}
