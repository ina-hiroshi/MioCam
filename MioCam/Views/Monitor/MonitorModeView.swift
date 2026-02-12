//
//  MonitorModeView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI

/// モニターモード画面
struct MonitorModeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var viewModel = MonitorViewModel()
    @State private var showQRScanner = false
    @State private var pairingError: String?
    @State private var showPairingError = false
    @State private var isPairing = false
    @State private var selectedCameraLink: MonitorLinkModel?
    
    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isLoading || isPairing {
                Spacer()
                ProgressView(isPairing ? String(localized: "pairing_in_progress") : String(localized: "loading"))
                    .foregroundColor(.mioTextSecondary)
                Spacer()
            } else if viewModel.pairedCameras.isEmpty {
                emptyStateView
            } else {
                cameraListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mioPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "monitor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundColor(.mioAccent)
                }
            }
        }
        .task {
            if let userId = authService.currentUser?.uid {
                viewModel.isLoading = true
                // 初回読み込み
                await viewModel.loadPairedCameras(monitorUserId: userId)
                // リアルタイム監視開始
                viewModel.startObservingPairedCameras(monitorUserId: userId)
            }
        }
        .onDisappear {
            viewModel.stopObservingPairedCameras()
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerView { cameraId, pairingCode in
                Task { await pairCamera(cameraId: cameraId, pairingCode: pairingCode) }
            }
        }
        .fullScreenCover(item: $selectedCameraLink) { link in
            LiveView(viewModel: viewModel, cameraLink: link)
                .environmentObject(authService)
        }
        .alert(String(localized: "pairing_error"), isPresented: $showPairingError) {
            Button("OK") {
                pairingError = nil
                showPairingError = false
            }
        } message: {
            if let error = pairingError {
                Text(error)
            }
        }
        .alert(String(localized: "error"), isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }
    
    // MARK: - 空の状態
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56))
                .foregroundColor(.mioTextSecondary.opacity(0.5))
            
            Text(String(localized: "no_paired_cameras"))
                .font(.system(.body, design: .rounded))
                .foregroundColor(.mioTextSecondary)
            
            Text(String(localized: "scan_to_pair"))
                .font(.system(.subheadline))
                .foregroundColor(.mioTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button {
                showQRScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(String(localized: "qr_scan_button"))
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.mioAccentSub)
                )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - カメラ一覧
    
    /// 同じcameraIdの重複を排除（最も新しいpairedAtのリンクを優先）
    private var uniquePairedCameras: [MonitorLinkModel] {
        var seen: Set<String> = []
        return viewModel.pairedCameras
            .filter { link in
                if seen.contains(link.cameraId) { return false }
                seen.insert(link.cameraId)
                return true
            }
    }
    
    private var cameraListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(uniquePairedCameras, id: \.cameraId) { link in
                    let cameraStatus = viewModel.cameraStatuses[link.cameraId]
                    let isOnline = cameraStatus?.isOnline ?? false
                    let canSelect = link.isActive && isOnline
                    
                    Button {
                        if canSelect {
                            selectedCameraLink = link
                        }
                    } label: {
                        CameraListRow(
                            link: link,
                            cameraStatus: cameraStatus
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!canSelect)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
    
    // MARK: - ペアリング処理
    
    private func pairCamera(cameraId: String, pairingCode: String) async {
        guard let userId = authService.currentUser?.uid else { return }
        isPairing = true
        pairingError = nil
        
        do {
            _ = try await viewModel.pairWithCamera(
                cameraId: cameraId,
                pairingCode: pairingCode,
                monitorUserId: userId
            )
        } catch {
            pairingError = error.localizedDescription
            showPairingError = true
        }
        
        isPairing = false
    }
}

// MARK: - カメラリスト行

private struct CameraListRow: View {
    let link: MonitorLinkModel
    let cameraStatus: CameraModel?
    
    private var isOnline: Bool {
        cameraStatus?.isOnline ?? false
    }
    
    private var canSelect: Bool {
        link.isActive && isOnline
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // アイコン
            ZStack {
                Circle()
                    .fill(canSelect ? Color.mioAccent.opacity(0.15) : Color.mioTextSecondary.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: isOnline ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 20))
                    .foregroundColor(canSelect ? .mioAccent : .mioTextSecondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(link.cameraDeviceName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.mioTextPrimary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline ? Color.mioSuccess : Color.mioError)
                        .frame(width: 6, height: 6)
                    
                    Text(isOnline ? String(localized: "online") : String(localized: "offline"))
                        .font(.system(.caption))
                        .foregroundColor(isOnline ? .mioSuccess : .mioError)
                    
                    if isOnline, let count = cameraStatus?.connectedMonitorCount {
                        Text("・")
                            .foregroundColor(.mioTextSecondary)
                        Text(String(format: String(localized: "cameras_connected_format"), count))
                            .font(.system(.caption))
                            .foregroundColor(.mioTextSecondary)
                    }
                }
            }
            
            Spacer()
            
            if canSelect {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mioTextSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.mioSecondaryBg)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}


#Preview {
    NavigationStack {
        MonitorModeView()
            .environmentObject(AuthenticationService.shared)
    }
}
