//
//  PassbookSelectorView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData

/// 口座選択画面
struct PassbookSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Passbook.sortOrder) private var passbooks: [Passbook]
    
    @Binding var selectedPassbook: Passbook?
    var onSelect: (() -> Void)?  // 選択時のコールバック
    
    @State private var passbookToEdit: Passbook?
    @State private var showAddPassbook = false
    
    // カスタム口座を取得
    private var customPassbooks: [Passbook] {
        passbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // マイ口座（ひとつずつ分ける）
                    ForEach(customPassbooks) { passbook in
                        passbookRow(
                            name: passbook.name,
                            subtitle: nil,
                            color: PassbookColor.color(for: passbook, in: customPassbooks),
                            isSelected: selectedPassbook?.persistentModelID == passbook.persistentModelID,
                            showMenu: true,
                            onMenuTap: {
                                passbookToEdit = passbook
                            }
                        ) {
                            selectedPassbook = passbook
                            onSelect?()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            
            Spacer()
            
            // 下部に配置：新しい口座を追加
            VStack(spacing: 0) {
                Divider()
                
                Button(action: {
                    showAddPassbook = true
                }) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.subheadline)
                        Text("新しい口座を追加")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .background(Color.appCardBackground)
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("口座を選択")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $passbookToEdit) { passbook in
            EditPassbookView(passbook: passbook)
        }
        .sheet(isPresented: $showAddPassbook) {
            AddPassbookView()
        }
    }
    
    // 口座行のビュー
    private func passbookRow(
        name: String,
        subtitle: String?,
        color: Color,
        isSelected: Bool,
        showMenu: Bool,
        onMenuTap: (() -> Void)? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            // 口座情報（タップで選択）
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // 口座アイコン（fillとstrokeを重ねる）
                    ZStack {
                        Image("icon-tab-account-fill")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(color.opacity(0.1))
                        
                        Image("icon-tab-account")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(color)
                    }
                    .frame(width: 20, height: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 三点リーダー（タップで編集）
            if showMenu {
                Button(action: {
                    onMenuTap?()
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.appCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - EditPassbookView

/// 口座編集ビュー（PassbookSelectorから呼び出し用）
struct EditPassbookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var passbook: Passbook
    @State private var editingName: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var showDeleteAlert = false
    
    // この口座の本の数を取得
    @Query private var allBooks: [UserBook]
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    private var bookCount: Int {
        allBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }.count
    }
    
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    init(passbook: Passbook) {
        self.passbook = passbook
        _editingName = State(initialValue: passbook.name)
        // colorIndexがあればそれを、なければリスト内の位置を使う
        if let colorIndex = passbook.colorIndex {
            _selectedColorIndex = State(initialValue: colorIndex)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("口座名", text: $editingName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("口座名")
                    } 
                    
                    Section {
                        HStack(spacing: 0) {
                            ForEach(0..<PassbookColor.count, id: \.self) { index in
                                Button {
                                    selectedColorIndex = index
                                } label: {
                                    Circle()
                                        .fill(PassbookColor.color(for: index))
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            if selectedColorIndex == index {
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: 2)
                                                    .frame(width: 30, height: 30)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 12)
                    } header: {
                        Text("テーマカラー")
                    }
                }
                .onAppear {
                    // colorIndexが未設定の場合、リスト内の位置に基づいた色をデフォルトにする
                    if passbook.colorIndex == nil {
                        if let index = customPassbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
                            selectedColorIndex = index % PassbookColor.count
                        }
                    }
                }
                
                // 削除ボタン（画面下固定）
                VStack(spacing: 0) {
                    Divider()
                    
                    VStack(spacing: 4) {
                        Button(role: .destructive, action: {
                            showDeleteAlert = true
                        }) {
                            HStack {
                                Spacer()
                                Text("この口座を削除")
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        
                        if bookCount > 0 {
                            Text("この口座に登録されている\(bookCount)冊の本も削除されます")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(Color.appGroupedBackground)
                }
            }
            .navigationTitle("口座を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        savePassbook()
                    }
                    .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("口座を削除しますか？", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    deletePassbook()
                }
            } message: {
                if bookCount > 0 {
                    Text("「\(editingName)」を削除すると、この口座に登録されている\(bookCount)冊の本も削除されます。\n\nこの操作は取り消せません。")
                } else {
                    Text("「\(editingName)」を削除してもよろしいですか？\n\nこの操作は取り消せません。")
                }
            }
        }
    }
    
    private func savePassbook() {
        passbook.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        passbook.colorIndex = selectedColorIndex
        try? context.save()
        dismiss()
    }
    
    private func deletePassbook() {
        // 関連する本も削除
        let booksToDelete = allBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
        for book in booksToDelete {
            context.delete(book)
        }
        
        context.delete(passbook)
        try? context.save()
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook1 = Passbook(name: "プライベート", type: .custom, sortOrder: 1)
    let passbook2 = Passbook(name: "漫画", type: .custom, sortOrder: 2)
    
    container.mainContext.insert(passbook1)
    container.mainContext.insert(passbook2)
    
    return NavigationStack {
        PassbookSelectorView(selectedPassbook: .constant(nil))
    }
    .modelContainer(container)
}
