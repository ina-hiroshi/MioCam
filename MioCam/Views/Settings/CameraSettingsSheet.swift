//
//  CameraSettingsSheet.swift
//  MioCam
//
//  カメラ側設定シート
//

import SwiftUI

/// カメラ側設定シート
struct CameraSettingsSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onStopCamera: () -> Void
    
    @State private var showQRCode = false
    @State private var showRegeneratePairingCodeAlert = false
    @State private var showStopCameraAlert = false
    @State private var showNameUpdateError = false
    @State private var showManualPairing = false
    @State private var cameraName: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                // QRコード再表示
                Section {
                    Button {
                        showQRCode = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundColor(.mioAccent)
                                .frame(width: 24)
                            Text(String(localized: "show_qr_code"))
                                .foregroundColor(.mioTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.mioTextSecondary)
                        }
                    }
                    
                    Button {
                        showRegeneratePairingCodeAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.mioAccent)
                                .frame(width: 24)
                            Text(String(localized: "regenerate_pairing_code"))
                                .foregroundColor(.mioTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.mioTextSecondary)
                        }
                    }
                }
                
                // 接続中モニター
                Section(header: Text(String(localized: "connected_monitors"))) {
                    if viewModel.connectedMonitors.isEmpty {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.mioTextSecondary)
                                .frame(width: 24)
                            Text(String(localized: "no_connected_monitors"))
                                .foregroundColor(.mioTextSecondary)
                        }
                    } else {
                        // ユーザー単位でグループ化（同じuserIdのモニターをまとめる）
                        let groupedMonitors = Dictionary(grouping: viewModel.connectedMonitors) { $0.monitorUserId }
                        
                        ForEach(Array(groupedMonitors.keys.sorted()), id: \.self) { userId in
                            if let monitors = groupedMonitors[userId],
                               let firstMonitor = monitors.first {
                                let isAudioEnabled = viewModel.connectedMonitors.first(where: { $0.monitorUserId == userId })?.isAudioEnabled ?? false
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: isAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                            .foregroundColor(isAudioEnabled ? .mioAccent : .mioTextSecondary)
                                            .frame(width: 24)
                                        
                                        Text(firstMonitor.displayName)
                                            .foregroundColor(.mioTextPrimary)
                                        
                                        Spacer()
                                        
                                        Toggle("", isOn: Binding(
                                            get: { isAudioEnabled },
                                            set: { enabled in
                                                viewModel.toggleAudioForUser(userId: userId, enabled: enabled)
                                            }
                                        ))
                                    }
                                    
                                    // デバイス名を表示（複数ある場合は全て表示）
                                    ForEach(monitors, id: \.id) { monitor in
                                        Text(monitor.deviceName)
                                            .font(.system(.caption))
                                            .foregroundColor(.mioTextSecondary)
                                            .padding(.leading, 28)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                // カメラ名
                Section(header: Text(String(localized: "camera_name"))) {
                    TextField(String(localized: "camera_name_placeholder"), text: $cameraName)
                        .onAppear {
                            cameraName = viewModel.deviceName
                        }
                        .onSubmit {
                            guard !cameraName.isEmpty else { return }
                            guard viewModel.cameraId != nil else {
                                showNameUpdateError = true
                                return
                            }
                            Task {
                                await viewModel.updateDeviceName(cameraName)
                            }
                        }
                        .disabled(viewModel.cameraId == nil)
                }
                
                // カメラ停止
                Section {
                    Button(role: .destructive) {
                        showStopCameraAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "stop_camera"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
                
                // アカウント情報
                Section {
                    HStack {
                        Text(String(localized: "account"))
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(authService.currentUser?.displayName ?? String(localized: "anonymous_user"))
                            .foregroundColor(.mioTextSecondary)
                    }
                    
                    HStack {
                        Text(String(localized: "version"))
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.mioTextSecondary)
                    }
                }
            }
            .navigationTitle(String(localized: "camera_settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showQRCode) {
            qrCodeSheet
        }
        .alert(String(localized: "regenerate_pairing_code"), isPresented: $showRegeneratePairingCodeAlert) {
            Button(String(localized: "regenerate"), role: .destructive) {
                Task {
                    await viewModel.regeneratePairingCode()
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            if viewModel.connectedMonitors.isEmpty {
                Text(String(localized: "regenerate_pairing_alert_message"))
            } else {
                Text(String(localized: "regenerate_pairing_alert_detail"))
            }
        }
        .alert(String(localized: "stop_camera"), isPresented: $showStopCameraAlert) {
            Button(String(localized: "stop"), role: .destructive) {
                dismiss()
                onStopCamera()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "stop_camera_alert_message"))
        }
        .alert(String(localized: "error"), isPresented: $showNameUpdateError) {
            Button("OK") {
                showNameUpdateError = false
            }
        } message: {
            Text(String(localized: "camera_not_registered"))
        }
    }
    
    // MARK: - QRコード表示シート
    
    private var qrCodeSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                if let cameraId = viewModel.cameraId, let pairingCode = viewModel.pairingCode {
                    if showManualPairing {
                        // 手動ペアリング情報表示
                        VStack(spacing: 20) {
                            Text(String(localized: "pairing_alternative"))
                                .font(.system(.body))
                                .foregroundColor(.mioTextSecondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 16) {
                                VStack(spacing: 4) {
                                    Text(String(localized: "camera_id"))
                                        .font(.system(.caption))
                                        .foregroundColor(.mioTextSecondary)
                                    
                                    Text(cameraId)
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.mioAccent)
                                        .onTapGesture {
                                            UIPasteboard.general.string = cameraId
                                        }
                                    
                                    Text(String(localized: "tap_to_copy"))
                                        .font(.system(.caption2))
                                        .foregroundColor(.mioTextSecondary.opacity(0.7))
                                }
                                
                                VStack(spacing: 4) {
                                    Text(String(localized: "pairing_code"))
                                        .font(.system(.caption))
                                        .foregroundColor(.mioTextSecondary)
                                    
                                    Text(QRCodeGenerator.formatPairingCode(pairingCode))
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.mioAccent)
                                        .onTapGesture {
                                            UIPasteboard.general.string = pairingCode
                                        }
                                    
                                    Text(String(localized: "tap_to_copy"))
                                        .font(.system(.caption2))
                                        .foregroundColor(.mioTextSecondary.opacity(0.7))
                                }
                            }
                            
                            Button {
                                showManualPairing = false
                            } label: {
                                Text(String(localized: "back_to_qr"))
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(.mioAccent)
                            }
                        }
                    } else {
                        // QRコード表示
                        Text(String(localized: "qr_instruction"))
                            .font(.system(.body))
                            .foregroundColor(.mioTextSecondary)
                            .multilineTextAlignment(.center)
                        
                        if let qrImage = QRCodeGenerator.generateQRCode(cameraId: cameraId, pairingCode: pairingCode) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        }
                        
                        Button {
                            showManualPairing = true
                        } label: {
                            Text(String(localized: "pairing_alternative"))
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.mioAccent)
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color.mioPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "qr_code_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "close")) {
                        showQRCode = false
                    }
                }
            }
        }
    }
}

#Preview {
    CameraSettingsSheet(viewModel: CameraViewModel()) {}
        .environmentObject(AuthenticationService.shared)
}
