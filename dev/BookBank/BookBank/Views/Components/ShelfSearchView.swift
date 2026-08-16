//
//  ShelfSearchView.swift
//  BookBank
//
//  本棚内検索のUI一式（R4.6・2026-08-13 オーナー確定で共通化）。
//  本棚タブと通帳ページの両方から使う——複製すると片方だけ直されてずれるため、
//  検索バー・入力前のつながり一覧・入力中の橋渡しチップ・件数・結果グリッド・
//  0件表示をここへ切り出した。
//
//  つながりの絞り込み状態（解除チップ・`BookshelfChromeState.linkFilter`）は
//  持たない——それは本棚タブの寿命の長い状態で、検索の共通化とは別の話
//  （2026-08-13 オーナー確定）。チップを押したときの動作は `onSelectLink` で
//  呼び出し側が決める（本棚: その場で絞り込み／通帳: 総合口座へ切り替えて本棚へ移動）。
//

import SwiftUI

/// つながりの印（メモ編集ツールバーの「つなぐ」と同じ図像）。
/// チップの言葉だけでは著者・タイトルの一致と見分けがつかないため添える
/// （2026-08-12 オーナー指示——文言だと5言語で幅が伸びるのでアイコンで示す）
struct MemoLinkChipIcon: View {
    var size: CGFloat = 12

