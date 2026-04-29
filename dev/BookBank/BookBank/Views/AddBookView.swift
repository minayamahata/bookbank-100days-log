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
    
    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var context
    
    /// モーダルを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// 登録先の口座（初期値）
    let passbook: Passbook
    
    /// 口座選択を許可するかどうか
    let allowPassbookChange: Bool
    
    /// 保存成功時のコールバック（親画面を閉じるため）
    var onSave: (() -> Void)?
    
    // MARK: - SwiftData Query
    
    /// すべての口座を取得
    @Query(sort: \Passbook.sortOrder) private var allPassbooks: [Passbook]
    
    /// カスタム口座のみ取得
    private var customPassbooks: [Passbook] {
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
    @State private var selectedPassbook: Passbook?
    
    /// 書籍タイトル（必須）
    @State private var title: String = ""
    
    /// 著者名（任意）
    @State private var author: String = ""
    
    /// 価格（任意）
    @State private var priceText: String = ""
    
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
    
    init(passbook: Passbook, allowPassbookChange: Bool = false, onSave: (() -> Void)? = nil) {
        self.passbook = passbook
        self.allowPassbookChange = allowPassbookChange
        self.onSave = onSave
        _selectedPassbook = State(initialValue: passbook)
    }
    
    // MARK: - Validation
    
    /// 保存ボタンが有効かどうか（タイトルと金額が必須）
    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasValidPrice = Int(priceText) != nil && !priceText.isEmpty
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
                                Text("写真を削除")
                                    .font(.caption)
                            }
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
                                    Text("表紙画像")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            
                            Menu {
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    Label("ライブラリから選択", systemImage: "photo.on.rectangle")
                                }
                                
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button {
                                        focusedField = nil
                                        requestCameraAccess()
                                    } label: {
                                        Label("カメラで撮影", systemImage: "camera")
                                    }
                                }
                            } label: {
                                Text("写真を登録する")
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
                            Text("本のタイトル")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        TextField("タイトルを入力", text: $title)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .title)
                    }

                    // 著者名（任意）
                    TextField("著者名", text: $author)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .author)

                    // 価格（必須）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("価格")
                            Text("*")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack {
                            Text("¥")
                                .foregroundColor(.secondary)
                            TextField("価格を入力（半角数字）", text: $priceText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .price)
                        }
                    }
                }

                // 口座選択（allowPassbookChangeがtrueの場合のみ表示）
                if allowPassbookChange {
                    Section {
                        Picker("口座", selection: $selectedPassbook) {
                            ForEach(customPassbooks) { passbook in
                                Text(passbook.name)
                                    .foregroundColor(.primary)
                                    .tag(passbook as Passbook?)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeColor)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle("本の登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタン
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                // 保存ボタン
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
            .alert("カメラへのアクセスが許可されていません", isPresented: $showCameraDeniedAlert) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("本の表紙を撮影するには、「設定」からカメラへのアクセスを許可してください。")
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
    
    /// 本を保存する
    private func saveBook() {
        guard let price = Int(priceText),
              let targetPassbook = selectedPassbook else {
            return
        }
        
        let imageData = selectedImage.flatMap { compressedImageData(from: $0) }
        
        let newBook = UserBook(
            title: title.trimmingCharacters(in: .whitespaces),
            author: author.isEmpty ? nil : author.trimmingCharacters(in: .whitespaces),
            isbn: nil,
            publisher: nil,
            publishedYear: nil,
            price: price,
            imageURL: nil,
            coverImageData: imageData,
            source: .manual,
            memo: nil,
            isFavorite: false,
            passbook: targetPassbook
        )
        
        context.insert(newBook)
        
        do {
            try context.save()
            dismiss()
            onSave?()
        } catch {
            #if DEBUG
            print("Error saving book: \(error)")
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Passbook.self, UserBook.self, configurations: config)
    
    let passbook = Passbook(name: "漫画口座", type: .custom, sortOrder: 1)
    container.mainContext.insert(passbook)
    
    return AddBookView(passbook: passbook)
        .modelContainer(container)
}
