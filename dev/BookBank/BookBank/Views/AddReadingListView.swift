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
                            createReadingList()
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
        .onAppear {
            guard !allBooks.isEmpty else { return }
            title = defaultTitle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
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
                if let list = createdList {
                    if list.books.isEmpty {
                        context.delete(list)
                        try? context.save()
                    }
                }
                dismiss()
            }
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
            createdList = newList
            showBookSelector = true
        } catch {
            #if DEBUG
            print("❌ Error creating reading list: \(error)")
            #endif
            showError = true
        }
    }
}

#Preview {
    AddReadingListView()
        .modelContainer(for: [ReadingList.self, UserBook.self, Passbook.self])
}
