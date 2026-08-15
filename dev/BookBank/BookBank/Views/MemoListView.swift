//
//  MemoListView.swift
//  BookBank
//
//  Created on 2026/08/15
//

import SwiftUI

/// 本に書いたメモだけを一覧し、タップでその本の詳細へ辿るページ（R4.6）
struct MemoListView: View {
    @Environment(AppRepositories.self) private var repos
    @Environment(LanguageManager.self) private var languageManager

    @State private var loadedBooks: [BookDTO]?
    @State private var selectedBook: BookDTO?
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var allBooks: [BookDTO] {
        loadedBooks ?? repos.books.latestSnapshot
    }

    /// コールドスタートで空状態が1フレーム瞬くのを防ぐ（既存画面と同じ判定）
    private var hasResolvedBooks: Bool {
        loadedBooks != nil || !repos.books.latestSnapshot.isEmpty
    }

    private struct MemoListItem: Identifiable {
        let book: BookDTO
        let text: String

        var id: String { book.id }
    }

    /// リポジトリの正準順を維持したまま、本文のあるメモだけを残す
    private var memoItems: [MemoListItem] {
        allBooks.compactMap { book in
            guard let memo = book.memo, !memo.isEmpty else {
                return nil
            }

            let text = MemoPlainText.stripped(from: memo)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return MemoListItem(book: book, text: text)
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var isSearchActive: Bool {
        isSearching && !trimmedQuery.isEmpty
    }

    private var filteredMemoItems: [MemoListItem] {
        guard isSearchActive else {
            return memoItems
        }

        return memoItems.filter { item in
            ShelfSearchMatcher.matches(
                fields: [item.text],
                query: trimmedQuery
            )
        }
    }

    private var navigationTitleKey: String {
        isSearching ? "bookshelf.search.title" : "memo.list.title"
    }

    var body: some View {
        let _ = languageManager.currentLanguage

        ZStack {
            Color.appGroupedBackground
                .ignoresSafeArea()

            if !hasResolvedBooks {
                Color.clear
            } else if memoItems.isEmpty {
                emptyState
            } else {
                memoList
            }
        }
        .navigationTitle(
            L10n.string(
                navigationTitleKey,
                locale: languageManager.resolvedLocale
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSearching {
                    Button {
                        exitSearch()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("common.cancel"))
                } else if hasResolvedBooks && !memoItems.isEmpty {
                    Button {
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("memo.list.search.placeholder"))
                }
            }
        }
        .navigationDestination(item: $selectedBook) { book in
            UserBookDetailView(book: book)
        }
        .onChange(of: memoItems.isEmpty) { _, isEmpty in
            if isEmpty && isSearching {
                exitSearch()
            }
        }
        .task {
            for await value in repos.books.observeBooks() {
                loadedBooks = value
            }
        }
    }

    private func exitSearch() {
        isSearchFieldFocused = false
        searchText = ""

        withAnimation(.easeInOut(duration: 0.2)) {
            isSearching = false
        }
    }

    private var memoList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isSearching {
                    searchFieldRow
                        .onAppear {
                            isSearchFieldFocused = true
                        }
                }

                if isSearchActive {
                    resultCountRow
                }

                if isSearchActive && filteredMemoItems.isEmpty {
                    searchEmptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMemoItems) { item in
                            Button {
                                selectedBook = item.book
                            } label: {
                                Text(item.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(16)
                                    .background(Color.appCardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, isSearching ? 0 : 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.7))

            TextField(
                "",
                text: $searchText,
                prompt: Text("memo.list.search.placeholder")
                    .foregroundStyle(Color.primary.opacity(0.5))
            )
            .font(.system(size: 13))
            .focused($isSearchFieldFocused)
            .foregroundStyle(Color.primary)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var resultCountRow: some View {
        Text(
            L10n.format(
                "bookshelf.search.result_count",
                Int64(filteredMemoItems.count)
            )
        )
        .font(.caption)
        .foregroundStyle(Color.primary.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var searchEmptyState: some View {
        Text("memo.list.search.empty")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.horizontal, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.system(size: 60))
                .foregroundStyle(.gray)

            Text("memo.list.empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
