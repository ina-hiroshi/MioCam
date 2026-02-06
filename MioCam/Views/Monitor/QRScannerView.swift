//
//  QRScannerView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import AVFoundation

/// QRコードスキャナー画面
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScanned: (String, String) -> Void  // (cameraId, pairingCode)
    
    @State private var isScanning = true
    @State private var scannedMessage: String?
    @State private var showManualEntry = false
    @State private var manualCameraId = ""
    @State private var manualPairingCode = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // カメラプレビュー
                if isScanning {
                    QRCodeScannerRepresentable { code in
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()
                }
                
                // オーバーレイ
                VStack {
                    Spacer()
                    
                    // スキャンエリアガイド
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.mioAccent, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .background(Color.clear)
                    
                    Spacer()
                    
                    // 説明テキスト
                    VStack(spacing: 12) {
                        Text("カメラのQRコードを読み取ってください")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Button {
                            showManualEntry = true
                        } label: {
                            Text("コードを手入力する")
                                .font(.system(.footnote))
                                .foregroundColor(.mioAccent)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.9))
                                )
                        }
                    }
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("QRスキャン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                manualEntrySheet
            }
        }
    }
    
    // MARK: - QRコード処理
    
    private func handleScannedCode(_ code: String) {
        guard isScanning else { return }
        isScanning = false
        
        // JSON文字列をパース（QRコードにはcameraId+pairingCodeのJSONが含まれる）
        if let data = code.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let cameraId = json["cameraId"],
           let pairingCode = json["pairingCode"] {
            onScanned(cameraId, pairingCode)
            dismiss()
        } else {
            // パース失敗 → 再スキャン
            scannedMessage = "無効なQRコードです。カメラアプリのQRを読み取ってください。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                scannedMessage = nil
                isScanning = true
            }
        }
    }
    
    // MARK: - 手入力シート
    
    private var manualEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("カメラのペアリング情報を入力してください")
                    .font(.system(.body))
                    .foregroundColor(.mioTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("カメラID")
                            .font(.system(.caption))
                            .foregroundColor(.mioTextSecondary)
                        Text("カメラ側の画面に表示されているカメラIDを入力してください")
                            .font(.system(.caption2))
                            .foregroundColor(.mioTextSecondary)
                            .padding(.bottom, 4)
                        TextField("カメラIDを入力", text: $manualCameraId)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ペアリングコード")
                            .font(.system(.caption))
                            .foregroundColor(.mioTextSecondary)
                        Text("6桁の英数字コード（例: ABC123）")
                            .font(.system(.caption2))
                            .foregroundColor(.mioTextSecondary)
                            .padding(.bottom, 4)
                        TextField("6桁のコードを入力", text: $manualPairingCode)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 24)
                }
                
                Button {
                    guard !manualCameraId.isEmpty, !manualPairingCode.isEmpty else { return }
                    showManualEntry = false
                    onScanned(manualCameraId, manualPairingCode)
                    dismiss()
                } label: {
                    Text("ペアリング")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.mioAccentSub)
                        )
                }
                .padding(.horizontal, 24)
                .disabled(manualCameraId.isEmpty || manualPairingCode.isEmpty)
                
                Spacer()
            }
            .background(Color.mioPrimary.ignoresSafeArea())
            .navigationTitle("手入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showManualEntry = false
                    }
                }
            }
        }
    }
}

// MARK: - AVFoundation QRコードスキャナー

struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onScanned = onScanned
        return vc
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        
        captureSession = session
        previewLayer = preview
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let value = metadataObject.stringValue else {
            return
        }
        
        // 1回だけコールバック
        captureSession?.stopRunning()
        onScanned?(value)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