    var body: some View {
        Image("icn_node")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// 本棚内検索のUI一式。呼び出し側が `ScrollView` に入れて使う。
/// 検索バーは中身と一緒にスクロールする（固定は使い勝手として不評だったため戻した・2026-08-15）。
/// - Note: オンライン検索（`BookSearchView`）とは完全に別系統。所有本のローカル絞り込みのみ
struct ShelfSearchView<UnderBar: View, EmptyFallback: View>: View {
    /// 結果グリッドの検索対象（呼び出し側でスコープ済み。総合=全冊・カスタム=その口座の本。
    /// 本棚はお気に入り・メモ・つながり絞り込みの適用後を渡し、検索とのANDを保つ）
    let books: [BookDTO]

    /// つながり一覧・橋渡しチップの元。口座全体から構築して渡す
    /// （結果グリッド側の絞り込みに左右されない——本棚の従来挙動と同じ）
    let linkIndex: MemoLinkIndex

    /// 文字・チップの基準色（本棚と同じ判定: 総合口座のライトは primary、それ以外は白）
    let controlColor: Color

    let onSelectBook: (BookDTO) -> Void
    let onSelectLink: (MemoLinkSelection) -> Void

    /// 0件表示の登録導線。nil なら導線を出さない（総合口座でカスタム口座が無い場合など）
    let onRegisterBook: (() -> Void)?

    /// 検索バー直下に差し込む行（本棚: つながり解除チップの行。不要なら EmptyView）
    @ViewBuilder let underBar: () -> UnderBar

    /// 入力前に0冊のときの表示（本棚: つながり絞り込み0件の文言や登録プロンプト）
    @ViewBuilder let emptyFallback: () -> EmptyFallback

    /// 検索クエリ（1文字ごとに即時絞り込み）
    @State private var searchText = ""

    @FocusState private var isFieldFocused: Bool

    /// つながり一覧を全件に展開しているか（開き直すと畳んだ状態に戻る）
    @State private var showsAllLinks = false

    // グリッドの列定義（本棚と同じ4カラム）
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// 有効な絞り込みを行っているか（入力あり）
    private var isSearchActive: Bool {
        !trimmedQuery.isEmpty
    }

    /// クエリ適用後の書籍。数百〜千冊でもタイトル+著者の正規化は軽量なため、
    /// 毎キーストロークのインライン計算で十分（本棚の従来実装と同じ）
    private var filteredBooks: [BookDTO] {
        guard isSearchActive else { return books }
        return books.filter {
            ShelfSearchMatcher.matches(fields: [$0.title, $0.author], query: trimmedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow

            underBar()

            if isSearchActive {
                // 入力あり: 一致するつながりのチップ（検索結果の上・決定事項3）＋件数
                linkMatchRow
                resultCountRow
            } else {
                // 入力前: つながりの一覧（表記ゆれに気づく場所・設計メモ4.1節）
                linkListSection
            }

            gridContent
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - 検索バー

    /// 検索フィールド行（虫眼鏡＋テキストフィールド＋フィールド内の✕クリア）。
    /// 検索モードの終了は右上ツールバーの✕が担うため、フィールド横のボタンは置かない
    /// （2026-08-14 オーナー指示——クリア手段はフィールド内の✕に一本化）
    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(controlColor.opacity(0.7))

            TextField(
                "",
                text: $searchText,
                prompt: Text("bookshelf.search.placeholder")
                    .foregroundColor(controlColor.opacity(0.5))
            )
            .font(.app(size: 13))
            .focused($isFieldFocused)
            .foregroundColor(controlColor)
            .tint(controlColor)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel(Text("bookshelf.search.placeholder"))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(controlColor.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(controlColor.opacity(0.08)))
        .overlay(Capsule().strokeBorder(controlColor.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// 検索結果の件数表示（検索フィールド直下）
    private var resultCountRow: some View {
        HStack {
            Text(L10n.format("bookshelf.search.result_count", Int64(filteredBooks.count)))
                .font(.app(.caption))
                .foregroundColor(controlColor.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - つながりチップ

    /// 候補チップ（線のみ・件数つき）。タップの動作は呼び出し側（`onSelectLink`）が決める
    private func linkSuggestionChip(_ link: MemoLinkIndex.Link, showsIcon: Bool) -> some View {
        Button(action: { onSelectLink(MemoLinkSelection(key: link.key, display: link.display)) }) {
            HStack(spacing: 6) {
                if showsIcon {
                    MemoLinkChipIcon()
                }
                Text(link.display)
                    .lineLimit(1)
                Text(link.bookCount.formatted())
                    .font(.app(size: 10))
                    .opacity(0.7)
            }
            .font(.app(size: 13))
            .foregroundColor(controlColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(controlColor.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 一覧に最初から出すつながりの数（多い順の上位）。実際は数十件に収まる想定だが、
    /// 上限が無いと際限なく伸びるため区切る（2026-08-12 実機確認を受けたオーナー指示）
    private static var linkListDisplayLimit: Int { 20 }

    /// 検索の入力前に出す、つながりの一覧（多い順・件数つき）。
    /// 全部のつながりを見られる場所で、表記ゆれ（[[京都]] と [[きょうと]]）に
    /// 気づく場所を兼ねる（設計メモ 4.1節）。つながりが1つも無ければ何も出ない。
    /// 上限を超えるぶんは「もっと見る」で全件に展開する
    @ViewBuilder
    private var linkListSection: some View {
        let links = linkIndex.links
        let visibleLinks = showsAllLinks ? links : Array(links.prefix(Self.linkListDisplayLimit))
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    MemoLinkChipIcon(size: 11)
                    Text("bookshelf.links.header")
                }
                .font(.app(size: 12))
                .foregroundColor(controlColor.opacity(0.7))

                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(visibleLinks, id: \.key) { link in
                        linkSuggestionChip(link, showsIcon: false)
                    }

                    if links.count > visibleLinks.count {
                        showMoreLinksChip(remaining: links.count - visibleLinks.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    /// 一覧の続きを開くチップ（残り件数つき）。押すと全件に展開する
    private func showMoreLinksChip(remaining: Int) -> some View {
        Button(action: { showsAllLinks = true }) {
            HStack(spacing: 4) {
                Text(L10n.format("bookshelf.links.show_more", Int64(remaining)))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.app(size: 13))
            .foregroundColor(controlColor.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                Capsule().strokeBorder(
                    controlColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 検索語に一致するつながりのチップ（検索結果の上・決定事項3）。
    /// 一致は部分一致＋本棚内検索と同じ正規化、複数一致は多い順に横1行
    /// （2026-08-12 オーナー確定）。先頭のアイコンが「著者・タイトルの一致ではなく
    /// つながり」であることの見分けになる
    @ViewBuilder
    private var linkMatchRow: some View {
        let matches = linkIndex.links(matching: searchText)
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(matches, id: \.key) { link in
                        linkSuggestionChip(link, showsIcon: true)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - 結果グリッド

    private var gridContent: some View {
        Group {
            if filteredBooks.isEmpty {
                if isSearchActive {
                    searchEmptyState
                } else {
                    emptyFallback()
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredBooks) { book in
                        Button(action: { onSelectBook(book) }) {
                            BookCoverView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .animation(nil, value: filteredBooks.count)
            }
        }
        .padding(.bottom, 100)
    }

    /// 検索で0件のときの空状態。オンライン検索（登録）への導線を出す（仕様3.4）
    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(controlColor.opacity(0.5))

            Text("bookshelf.search.empty_title")
                .font(.app(.headline))
                .foregroundColor(controlColor)

            Text("bookshelf.search.empty_message")
                .font(.app(.subheadline))
                .foregroundColor(controlColor.opacity(0.7))
                .multilineTextAlignment(.center)

            if let onRegisterBook {
                Button(action: onRegisterBook) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("book.register")
                    }
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundColor(controlColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().strokeBorder(controlColor.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
}
