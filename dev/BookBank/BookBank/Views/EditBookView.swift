import SwiftUI
import PhotosUI
import AVFoundation

/// 本の編集画面
/// 手動登録の本は全フィールド編集可能、API登録の本は登録日のみ編集可能
struct EditBookView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LanguageManager.self) private var languageManager
    @Environment(CurrencyManager.self) private var currencyManager
    @Environment(AppRepositories.self) private var repos

    // MARK: - Properties

    /// 編集対象の本（値型のコピー。生の `@Model` は保持しない＝設計メモ 8.4節）
    @State private var book: BookDTO

    /// 削除に成功したとき、このシートを閉じたあとに呼ぶ（詳細画面を閉じてもらう）
    private let onDeleted: () -> Void

    init(book: BookDTO, onDeleted: @escaping () -> Void = {}) {
        _book = State(initialValue: book)
        self.onDeleted = onDeleted
    }

    @State private var allPassbooks: [PassbookDTO] = []
    /// 口座ストリーム到達済みか
    @State private var hasLoadedPassbooks = false

    /// 口座一覧。ストリーム未到達の初回フレームは同期スナップショットで補う（色の1フレーム差を作らない）
    private var resolvedPassbooks: [PassbookDTO] {
        hasLoadedPassbooks ? allPassbooks : repos.passbooks.latestSnapshot
    }

    private var customPassbooks: [PassbookDTO] {
        resolvedPassbooks.filter { $0.type == .custom && $0.isActive }
    }

    private var bookPassbookDTO: PassbookDTO? {
        guard let passbookId = book.passbookId else { return nil }
        return customPassbooks.first(where: { $0.id == passbookId })
            ?? resolvedPassbooks.first(where: { $0.id == passbookId })
    }

    private var themeColor: Color {
        if let passbook = bookPassbookDTO {
            return PassbookColor.color(for: passbook, in: customPassbooks)
        }
        return .blue
    }

    /// メモエディタの装飾色。黒テーマ＋ダークモードではテーマ色が背景に沈むため白へ退避する
    /// （`UserBookDetailView.linkColor` と同じ判断）
    private var memoAccentColor: Color {
        let isBlackTheme = bookPassbookDTO.map {
            PassbookColor.isBlackTheme(for: $0, in: customPassbooks)
        } ?? false
        if colorScheme == .dark && isBlackTheme {
            return .white
        }
        return themeColor
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
    @State private var selectedPassbookID: String?
    @State private var isFavorite = false
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showCameraDeniedAlert = false
    @State private var showDatePicker = false
    @State private var showMemoEditor = false
    @State private var draftRereadRows: [DraftRereadRow] = []
    @State private var deletedRereadIDs: [String] = []
    @State private var expandedRereadID: String?
    @State private var rereadPendingDelete: DraftRereadRow?

    private var registeredAtUpperBound: Date {
        RereadDatePolicy.registeredAtUpperBound(firstRereadDate: draftRereadRows.map(\.record.date).min())
    }

    private var rereadDateRange: ClosedRange<Date> {
        let start = min(registeredAt, Date())
        return start...Date()
    }
    @State private var showDeleteAlert = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, author, price
    }
    
    // MARK: - Validation
    
    private var bookFieldsChanged: Bool {
        let titleChanged = title.trimmingCharacters(in: .whitespaces) != (book.title)
        let authorChanged = author.trimmingCharacters(in: .whitespaces) != (book.author ?? "")
        let priceChanged = priceText != (book.price.map { book.storedCurrency.inputString(fromMinor: $0) } ?? "")
        let dateChanged = !Calendar.current.isDate(registeredAt, inSameDayAs: book.registeredAt)
        let passbookChanged = selectedPassbookID != book.passbookId
        let favoriteChanged = isFavorite != book.isFavorite
        return titleChanged || authorChanged || priceChanged || imageChanged || dateChanged || passbookChanged || favoriteChanged
    }

    private var rereadsChanged: Bool {
        if !deletedRereadIDs.isEmpty { return true }
        let original = book.rereads.sorted { $0.id < $1.id }
        let draft = draftRereadRows.map(\.record).sorted { $0.id < $1.id }
        guard original.map(\.id) == draft.map(\.id) else { return true }
        return zip(original, draft).contains { !Calendar.current.isDate($0.date, inSameDayAs: $1.date) }
    }

    private var hasChanges: Bool {
        bookFieldsChanged || rereadsChanged
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

                // 登録口座（書影の下）
                if selectedPassbookID != nil {
                    Section {
                        Picker("account.registered", selection: $selectedPassbookID) {
                            ForEach(customPassbooks) { passbook in
                                Text(passbook.name)
                                    .tag(Optional(passbook.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeColor)
                    }
                    .listSectionSpacing(8)
                }
                
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
                            in: ...registeredAtUpperBound,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(themeColor)
                        .labelsHidden()
                    }
                }
                .listSectionSpacing(8)

                if !draftRereadRows.isEmpty {
                    Section {
                        ForEach(draftRereadRows) { row in
                            Button {
                                withAnimation {
                                    expandedRereadID = expandedRereadID == row.id ? nil : row.id
                                }
                            } label: {
                                HStack {
                                    Text("book.reread.entry")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(formatDate(row.record.date))
                                        .foregroundColor(themeColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if expandedRereadID == row.id {
                                DatePicker(
                                    "",
                                    selection: rereadDateBinding(for: row.id),
                                    in: rereadDateRange,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .tint(themeColor)
                                .labelsHidden()

                                Button(role: .destructive) {
                                    rereadPendingDelete = row
                                } label: {
                                    Text("book.reread.delete.title")
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

                // お気に入り（詳細画面のカバー右下ボタンと同じ isFavorite を切り替える）
                Section {
                    Toggle("book.favorite", isOn: $isFavorite)
                        .tint(themeColor)
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
                                // 装飾を描けない1行プレビューなので、Markdownの記号は取り除いて見せる
                                Text(MemoHiddenMarkers.strippingMarkers(from: memo))
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

                // 削除（詳細画面から移設・2026-08-13 オーナー指示）
                Section {
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Text("book.delete.action")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.app(.subheadline))
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
            .alert("book.reread.delete.title", isPresented: Binding(
                get: { rereadPendingDelete != nil },
                set: { if !$0 { rereadPendingDelete = nil } }
            )) {
                Button("common.cancel", role: .cancel) { rereadPendingDelete = nil }
                Button("common.delete", role: .destructive) {
                    if let row = rereadPendingDelete {
                        deletedRereadIDs.append(row.record.id)
                        if let index = draftRereadRows.firstIndex(where: { $0.id == row.id }) {
                            draftRereadRows.remove(at: index)
                        }
                        if expandedRereadID == row.id {
                            expandedRereadID = nil
                        }
                    }
                    rereadPendingDelete = nil
                }
            } message: {
                Text("book.reread.delete.message")
            }
            .alert("book.delete.title", isPresented: $showDeleteAlert) {
                Button("common.cancel", role: .cancel) { }
                Button("common.delete", role: .destructive) {
                    deleteBook()
                }
            } message: {
                Text(L10n.format("book.delete.message", locale: languageManager.resolvedLocale, book.title))
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
            // タブのテーマ色がアラートのキャンセルに乗らないようにする（口座編集と同じ）
            .tint(.primary)
            .sheet(isPresented: $showMemoEditor) {
                MemoEditorView(
                    memo: Binding(
                        get: { book.memo ?? "" },
                        set: { _ in }
                    ),
                    allowsLinks: true,
                    accentColor: memoAccentColor
                ) { newMemo in
                    saveMemo(newMemo)
                }
            }
            .onAppear {
                title = book.title
                author = book.author ?? ""
                priceText = book.price.map { book.storedCurrency.inputString(fromMinor: $0) } ?? ""
                registeredAt = book.registeredAt
                draftRereadRows = book.rereads.map { DraftRereadRow(record: $0) }
                deletedRereadIDs = []
                selectedPassbookID = book.passbookId
                isFavorite = book.isFavorite
                if selectedImage == nil, !imageChanged,
                   let coverImage = LocalCoverDataCache.shared.image(for: book.id) {
                    // 通常はストリーム受領時にキャッシュ済みのため同期で取れる（初回フレーム差なし）
                    selectedImage = coverImage
                }
            }
            .task {
                for await value in repos.passbooks.observePassbooks() {
                    allPassbooks = value
                    hasLoadedPassbooks = true
                }
            }
            .task(id: book.id) {
                // キャッシュミス（LRU退避）時のみ非同期フォールバック
                guard selectedImage == nil, !imageChanged, book.hasCoverImage else { return }
                guard let data = await repos.books.loadCoverImage(bookId: book.id), !data.isEmpty else { return }
                guard selectedImage == nil, !imageChanged else { return }
                selectedImage = LocalCoverDataCache.shared.storeAndDecode(data, for: book.id)
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
                                    .font(.app(.subheadline))
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
                                    .font(.app(.subheadline))
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
                                .font(.app(.subheadline))
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
                if let coverImage = selectedImage {
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
                                .font(.app(.subheadline))
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
    
    /// メモは編集シートを閉じた時点で即保存する（現行どおり・`updatedAt` は更新しない＝前提12）
    private func saveMemo(_ newMemo: String) {
        let previous = book
        var updated = book
        updated.memo = newMemo.isEmpty ? nil : newMemo
        book = updated
        Task {
            do {
                try await repos.books.updateBook(updated)
            } catch {
                // 楽観更新のロールバック（鮮度ガードつき・設計メモ 4.5節）。
                // 待つ間に別操作が新しい値を入れていたら踏み潰さない。エラーUIは新設しない（前提13）
                if let value = OptimisticUpdate.rollbackValue(
                    current: book,
                    optimistic: updated,
                    previous: previous
                ) {
                    book = value
                }
            }
        }
    }

    private func deleteBook() {
        let id = book.id
        Task {
            do {
                try await repos.books.deleteBook(id: id)
            } catch {
                // 削除に失敗したら画面を閉じない（レビュー S4-13）
                return
            }
            dismiss()
            onDeleted()
        }
    }

    private func saveChanges() {
        var updated = book
        if isManual {
            updated.title = title.trimmingCharacters(in: .whitespaces)
            updated.author = author.isEmpty ? nil : author.trimmingCharacters(in: .whitespaces)
            if let price = updated.storedCurrency.minorUnits(fromInput: priceText) {
                updated.price = price
                updated.priceAtRegistration = price
            }
        }

        let cover: CoverImageUpdate
        if imageChanged {
            let newCoverData = selectedImage.flatMap { compressedImageData(from: $0) }
            cover = .replace(newCoverData)
            updated.hasCoverImage = (newCoverData?.isEmpty == false)
            if updated.hasCoverImage, BookCoverImageURL.isRakutenPlaceholder(updated.imageURL) {
                updated.imageURL = nil
            }
        } else {
            cover = .unchanged
        }

        updated.isFavorite = isFavorite

        // 登録日は未来日を許可しない（DatePicker でも制限しているが、旧データ含め保存時にも保証する）
        updated.registeredAt = min(registeredAt, registeredAtUpperBound)
        if let id = selectedPassbookID {
            updated.passbookId = id
        }
        if bookFieldsChanged {
            updated.updatedAt = Date()
        }

        var rereadDateUpdates: [String: Date] = [:]
        for row in draftRereadRows {
            guard let original = book.rereads.first(where: { $0.id == row.record.id }) else { continue }
            guard !Calendar.current.isDate(original.date, inSameDayAs: row.record.date) else { continue }
            rereadDateUpdates[row.record.id] = row.record.date
        }

        let toSave = updated
        Task {
            do {
                try await repos.books.saveBookEdits(
                    toSave,
                    cover: cover,
                    deletedRereadIDs: deletedRereadIDs,
                    rereadDateUpdates: rereadDateUpdates,
                    updatesBookFields: bookFieldsChanged
                )
            } catch RepositoryError.bookNotFound {
                // 編集中に本が消えている＝書き戻す先が無い。シートを閉じるのが現行と同じ見え
                // （「閉じてよいか」のUX判断はリポジトリではなくここが持つ・設計メモ 4.5節）
                dismiss()
                return
            } catch {
                // それ以外の失敗ではシートを閉じない（旧実装の do/catch と同じ・レビュー S4-17）
                return
            }
            dismiss()
        }
    }

    private func rereadDateBinding(for rowID: String) -> Binding<Date> {
        Binding(
            get: { draftRereadRows.first(where: { $0.id == rowID })?.record.date ?? registeredAt },
            set: { newDate in
                guard let index = draftRereadRows.firstIndex(where: { $0.id == rowID }) else { return }
                draftRereadRows[index].record.date = newDate
            }
        )
    }

}

/// 編集中の再読1行。保存用の `record.id` とは別に、画面上の行だけを一意に識別する。
private struct DraftRereadRow: Identifiable {
    let id: String
    var record: RereadRecord

    init(record: RereadRecord, id: String = UUID().uuidString) {
        self.id = id
        self.record = record
    }
}

// MARK: - Preview

// ※ 2つの #Preview が同一内容になっている件（source 差分が見えない）は
//   設計メモ 8.3節-5(a) のとおりステップ6で是正する。ここでは DTO 化のみ行う。
#Preview("手動登録の本") {
    Group {
        if let book = PreviewSupport.book(source: .manual) {
            EditBookView(book: book)
        } else {
            Text("No preview book")
        }
    }
    .bookBankPreviewEnvironment()
}

#Preview("API取得の本") {
    Group {
        if let book = PreviewSupport.book(source: .api) {
            EditBookView(book: book)
        } else {
            Text("No preview book")
        }
    }
    .bookBankPreviewEnvironment()
}
