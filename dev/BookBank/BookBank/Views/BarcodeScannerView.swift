//
//  BarcodeScannerView.swift
//  BookBank
//
//  Created by YAMAHATA Mina on 2026/01/22.
//

import SwiftUI
import AVFoundation

/// バーコードスキャナーView
/// ISBN-13（EAN-13）とISBN-10のバーコードを読み取る
struct BarcodeScannerView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// スキャン完了時のコールバック（ISBNを返す）
    let onScanComplete: (String) -> Void
    
    // MARK: - State
    
    /// カメラ権限の状態
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    
    /// エラーメッセージ
    @State private var errorMessage: String?
    
    /// スキャン済みフラグ（重複スキャン防止）
    @State private var hasScanned: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // 背景を黒に
            Color.black.ignoresSafeArea()
            
            // カメラプレビュー
            if cameraPermission == .authorized {
                CameraPreviewView(
                    onBarcodeDetected: { barcode in
                        handleBarcodeDetected(barcode)
                    },
                    onError: { error in
                        errorMessage = error
                    }
                )
                .ignoresSafeArea()
                
                // スキャンエリア外を暗くするオーバーレイ
                ScanAreaOverlay(scanAreaSize: CGSize(width: 280, height: 80))
                    .ignoresSafeArea()

                // スキャンガイドとUI
                VStack {
                    // 上部のクローズボタン
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .padding(.leading, 20)
                        .padding(.top, 16)

                        Spacer()
                    }

                    Spacer()

                    // スキャンエリアのガイド（四隅のカッコ）
                    CornerBracketShape()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: 280, height: 80)

                    Text("バーコードをこの枠内に合わせてください")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.top, 16)
                        .shadow(color: .black, radius: 2, x: 0, y: 1)

                    Spacer()
                    Spacer()
                }
            } else if cameraPermission == .denied || cameraPermission == .restricted {
                // カメラ権限がない場合
                VStack(spacing: 24) {
                    // クローズボタン
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .padding(.leading, 20)
                        .padding(.top, 16)
                        
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("カメラへのアクセスが必要です")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("本のバーコードを読み取るには、\nカメラへのアクセスを許可してください")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    Button(action: openSettings) {
                        Text("設定を開く")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .padding()
            } else {
                // 権限確認中
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("カメラを準備中...")
                        .foregroundColor(.gray)
                }
            }
            
            // エラーメッセージ
            if let error = errorMessage {
                VStack {
                    Spacer()
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding()
                        .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }
    
    // MARK: - Actions
    
    /// カメラ権限を確認
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = status
        
        if status == .notDetermined {
            // 権限をリクエスト
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        }
    }
    
    /// 設定アプリを開く
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    /// バーコード検出時の処理
    private func handleBarcodeDetected(_ barcode: String) {
        // 重複スキャン防止
        guard !hasScanned else { return }
        
        // ISBNの検証（10桁または13桁の数字）
        let cleanBarcode = barcode.replacingOccurrences(of: "-", with: "")
        
        // ISBN-13は978または979で始まる13桁
        // ISBN-10は10桁
        if (cleanBarcode.count == 13 && (cleanBarcode.hasPrefix("978") || cleanBarcode.hasPrefix("979"))) ||
           cleanBarcode.count == 10 {
            hasScanned = true
            
            // 触覚フィードバック
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // コールバックを呼び出してモーダルを閉じる
            onScanComplete(cleanBarcode)
            dismiss()
        }
    }
}

// MARK: - CameraPreviewView

/// AVFoundationを使用したカメラプレビュー
struct CameraPreviewView: UIViewRepresentable {
    
    let onBarcodeDetected: (String) -> Void
    let onError: (String) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.onBarcodeDetected = onBarcodeDetected
        view.onError = onError
        view.setupCamera()
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // 何もしない（レイアウトはCameraPreviewUIView内で処理）
    }
    
    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.stopCamera()
    }
}

/// カメラプレビュー用のカスタムUIView
class CameraPreviewUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    
    var onBarcodeDetected: ((String) -> Void)?
    var onError: ((String) -> Void)?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // レイアウト変更時にプレビューレイヤーのフレームを更新
        previewLayer?.frame = bounds
    }
    
    func setupCamera() {
        // カメラセッションの設定
        let captureSession = AVCaptureSession()
        self.captureSession = captureSession
        
        // 高解像度設定（バーコード認識精度向上）
        captureSession.sessionPreset = .hd1920x1080
        
        // カメラデバイスの取得
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("カメラが見つかりません")
            }
            return
        }
        
        // オートフォーカスの設定
        do {
            try videoCaptureDevice.lockForConfiguration()
            
            // フォーカス範囲制限を解除（様々な距離に対応）
            if videoCaptureDevice.isAutoFocusRangeRestrictionSupported {
                videoCaptureDevice.autoFocusRangeRestriction = .none
            }
            
            // 連続オートフォーカスを有効化
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            
            videoCaptureDevice.unlockForConfiguration()
        } catch {
            // 設定に失敗しても続行
        }
        
        // 入力の設定
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("カメラの初期化に失敗しました")
            }
            return
        }
        
        // 出力の設定（バーコード読み取り）
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            // 高優先度のキューを使用
            let metadataQueue = DispatchQueue(label: "barcode.metadata", qos: .userInteractive)
            metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
            
            // ISBNに必要なタイプのみに絞る（高速化）
            metadataOutput.metadataObjectTypes = [.ean13]
        }
        
        // プレビューレイヤーの設定
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        
        // セッション開始
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
    
    func stopCamera() {
        captureSession?.stopRunning()
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                       didOutput metadataObjects: [AVMetadataObject],
                       from connection: AVCaptureConnection) {
        // バーコードが検出された（メインスレッドでコールバック）
        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {
            DispatchQueue.main.async { [weak self] in
                self?.onBarcodeDetected?(stringValue)
            }
        }
    }
}

// MARK: - ScanAreaOverlay

/// スキャンエリア以外を暗くするオーバーレイ
struct ScanAreaOverlay: View {
    let scanAreaSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let scanRect = CGRect(
                x: (geometry.size.width - scanAreaSize.width) / 2,
                y: (geometry.size.height - scanAreaSize.height) / 2,
                width: scanAreaSize.width,
                height: scanAreaSize.height
            )

            Path { path in
                // 全体を覆う
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                // スキャンエリアを切り抜く
                path.addRect(scanRect)
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
        }
    }
}

// MARK: - CornerBracketShape

/// 四隅のL字型カッコ形状のスキャンガイド
struct CornerBracketShape: Shape {
    /// コーナーの長さ
    var cornerLength: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 左上 ┌
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

        // 右上 ┐
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

        // 左下 └
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

        // 右下 ┘
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))

        return path
    }
}

// MARK: - Preview

#Preview {
    BarcodeScannerView { isbn in
        print("Scanned ISBN: \(isbn)")
    }
}
