//
//  AddReadingListView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI

/// 読了リスト作成画面（ステップ形式）
struct AddReadingListView: View {
    var themeColor: Color = .accentColor
    var onNavigateToPassbook: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRepositories.self) private var repos
    /// すべての書籍（リポジトリストリーム）。用途は `.isEmpty` のみで順序に依存しない
    @State private var loadedBooks: [BookDTO]?
    private var allBooks: [BookDTO] { loadedBooks ?? repos.books.latestSnapshot }
    /// 既存リスト（デフォルトタイトルの連番にのみ使う）。
    /// 件数を数えるだけなので購読はせず、スナップショットを都度読む。
    /// `observeReadingLists()` を購読すると全リスト＋所属書籍＋表紙キャッシュの
    /// プライムが同期で走り、件数取得には過剰なコストになる
    private var existingLists: [ReadingListDTO] { repos.readingLists.latestSnapshot }
    /// デフォルトタイトルを初回yieldでのみ適用するためのフラグ（レビュー S4-7）
    @State private var hasResolvedDefaultTitle = false

    @State private var title: String = ""
    @State private var showError: Bool = false
    /// 未保存の作成中リスト。**本が1冊以上選ばれるまで永続化しない**（設計メモ 8.3節-3）。
    /// 旧実装は空リストを先に作ってキャンセル時に削除していた（rollback）
    @State private var draftList: ReadingListDTO?
    /// `BookSelectorView` で選ばれた本（表示順）
    @State private var pendingBooks: [BookDTO] = []
    @State private var showBookSelector = false
    @State private var isCompleting = false
    @FocusState private var isFocused: Bool
    
    /// デフォルトのリスト名を生成
    private var defaultTitle: String {
        L10n.format("readinglist.default_name", Int64(existingLists.count + 1))
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.appGroupedBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 閉じるボタン
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                Spacer()
                
                if isCompleting {
                    ProgressView()
                        .tint(.secondary)
                } else if allBooks.isEmpty {
                    VStack(spacing: 20) {
                        Text("readinglist.empty_register_first")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            dismiss()
                            onNavigateToPassbook?()
                        }) {
                            Text("book.register")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(themeColor))
                        }
                    }
                } else {
                    VStack(spacing: 32) {
                        Text("readinglist.name_prompt")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                        
                        TextField("", text: $title)
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .focused($isFocused)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.appCardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 32)
                        
                        Button(action: {
                            startBookSelection()
                        }) {
                            Text("common.create")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(title.isEmpty ? Color.gray : Color.blue)
                                )
                        }
                        .disabled(title.isEmpty)
                    }
                }
                
                Spacer()
                Spacer()
            }
        }
        .task {
            for await value in repos.books.observeBooks() {
                loadedBooks = value
                // デフォルトタイトルの決定は初回yield時に1回だけ行う（ステップ3 #1 と同形・レビュー S4-7）。
                // `.onAppear` に置くとストリーム未到達の初回フレームでは本が0件に見え、
                // タイトルもフォーカスも設定されないまま終わる
                if !hasResolvedDefaultTitle {
                    hasResolvedDefaultTitle = true
                    guard !value.isEmpty else { continue }
                    title = defaultTitle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isFocused = true
                    }
                }
            }
        }
        .alert("common.error", isPresented: $showError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("readinglist.create.error")
        }
        .fullScreenCover(isPresented: $showBookSelector, onDismiss: {
            isCompleting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                finishCreation()
            }
        }) {
            // 表示内容を `draftList` の Optional 束縛で包まないこと。
            // 包むと、提示のきっかけと `draftList` の反映がずれた瞬間に中身が空になり、
            // 全画面が真っ白なまま残る（再レイアウトが起きるまで復帰しない）。
            // ヘッダーに要るのはタイトルだけなので、常に値のある `title` を直接渡す
            BookSelectorView(listTitle: title, existingBookIds: []) { picked in
                pendingBooks = picked
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// リストは**まだ作らず**、本の選択へ進む
    private func startBookSelection() {
        guard !title.isEmpty else { return }
        
        let now = Date()
        draftList = ReadingListDTO(
            id: UUID().uuidString,
            title: title,
            description: nil,
            colorIndex: 10,
            bookIds: [],
            books: [],
            createdAt: now,
            updatedAt: now,
            legacyShareId: ""
        )
        pendingBooks = []
        showBookSelector = true
    }
    
    /// 本が選ばれていればこの時点で初めて作成する。
    /// 選ばれていなければ何も作らない（旧実装の「空リストを作って delete」と最終状態が同じ）
    private func finishCreation() {
        guard let list = ReadingListDTO.confirmedCreation(
            draft: draftList,
            pickedBooks: pendingBooks,
            now: Date()
        ) else {
            dismiss()
            return
        }
        
        Task {
            do {
                try await repos.readingLists.addReadingList(list)
            } catch {
                #if DEBUG
                print("❌ Error creating reading list: \(error)")
                #endif
                isCompleting = false
                showError = true
                return
            }
            dismiss()
        }
    }
}

#Preview {
    AddReadingListView()
        .bookBankPreviewEnvironment()
}
