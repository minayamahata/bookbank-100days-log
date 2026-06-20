//
//  EditPassbookView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 口座編集ビュー
struct EditPassbookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    
    @Bindable var passbook: Passbook
    @State private var editingName: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var showDeleteAlert = false
    @State private var showExportSheet = false
    @State private var showExporter = false
    @State private var exportDocument: MarkdownDocument = MarkdownDocument(text: "")
    @State private var exportFileName: String = ""
    @State private var showColorPicker = false
    @State private var customColor: Color = .blue
    @State private var useCustomColor: Bool = false
    @State private var showUnlimitedPaywall = false
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    // 変更検知用の元の値
    @State private var originalName: String = ""
    @State private var originalColorIndex: Int = 0
    @State private var originalCustomColorHex: String? = nil
    
    // この口座の本の数を取得
    @Query private var allBooks: [UserBook]
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    private var passbookBooks: [UserBook] {
        allBooks.filter { $0.passbook?.persistentModelID == passbook.persistentModelID }
    }
    
    private var bookCount: Int {
        passbookBooks.count
    }
    
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    private var hasChanges: Bool {
        editingName != originalName || selectedColorIndex != originalColorIndex ||
        useCustomColor != (originalCustomColorHex != nil) ||
        (useCustomColor && PassbookColor.hexString(from: customColor) != originalCustomColorHex)
    }
    
    init(passbook: Passbook) {
        self.passbook = passbook
        _editingName = State(initialValue: passbook.name)
        _originalName = State(initialValue: passbook.name)
        _originalCustomColorHex = State(initialValue: passbook.customColorHex)
        if let hex = passbook.customColorHex, !hex.isEmpty {
            _useCustomColor = State(initialValue: true)
            _customColor = State(initialValue: Color(hex: hex))
        }
        if let colorIndex = passbook.colorIndex {
            _selectedColorIndex = State(initialValue: colorIndex)
            _originalColorIndex = State(initialValue: colorIndex)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 口座名セクション
                        VStack(alignment: .leading, spacing: 12) {
                            Text("account.name")
                                .font(.body)
                            
                            HStack(spacing: 8) {
                                TextField("account.name", text: $editingName)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 18, weight: .light))
                                    .multilineTextAlignment(.center)
                                    .frame(height: 50)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                    )
                                
                                Text("account.title")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // テーマカラーセクション
                        VStack(alignment: .leading, spacing: 12) {
                            Text("account.theme_color")
                                .font(.body)
                            
                            let columns = 6
                            let totalCount = PassbookColor.count + 1
                            let rows = (totalCount + columns - 1) / columns
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(0..<rows, id: \.self) { row in
                                    HStack(spacing: 8) {
                                        ForEach(0..<columns, id: \.self) { col in
                                            let index = row * columns + col
                                            if index < PassbookColor.count {
                                                Button {
                                                    selectedColorIndex = index
                                                    useCustomColor = false
                                                } label: {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(PassbookColor.color(for: index))
                                                        .frame(maxWidth: .infinity)
                                                        .frame(height: 46)
                                                        .overlay {
                                                            if !useCustomColor && selectedColorIndex == index {
                                                                RoundedRectangle(cornerRadius: 6)
                                                                    .stroke(Color.primary, lineWidth: 2)
                                                                    .padding(-3)
                                                            }
                                                        }
                                                }
                                                .buttonStyle(.plain)
                                            } else if index == PassbookColor.count {
                                                Button {
                                                    if unlimitedManager.isUnlimited {
                                                        showColorPicker = true
                                                    } else {
                                                        showUnlimitedPaywall = true
                                                    }
                                                } label: {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(
                                                                AngularGradient(
                                                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                                    center: .center
                                                                )
                                                            )
                                                        if !unlimitedManager.isUnlimited {
                                                            RoundedRectangle(cornerRadius: 4)
                                                                .fill(Color.black.opacity(0.5))
                                                        }
                                                        Image(systemName: "plus")
                                                            .foregroundColor(.white)
                                                            .font(.system(size: 14, weight: .bold))
                                                            .shadow(color: .black.opacity(0.3), radius: 1)
                                                    }
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 46)
                                                    .overlay {
                                                        if useCustomColor {
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .stroke(Color.primary, lineWidth: 2)
                                                                .padding(-3)
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                Color.clear
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 46)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if useCustomColor {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Triangle()
                                        .fill(Color.primary.opacity(0.15))
                                        .frame(width: 12, height: 6)
                                        .padding(.trailing, 28)
                                    
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(customColor)
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.primary, lineWidth: 2)
                                                    .padding(-3)
                                            )
                                        
                                        Text("account.custom_color")
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Button("common.change") {
                                            showColorPicker = true
                                        }
                                        .font(.system(size: 14))
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                }
                .onAppear {
                    // colorIndexが未設定の場合、リスト内の位置に基づいた色をデフォルトにする
                    if passbook.colorIndex == nil {
                        if let index = customPassbooks.firstIndex(where: { $0.persistentModelID == passbook.persistentModelID }) {
                            selectedColorIndex = index % PassbookColor.count
                            originalColorIndex = selectedColorIndex
                        }
                    }
                }
                
                // アクションボタン（画面下固定）
                VStack(spacing: 12) {
                    // ダウンロードボタン
                    Button(action: {
                        showExportSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Spacer()
                            Image("icon-download")
                                .renderingMode(.template)
                            Text("account.download_data")
                            Spacer()
                        }
                        .font(.system(size: 15))
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 削除ボタン
                    VStack(spacing: 8) {
                        Button(action: {
                            showDeleteAlert = true
                        }) {
                            HStack {
                                Spacer()
                                Text("account.delete")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if bookCount > 0 {
                            Text(L10n.format("account.delete.warning_books", Int64(bookCount)))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("account.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.save") {
                        savePassbook()
                    }
                    .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasChanges)
                    .foregroundColor(hasChanges && !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .blue : .primary.opacity(0.4))
                }
            }
            .alert("account.delete.title", isPresented: $showDeleteAlert) {
                Button("common.cancel", role: .cancel) { }
                Button("common.delete", role: .destructive) {
                    deletePassbook()
                }
            } message: {
                if bookCount > 0 {
                    Text(L10n.format("account.delete.message_with_books", editingName, Int64(bookCount)))
                } else {
                    Text(L10n.format("account.delete.message_empty", editingName))
                }
            }
            .tint(.primary)
            .sheet(isPresented: $showExportSheet) {
                ExportSheetView(
                    title: passbook.name,
                    bookCount: passbookBooks.count,
                    totalValue: passbookBooks.totalDisplayAmount(
                        in: currencyManager.displayCurrency,
                        exchangeRates: exchangeRates
                    ),
                    sampleBooks: passbookBooks.prefix(4).map { book in
                        if let author = book.author, !author.isEmpty {
                            return "\(book.title) / \(author)"
                        } else {
                            return book.title
                        }
                    },
                    sampleDetailedBook: passbookBooks.first.map { book in
                        (
                            title: book.title,
                            author: book.author,
                            price: book.priceAtRegistration,
                            sourceCurrency: book.storedCurrency,
                            publisher: book.publisher,
                            date: formatExportDate(book.registeredAt),
                            isbn: book.isbn,
                            imageURL: book.imageURL,
                            memo: book.memo,
                            isFavorite: book.isFavorite
                        )
                    },
                    onExportTitleOnly: {
                        showExportSheet = false
                        prepareExport(type: .titleOnly)
                    },
                    onExportDetailed: {
                        showExportSheet = false
                        prepareExport(type: .detailed)
                    }
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: exportFileName
            ) { result in
                #if DEBUG
                switch result {
                case .success:
                    print("✅ Export succeeded")
                case .failure(let error):
                    print("❌ Export failed: \(error)")
                }
                #endif
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerSheet(selectedColor: $customColor, onComplete: {
                    useCustomColor = true
                })
            }
            .sheet(isPresented: $showUnlimitedPaywall) {
                UnlimitedPaywallView()
            }
        }
    }
    
    private func prepareExport(type: ExportType) {
        let formatting = ExportFormattingContext(
            displayCurrency: currencyManager.displayCurrency,
            exchangeRates: exchangeRates,
            locale: languageManager.resolvedLocale
        )
        let markdown = generatePassbookMarkdown(
            passbook: passbook,
            books: passbookBooks,
            exportType: type,
            formatting: formatting
        )
        exportDocument = MarkdownDocument(text: markdown)
        exportFileName = "\(passbook.name).md"
        showExporter = true
    }
    
    private func formatExportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
    
    private func savePassbook() {
        passbook.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if useCustomColor {
            passbook.customColorHex = PassbookColor.hexString(from: customColor)
        } else {
            passbook.customColorHex = nil
            passbook.colorIndex = selectedColorIndex
        }
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
    
    let passbook = Passbook(name: "プライベート", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return EditPassbookView(passbook: passbook)
        .modelContainer(container)
}
