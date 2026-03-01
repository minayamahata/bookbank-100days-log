//
//  AddReadingListView.swift
//  BookBank
//
//  Created on 2026/01/31
//

import SwiftUI
import SwiftData

/// 読了リスト作成画面（ステップ形式）
struct AddReadingListView: View {
    var themeColor: Color = .accentColor
    var onNavigateToPassbook: (() -> Void)?
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingLists: [ReadingList]
    @Query private var allBooks: [UserBook]
    
    @State private var title: String = ""
    @State private var showError: Bool = false
    @State private var createdList: ReadingList?
    @State private var showBookSelector = false
    @FocusState private var isFocused: Bool
    
    /// デフォルトのリスト名を生成
    private var defaultTitle: String {
        "Myリスト#\(existingLists.count + 1)"
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
                
                if allBooks.isEmpty {
                    VStack(spacing: 20) {
                        Text("まずは口座に本を登録しましょう")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            dismiss()
                            onNavigateToPassbook?()
                        }) {
                            Text("本を登録する")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(themeColor))
                        }
                    }
                } else {
                    // メインコンテンツ
                    VStack(spacing: 32) {
                        Text("読了リストの名前はどうしますか？")
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
                            createReadingList()
                        }) {
                            Text("作成する")
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
        .onAppear {
            guard !allBooks.isEmpty else { return }
            title = defaultTitle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("リストの作成に失敗しました")
        }
        .fullScreenCover(isPresented: $showBookSelector, onDismiss: {
            // 本の追加画面が閉じたら、リストが空かどうかチェック
            if let list = createdList {
                if list.books.isEmpty {
                    // 本が追加されなかった場合はリストを削除
                    context.delete(list)
                    try? context.save()
                    print("✅ Reading list creation cancelled and deleted (no books added)")
                }
            }
            dismiss()
        }) {
            if let list = createdList {
                BookSelectorView(readingList: list)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func createReadingList() {
        guard !title.isEmpty else { return }
        
        let newList = ReadingList(title: title)
        newList.colorIndex = 10
        context.insert(newList)
        
        do {
            try context.save()
            print("✅ New reading list created: \(title)")
            createdList = newList
            showBookSelector = true
        } catch {
            print("❌ Error creating reading list: \(error)")
            showError = true
        }
    }
}

#Preview {
    AddReadingListView()
        .modelContainer(for: [ReadingList.self, UserBook.self, Passbook.self])
}
