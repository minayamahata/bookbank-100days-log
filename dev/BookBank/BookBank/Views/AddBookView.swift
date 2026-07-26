//
//  AddBookView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/15.
//

import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// 本の登録画面
/// モーダルで表示され、手動で書籍情報を入力して登録する
struct AddBookView: View {
    
    // MARK: - Environment
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss

    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(AppRepositories.self) private var repos
    
    // MARK: - Properties
    
    /// 登録先の口座（初期値）
    let passbook: PassbookDTO
    
    /// 口座選択を許可するかどうか
    let allowPassbookChange: Bool
    
    /// 保存成功時のコールバック（親画面を閉じるため）
    var onSave: (() -> Void)?
    
    // MARK: - SwiftData Query / State
    
    /// すべての口座（リポジトリストリーム）
    @State private var allPassbooks: [PassbookDTO] = []
    
    /// カスタム口座のみ取得
    private var customPassbooks: [PassbookDTO] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }

    /// 選択中の口座のテーマカラー
    private var themeColor: Color {
        if let passbook = selectedPassbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
    // MARK: - Form State
    
    /// 選択中の口座
    @State private var selectedPassbookId: String
    private var selectedPassbook: PassbookDTO? {
        customPassbooks.first { $0.id == selectedPassbookId }
            ?? allPassbooks.first { $0.id == selectedPassbookId }
            ?? (passbook.id == selectedPassbookId ? passbook : nil)
    }
    
    /// 書籍タイトル（必須）
    @State private var title: String = ""
    
    /// 著者名（任意）
    @State private var author: String = ""
    
    /// 価格（任意）
    @State private var priceText: String = ""

    /// 登録日（デフォルトは今日）
    @State private var registeredAt: Date = Date()

    /// 登録日ピッカーの表示フラグ
    @State private var showDatePicker = false
    
    /// 選択された表紙画像
    @State private var selectedImage: UIImage?
    
    /// PhotosPicker用のアイテム
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    /// フォトピッカー表示フラグ
    @State private var showPhotoPicker = false
    
    /// カメラ表示フラグ
    @State private var showCamera = false
    
    /// カメラ権限拒否アラート
    @State private var showCameraDeniedAlert = false
    
    /// キーボードフォーカス
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, author, price
    }
    
    // MARK: - Initialization
    
    init(passbook: PassbookDTO, allowPassbookChange: Bool = false, onSave: (() -> Void)? = nil) {
        self.passbook = passbook
        self.allowPassbookChange = allowPassbookChange
        self.onSave = onSave
        _selectedPassbookId = State(initialValue: passbook.id)
    }
    
    // MARK: - Validation
    
    /// 保存ボタンが有効かどうか（タイトルと金額が必須）
    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasValidPrice = currencyManager.displayCurrency.minorUnits(fromInput: priceText) != nil
        return hasTitle && hasValidPrice
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // 表紙画像
                Section {
                    if let selectedImage {
                        VStack(spacing: 8) {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                                .frame(maxWidth: .infinity)
                            
                            Button(role: .destructive) {
                                withAnimation {
                                    self.selectedImage = nil
                                    self.selectedPhotoItem = nil
                                }
                            } label: {
                                Text("book.cover_delete")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                        .foregroundColor(Color.gray.opacity(0.4))
                                )
                                .frame(width: 120, height: 180)
                                .overlay {
                                    Text("book.cover")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            
                            Menu {
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    Label("book.library_select", systemImage: "photo.on.rectangle")
                                }
                                
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button {
                                        focusedField = nil
                                        requestCameraAccess()
                                    } label: {
                                        Label("book.camera_capture", systemImage: "camera")
                                    }
                                }
                            } label: {
                                Text("book.cover_register")
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                
                Section {
                    // タイトル（必須）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("book.title_label")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        TextField("book.title_placeholder", text: $title)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .title)
                    }

                    // 著者名（任意）
                    TextField("book.author", text: $author)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .author)

                    // 価格（必須）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("book.price")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack {
                            Text(currencyManager.displayCurrency.displaySymbol)
                                .foregroundColor(.secondary)
                            TextField("book.price_placeholder", text: $priceText)
                                .keyboardType(currencyManager.displayCurrency.fractionDigits > 0 ? .decimalPad : .numberPad)
                                .focused($focusedField, equals: .price)
                        }
                    }
                }

                // 登録日（デフォルトは今日）
                Section {
                    Button {
                        withAnimation {
                            showDatePicker.toggle()
                        }
                    } label: {
                        HStack {
                            Text("book.registration_date")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(formatDate(registeredAt))
                                .foregroundColor(themeColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showDatePicker {
                        DatePicker(
                            "",
                            selection: $registeredAt,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(themeColor)
                        .labelsHidden()
                    }
                }

                // 口座選択（allowPassbookChangeがtrueの場合のみ表示）
                if allowPassbookChange {
                    Section {
                        Picker("account.title", selection: $selectedPassbookId) {
                            ForEach(customPassbooks) { passbook in
                                Text(passbook.name)
                                    .foregroundColor(.primary)
                                    .tag(passbook.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeColor)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    allPassbooks = value
                }
            }
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle("book.add.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                // 保存ボタン
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveBook()
                    }
                    .disabled(!canSave)
                    .foregroundColor(canSave ? themeColor : .gray)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker { image in
                    selectedImage = image
                }
                .ignoresSafeArea()
            }
            .alert("book.camera.denied.title", isPresented: $showCameraDeniedAlert) {
                Button("book.camera.open_settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("book.camera.denied.message")
            }
        }
    }
    
    // MARK: - Actions
    
    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        showCameraDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraDeniedAlert = true
        @unknown default:
            showCameraDeniedAlert = true
        }
    }
    
    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = uiImage
                }
            }
        }
    }
    
    /// 画像をJPEGデータに変換（リサイズ含む）
    private func compressedImageData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 800
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
    
    /// 日付を言語に応じた表記でフォーマット
    private func formatDate(_ date: Date) -> String {
        AppDateFormat.display(date)
    }

    /// 本を保存する
    private func saveBook() {
        guard let price = currencyManager.displayCurrency.minorUnits(fromInput: priceText),
              let targetDTO = selectedPassbook else {
            return
        }

        let imageData = selectedImage.flatMap { compressedImageData(from: $0) }
        let now = Date()

        let newBook = BookDTO(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            author: author.isEmpty ? nil : author.trimmingCharacters(in: .whitespaces),
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            seriesName: nil,
            price: price,
            imageURL: nil,
            bookFormat: nil,
            pageCount: nil,
            source: .manual,
            memo: nil,
            isFavorite: false,
            priceAtRegistration: price,
            currencyCode: currencyManager.displayCurrency.code,
            // 登録日は未来日を許可しない（DatePicker でも制限しているが、保存時にも保証する）
            registeredAt: min(registeredAt, now),
            createdAt: now,
            updatedAt: now,
            passbookId: targetDTO.id,
            hasCoverImage: imageData?.isEmpty == false
        )

        // 保存に失敗したら画面を閉じない・onSave も呼ばない（旧実装の do/catch と同じ・レビュー S4-3）。
        // エラーUIは新設しない（設計メモ 4.5節・前提13）
        Task {
            do {
                try await repos.books.addBook(newBook, coverImageData: imageData)
            } catch {
                return
            }
            dismiss()
            onSave?()
        }
    }
}

// MARK: - Preview

#Preview {
    AddBookView(
        passbook: PassbookDTO(
            id: UUID().uuidString,
            name: "漫画口座",
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
