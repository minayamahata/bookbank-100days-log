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
                "memo.list.title",
                locale: languageManager.resolvedLocale
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedBook) { book in
            UserBookDetailView(book: book)
        }
        .task {
            for await value in repos.books.observeBooks() {
                loadedBooks = value
            }
        }
    }

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(memoItems) { item in
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
            .padding(.vertical, 16)
        }
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
