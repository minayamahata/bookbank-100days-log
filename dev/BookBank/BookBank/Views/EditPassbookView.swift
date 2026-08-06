//
//  EditPassbookView.swift
//  BookBank
//
//  Created on 2026/01/19
//

import SwiftUI
import UniformTypeIdentifiers

/// 口座編集ビュー
struct EditPassbookView: View {
    @Environment(AppRepositories.self) private var repos
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(LanguageManager.self) private var languageManager
    
    let passbook: PassbookDTO
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
    @State private var allPassbooks: [PassbookDTO] = []
    /// ストリーム初回値でのみリスト位置フォールバックを適用する（レビュー #1）
    @State private var hasResolvedDefaultColor = false
    
    private var unlimitedManager: UnlimitedManager { UnlimitedManager.shared }
    
    // 変更検知用の元の値
    @State private var originalName: String = ""
    @State private var originalColorIndex: Int = 0
    @State private var originalCustomColorHex: String? = nil
    
    /// すべての書籍（リポジトリストリーム）
    @State private var loadedBooks: [BookDTO]?
    private var allBooks: [BookDTO] { loadedBooks ?? repos.books.latestSnapshot }

    private var passbookBooks: [BookDTO] {
        allBooks.filter { $0.passbookId == passbook.id }
    }
    
    private var bookCount: Int {
        passbookBooks.count
    }
    
    private var customPassbooks: [PassbookDTO] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    private var hasChanges: Bool {
        editingName != originalName || selectedColorIndex != originalColorIndex ||
        useCustomColor != (originalCustomColorHex != nil) ||
        (useCustomColor && PassbookColor.hexString(from: customColor) != originalCustomColorHex)
    }
    
    init(passbook: PassbookDTO) {
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
                            imageURL: book.coverImageURL,
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
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    allPassbooks = value
                    // 初回yieldでのみデフォルト色を解決（2回目以降やユーザー選択を上書きしない）
                    if !hasResolvedDefaultColor {
                        hasResolvedDefaultColor = true
                        if let index = PassbookColor.resolvedDefaultColorIndex(
                            for: passbook,
                            in: customPassbooks
                        ) {
                            selectedColorIndex = index
                            originalColorIndex = index
                        }
                    }
                }
            }
            .task {
                for await value in repos.books.observeBooks() {
                    loadedBooks = value
                }
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
        AppDateFormat.display(date)
    }
    
    private func savePassbook() {
        var updated = passbook
        updated.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if useCustomColor {
            updated.customColorHex = PassbookColor.hexString(from: customColor)
        } else {
            updated.customColorHex = nil
            updated.colorIndex = selectedColorIndex
        }
        Task {
            try? await repos.passbooks.updatePassbook(updated)
            dismiss()
        }
    }
    
    private func deletePassbook() {
        // 所属本の削除はリポジトリ側（設計メモ 4.4節）
        Task {
            try? await repos.passbooks.deletePassbook(id: passbook.id)
            dismiss()
        }
    }
}

#Preview {
    EditPassbookView(
        passbook: PassbookDTO(
            id: UUID().uuidString,
            name: "プライベート",
            type: .custom,
            sortOrder: 1,
            isActive: true,
            colorIndex: 0,
            customColorHex: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
    .bookBankPreviewEnvironment()
}
