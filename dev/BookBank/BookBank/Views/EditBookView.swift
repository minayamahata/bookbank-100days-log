import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// 本の編集画面
/// 手動登録の本は全フィールド編集可能、API登録の本は登録日のみ編集可能
struct EditBookView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    
    // MARK: - Properties
    
    @Bindable var book: UserBook
    
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    private var customPassbooks: [Passbook] {
        allPassbooks.filter { $0.type == .custom && $0.isActive }
    }
    
    private var themeColor: Color {
        if let passbook = book.passbook {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }
    
    private var isManual: Bool {
        book.source == .manual
    }

    /// 手動登録、またはAPI登録で楽天表紙URLがない場合は表紙を編集可能
    private var canEditCover: Bool {
        if isManual { return true }
        return book.coverImageURL == nil
    }
    
    // MARK: - Form State
    
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var priceText: String = ""
    @State private var selectedImage: UIImage?
    @State private var imageChanged = false
    @State private var registeredAt: Date = Date()
    @State private var selectedPassbookID: PersistentIdentifier?
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showCameraDeniedAlert = false
    @State private var showDatePicker = false
    @State private var showMemoEditor = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, author, price
    }
    
    // MARK: - Validation
    
    private var hasChanges: Bool {
        let titleChanged = title.trimmingCharacters(in: .whitespaces) != (book.title)
        let authorChanged = author.trimmingCharacters(in: .whitespaces) != (book.author ?? "")
        let priceChanged = priceText != (book.price.map { book.storedCurrency.inputString(fromMinor: $0) } ?? "")
        let dateChanged = !Calendar.current.isDate(registeredAt, inSameDayAs: book.registeredAt)
        let passbookChanged = selectedPassbookID != book.passbook?.persistentModelID
        return titleChanged || authorChanged || priceChanged || imageChanged || dateChanged || passbookChanged
    }
    
    private var canSave: Bool {
        guard hasChanges else { return false }
        if isManual {
            let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
            let hasValidPrice = book.storedCurrency.minorUnits(fromInput: priceText) != nil
            return hasTitle && hasValidPrice
        }
        return true
    }
    
    // MARK: - Body
    
    var body: some View {
        let _ = languageManager.currentLanguage

        NavigationStack {
            Form {
                // 表紙画像
                coverImageSection
                
                // 登録日
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
                .listSectionSpacing(8)
                
                // 登録口座
                if selectedPassbookID != nil {
                    Section {
                        Picker("account.registered", selection: $selectedPassbookID) {
                            ForEach(customPassbooks) { passbook in
                                Text(passbook.name)
                                    .tag(passbook.persistentModelID as PersistentIdentifier?)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeColor)
                    }
                    .listSectionSpacing(8)
                }
                
                // 書籍情報
                Section {
                    // タイトル
                    HStack {
                        HStack(spacing: 2) {
                            Text("book.field.title")
                            if isManual {
                                Text("*").foregroundColor(.red)
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(width: 70, alignment: .leading)
                        
                        TextField("book.title_placeholder", text: $title)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .title)
                            .disabled(!isManual)
                            .foregroundColor(isManual ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isManual { focusedField = .title }
                    }
                    
                    // 著者名
                    HStack {
                        Text("book.author")
                            .foregroundColor(.primary)
                            .frame(width: 70, alignment: .leading)
                        
                        TextField("book.author_placeholder", text: $author)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .author)
                            .disabled(!isManual)
                            .foregroundColor(isManual ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isManual { focusedField = .author }
                    }
                    
                    // 価格
                    HStack {
                        HStack(spacing: 2) {
                            Text("book.price")
                            if isManual {
                                Text("*").foregroundColor(.red)
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(width: 70, alignment: .leading)
                        
                        HStack(spacing: 2) {
                            Spacer()
                            TextField("book.price_placeholder_short", text: $priceText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(book.storedCurrency.fractionDigits > 0 ? .decimalPad : .numberPad)
                                .focused($focusedField, equals: .price)
                                .disabled(!isManual)
                                .foregroundColor(isManual ? .primary : .secondary)
                                .fixedSize()
                            Text(book.storedCurrency.code)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isManual { focusedField = .price }
                    }
                    
                    if !isManual {
                        if let publisher = book.publisher, !publisher.isEmpty {
                            readOnlyRow(label: "book.publisher", value: publisher)
                        }
                        if let year = book.publishedYear {
                            readOnlyRow(
                                label: "book.published_year",
                                value: L10n.format("book.year_suffix", locale: languageManager.resolvedLocale, String(year))
                            )
                        }
                        if let format = book.bookFormat, !format.isEmpty {
                            readOnlyRow(label: "book.format", value: format)
                        }
                        if let pages = book.pageCount {
                            readOnlyRow(
                                label: "book.page_count",
                                value: L10n.format("book.pages_suffix", locale: languageManager.resolvedLocale, Int64(pages))
                            )
                        }
                    }
                }
                .listSectionSpacing(8)
                
                // メモ
                Section {
                    Button {
                        showMemoEditor = true
                    } label: {
                        HStack {
                            Text("bookshelf.memo")
                                .foregroundColor(.primary)
                            Spacer()
                            if let memo = book.memo, !memo.isEmpty {
                                Text(memo)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("book.memo.not_entered")
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("book.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        saveChanges()
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
                    imageChanged = true
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
            .sheet(isPresented: $showMemoEditor) {
                MemoEditorView(memo: Binding(
                    get: { book.memo ?? "" },
                    set: { _ in }
                )) { newMemo in
                    book.memo = newMemo.isEmpty ? nil : newMemo
                    try? context.save()
                }
            }
            .onAppear {
                title = book.title
                author = book.author ?? ""
                priceText = book.price.map { book.storedCurrency.inputString(fromMinor: $0) } ?? ""
                registeredAt = book.registeredAt
                selectedPassbookID = book.passbook?.persistentModelID
                if let coverImage = book.coverUIImage {
                    selectedImage = coverImage
                }
            }
        }
    }
    
    // MARK: - Cover Image Section
    
    @ViewBuilder
    private var coverImageSection: some View {
        Section {
            if canEditCover {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    self.selectedImage = nil
                                    self.selectedPhotoItem = nil
                                    imageChanged = true
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .offset(x: 6, y: -6)
                        }
                        .overlay(alignment: .bottom) {
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
                                Text("common.edit")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            }
                            .padding(.bottom, 12)
                        }
                        .frame(maxWidth: .infinity)
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
            } else {
                // API登録（楽天表紙URLあり）: 表示のみ
                if let coverImage = selectedImage ?? book.coverUIImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .frame(maxWidth: .infinity)
                        .opacity(0.5)
                } else if let imageURL = book.coverImageURL, let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url, width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .frame(maxWidth: .infinity)
                        .opacity(0.5)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 120, height: 180)
                        .overlay {
                            Text("book.cover_none")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
    }
    
    // MARK: - Helpers
    
    private func readOnlyRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        AppDateFormat.display(date)
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
                    imageChanged = true
                }
            }
        }
    }
    
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
    
    private func saveChanges() {
        if isManual {
            book.title = title.trimmingCharacters(in: .whitespaces)
            book.author = author.isEmpty ? nil : author.trimmingCharacters(in: .whitespaces)
            if let price = book.storedCurrency.minorUnits(fromInput: priceText) {
                book.price = price
                book.priceAtRegistration = price
            }
        }
        if imageChanged {
            book.coverImageData = selectedImage.flatMap { compressedImageData(from: $0) }
            if book.coverImageData != nil, BookCoverImageURL.isRakutenPlaceholder(book.imageURL) {
                book.imageURL = nil
            }
        }
        
        book.registeredAt = registeredAt
        if let id = selectedPassbookID {
            book.passbook = customPassbooks.first { $0.persistentModelID == id }
        }
        book.updatedAt = Date()
        
        do {
            try context.save()
            dismiss()
        } catch {
            #if DEBUG
            print("Error saving book: \(error)")
            #endif
        }
    }
}

// MARK: - Preview

#Preview("手動登録の本") {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Passbook.self, UserBook.self, Subscription.self, ReadingList.self, configurations: config)
        
        let passbook = Passbook(name: "漫画", type: .custom, sortOrder: 1)
        container.mainContext.insert(passbook)
        
        let book = UserBook(
            title: "よつばと！",
            author: "あずまきよひこ",
            price: 693,
            source: .manual,
            passbook: passbook
        )
        container.mainContext.insert(book)
        
        return EditBookView(book: book)
            .modelContainer(container)
    } catch {
        return Text("Preview error: \(error.localizedDescription)")
    }
}

#Preview("API取得の本") {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Passbook.self, UserBook.self, Subscription.self, ReadingList.self, configurations: config)
        
        let passbook = Passbook(name: "技術書", type: .custom, sortOrder: 1)
        container.mainContext.insert(passbook)
        
        let book = UserBook(
            title: "SwiftUI実践入門",
            author: "山田太郎",
            isbn: "9784123456789",
            publisher: "技術評論社",
            publishedYear: 2024,
            seriesName: "プログラミングシリーズ",
            price: 3200,
            imageURL: "https://thumbnail.image.rakuten.co.jp/@0_mall/book/cabinet/6789/9784123456789.jpg",
            bookFormat: "単行本",
            pageCount: 320,
            source: .api,
            passbook: passbook
        )
        container.mainContext.insert(book)
        
        return EditBookView(book: book)
            .modelContainer(container)
    } catch {
        return Text("Preview error: \(error.localizedDescription)")
    }
}
