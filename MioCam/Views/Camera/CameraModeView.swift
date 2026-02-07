//
//  CameraModeView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

/// カメラモード画面
struct CameraModeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CameraViewModel()
    @State private var hasRegistered = false
    @State private var showError = false
    @State private var cameraPermissionDenied = false
    @State private var isCameraStarted = false
    @State private var showSettings = false
    @State private var showManualPairing = false
    @State private var shouldDismissToRoleSelection = false
    
    private let captureService = CameraCaptureService.shared
    
    var body: some View {
        ZStack {
            // カメラプレビュー背景
            if isCameraStarted {
                CameraPreviewView(captureService: captureService)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
            
            // コンテンツオーバーレイ
            contentOverlay
        }
        .navigationTitle(viewModel.deviceName.isEmpty ? "カメラ" : viewModel.deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasRegistered || viewModel.cameraId != nil {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(viewModel: viewModel) {
                // カメラ停止時の処理
                viewModel.stopCamera()
                captureService.stopCapture()
                isCameraStarted = false
                hasRegistered = false
                shouldDismissToRoleSelection = true
            }
            .environmentObject(authService)
        }
        .onChange(of: shouldDismissToRoleSelection) { newValue in
            if newValue {
                dismiss()
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            captureService.stopCapture()
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {
                viewModel.errorMessage = nil
                showError = false
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert("カメラへのアクセス", isPresented: $cameraPermissionDenied) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("カメラを使用するには、設定アプリでカメラへのアクセスを許可してください。")
        }
        // カメラ登録済みの場合はブラックアウトモードへ遷移（接続数に関係なく）
        .fullScreenCover(isPresented: .init(
            get: { hasRegistered && !shouldDismissToRoleSelection },
            set: { isPresented in
                // fullScreenCoverが閉じられた時（BlackoutViewから戻った時）
                if !isPresented {
                    // カメラが停止されている場合（isOnline=false または shouldDismissToRoleSelection=true）は役割選択画面に戻る
                    // 接続数が0になってもカメラモードは維持する
                    if !viewModel.isOnline || shouldDismissToRoleSelection {
                        // onChangeを確実に呼び出すために、一度falseにリセットしてからtrueに設定
                        shouldDismissToRoleSelection = false
                        DispatchQueue.main.async {
                            shouldDismissToRoleSelection = true
                        }
                    }
                }
            }
        )) {
            BlackoutView(viewModel: viewModel) {
                // カメラ停止時の処理（BlackoutView → CameraModeView）
                viewModel.stopCamera()
                captureService.stopCapture()
                isCameraStarted = false
                hasRegistered = false
                shouldDismissToRoleSelection = true
            }
            .environmentObject(authService)
        }
    }
    
    // MARK: - コンテンツオーバーレイ
    
    @ViewBuilder
    private var contentOverlay: some View {
        if viewModel.isLoading {
            loadingView
        } else if cameraPermissionDenied {
            permissionDeniedView
        } else if hasRegistered {
            cameraInfoOverlay
        } else if viewModel.errorMessage != nil {
            errorView
        } else {
            loadingView
        }
    }
    
    // MARK: - ローディング表示
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("カメラを準備中...")
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                )
            Spacer()
        }
    }
    
    // MARK: - 権限拒否表示
    
    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.7))
            
            Text("カメラへのアクセスが必要です")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("設定アプリからカメラへのアクセスを許可してください")
                .font(.system(.body))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("設定を開く")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.mioAccent)
                    )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - エラー表示
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.mioError)
            
            Text("カメラ登録に失敗しました")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(.body))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                Task {
                    await setupCamera()
                }
            } label: {
                Text("再試行")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.mioAccent)
                    )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - カメラ情報オーバーレイ（QRコード付き）
    
    private var cameraInfoOverlay: some View {
        VStack(spacing: 0) {
            // 上部グラデーション
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            
            Spacer()
            
            // QRコード表示エリア
            VStack(spacing: 16) {
                // ステータス表示
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isOnline ? Color.mioSuccess : Color.mioError)
                        .frame(width: 10, height: 10)
                    Text(viewModel.isOnline ? "オンライン" : "オフライン")
                        .font(.system(.subheadline))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
                
                // QRコードまたは手動ペアリング情報
                if let cameraId = viewModel.cameraId, let pairingCode = viewModel.pairingCode {
                    if showManualPairing {
                        // 手動ペアリング情報表示
                        VStack(spacing: 16) {
                            Text("QRコード以外でペアリングする")
                                .font(.system(.subheadline))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 12) {
                                VStack(spacing: 4) {
                                    Text("カメラID")
                                        .font(.system(.caption))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(cameraId)
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.mioAccent.opacity(0.8))
                                        )
                                        .onTapGesture {
                                            UIPasteboard.general.string = cameraId
                                        }
                                    Text("タップしてコピー")
                                        .font(.system(.caption2))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                VStack(spacing: 4) {
                                    Text("ペアリングコード")
                                        .font(.system(.caption))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(formatPairingCode(pairingCode))
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.mioAccent.opacity(0.8))
                                        )
                                        .onTapGesture {
                                            UIPasteboard.general.string = pairingCode
                                        }
                                    Text("タップしてコピー")
                                        .font(.system(.caption2))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            
                            Button {
                                showManualPairing = false
                            } label: {
                                Text("QRコードに戻る")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.2))
                                    )
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        // QRコード表示
                        VStack(spacing: 12) {
                            Text("モニターでこのQRコードを読み取ってください")
                                .font(.system(.subheadline))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                            
                            if let qrImage = generateQRCode(cameraId: cameraId, pairingCode: pairingCode) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                            }
                            
                            Button {
                                showManualPairing = true
                            } label: {
                                Text("QRコード以外でペアリングする")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.2))
                                    )
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                
                // 接続待ちインジケータ
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.mioAccent)
                        .frame(width: 8, height: 8)
                        .opacity(0.7)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: true)
                    
                    Text("モニターの接続を待っています...")
                        .font(.system(.footnote))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 16)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.7))
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // 下部グラデーション
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
        }
    }
    
    // MARK: - Setup
    
    private func setupCamera() async {
        // カメラ権限チェック
        let cameraStatus = CameraCaptureService.authorizationStatus
        
        switch cameraStatus {
        case .notDetermined:
            let granted = await CameraCaptureService.requestAuthorization()
            if !granted {
                cameraPermissionDenied = true
                return
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
            return
        case .authorized:
            break
        @unknown default:
            break
        }
        
        // マイク権限チェック
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            // マイク権限が拒否されていてもカメラ機能は使用可能（音声のみ無効）
            print("マイク権限が拒否されています。音声機能は使用できません。")
        case .authorized:
            break
        @unknown default:
            break
        }
        
        // カメラ起動
        do {
            try await captureService.startCapture(position: .back)
            isCameraStarted = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
            showError = true
            return
        }
        
        // カメラ登録
        if !hasRegistered, let userId = authService.currentUser?.uid {
            await viewModel.registerCamera(ownerUserId: userId)
            if viewModel.errorMessage == nil && viewModel.cameraId != nil {
                hasRegistered = true
            } else if viewModel.errorMessage != nil {
                showError = true
            }
        }
    }
    
    // MARK: - QRコード生成
    
    /// cameraId + pairingCode を JSON → Base64 → QRコード画像に変換
    private func generateQRCode(cameraId: String, pairingCode: String) -> UIImage? {
        let payload: [String: String] = [
            "cameraId": cameraId,
            "pairingCode": pairingCode
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // QRコードを拡大（デフォルトは非常に小さい）
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - ペアリングコードフォーマット
    
    private func formatPairingCode(_ code: String) -> String {
        return code
    }
}

#Preview {
    NavigationStack {
        CameraModeView()
            .environmentObject(AuthenticationService.shared)
    }
}
