//
//  CameraModeView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
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
    @State private var showBlackoutView = false
    
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
        .navigationTitle(viewModel.deviceName.isEmpty ? String(localized: "camera") : viewModel.deviceName)
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
                showBlackoutView = false
                dismiss()
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
            captureService.stopCapture()
        }
        .alert(String(localized: "error"), isPresented: $showError) {
            Button("OK") {
                viewModel.errorMessage = nil
                showError = false
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert(String(localized: "camera_access_alert_title"), isPresented: $cameraPermissionDenied) {
            Button(String(localized: "open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "camera_access_alert_message"))
        }
        // カメラ登録済みの場合はブラックアウトモードへ遷移（接続数に関係なく）
        .fullScreenCover(isPresented: $showBlackoutView) {
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
            ProgressView(String(localized: "camera_preparing"))
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
            
            Text(String(localized: "camera_access_required"))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(String(localized: "camera_access_hint"))
                .font(.system(.body))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(String(localized: "open_settings"))
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
            
            Text(String(localized: "camera_registration_failed"))
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
                Text(String(localized: "retry"))
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
                    Text(viewModel.isOnline ? String(localized: "online") : String(localized: "offline"))
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
                            Text(String(localized: "pairing_alternative"))
                                .font(.system(.subheadline))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 12) {
                                VStack(spacing: 4) {
                                    Text(String(localized: "camera_id"))
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
                                    Text(String(localized: "tap_to_copy"))
                                        .font(.system(.caption2))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                VStack(spacing: 4) {
                                    Text(String(localized: "pairing_code"))
                                        .font(.system(.caption))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(QRCodeGenerator.formatPairingCode(pairingCode))
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
                                    Text(String(localized: "tap_to_copy"))
                                        .font(.system(.caption2))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            
                            Button {
                                showManualPairing = false
                            } label: {
                                Text(String(localized: "back_to_qr"))
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
                            Text(String(localized: "qr_instruction"))
                                .font(.system(.subheadline))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                            
                            if let qrImage = QRCodeGenerator.generateQRCode(cameraId: cameraId, pairingCode: pairingCode) {
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
                                Text(String(localized: "pairing_alternative"))
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
                    
                    Text(String(localized: "waiting_for_monitors"))
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
                showBlackoutView = true
            } else if viewModel.errorMessage != nil {
                showError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        CameraModeView()
            .environmentObject(AuthenticationService.shared)
    }
}
