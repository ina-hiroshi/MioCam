//
//  MonitorSettingsSheet.swift
//  MioCam
//
//  モニター側設定シート
//

import SwiftUI
import FirebaseFirestore

/// モニター側設定シート
struct MonitorSettingsSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject var viewModel: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    
    let cameraLink: MonitorLinkModel
    let cameraInfo: CameraModel?
    let onDisconnect: () -> Void
    
    @State private var showDisconnectAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // カメラ情報
                Section(header: Text(String(localized: "camera_info"))) {
                    HStack {
                        Text(String(localized: "camera_name"))
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(cameraLink.cameraDeviceName)
                            .foregroundColor(.mioTextPrimary)
                    }
                    
                    if let camera = cameraInfo {
                        HStack {
                            Text(String(localized: "device_model"))
                                .foregroundColor(.mioTextSecondary)
                            Spacer()
                            Text(camera.deviceModel ?? String(localized: "unknown"))
                                .foregroundColor(.mioTextPrimary)
                        }
                        
                        HStack {
                            Text(String(localized: "connection_status"))
                                .foregroundColor(.mioTextSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(camera.isOnline ? Color.mioSuccess : Color.mioError)
                                    .frame(width: 8, height: 8)
                                Text(camera.isOnline ? String(localized: "online") : String(localized: "offline"))
                                    .foregroundColor(camera.isOnline ? .mioSuccess : .mioError)
                            }
                        }
                        
                        if let batteryLevel = camera.batteryLevel {
                            HStack {
                                Text(String(localized: "battery"))
                                    .foregroundColor(.mioTextSecondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: BatteryDisplay.icon(level: batteryLevel))
                                        .foregroundColor(BatteryDisplay.color(level: batteryLevel))
                                    Text("\(batteryLevel)%")
                                        .foregroundColor(BatteryDisplay.color(level: batteryLevel))
                                }
                            }
                        }
                    }
                }
                
                // 接続解除
                Section {
                    Button(role: .destructive) {
                        showDisconnectAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "disconnect_camera"))
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
            .navigationTitle(String(localized: "monitor_settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) {
                        dismiss()
                    }
                }
            }
        }
        .alert(String(localized: "disconnect"), isPresented: $showDisconnectAlert) {
            Button(String(localized: "disconnect_button"), role: .destructive) {
                disconnect()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "disconnect_confirm_message"))
        }
    }
    
    // MARK: - Actions
    
    private func disconnect() {
        guard let userId = authService.currentUser?.uid else { return }
        
        Task {
            await viewModel.unpairCamera(monitorUserId: userId, cameraId: cameraLink.cameraId)
            dismiss()
            onDisconnect()
        }
    }
}

#Preview {
    let link = MonitorLinkModel(
        id: "test",
        monitorUserId: "user1",
        cameraId: "camera1",
        cameraDeviceName: "リビングのカメラ",
        pairedAt: Timestamp(date: Date()),
        isActive: true
    )
    
    let camera = CameraModel(
        id: "camera1",
        ownerUserId: "owner1",
        pairingCode: "ABC123",
        deviceName: "リビングのカメラ",
        deviceModel: "iPhone 12",
        osVersion: "16.0",
        pushToken: nil,
        isOnline: true,
        batteryLevel: 85,
        lastSeenAt: Timestamp(date: Date()),
        createdAt: Timestamp(date: Date()),
        connectedMonitorCount: 1
    )
    
    MonitorSettingsSheet(
        viewModel: MonitorViewModel(),
        cameraLink: link,
        cameraInfo: camera
    ) {}
        .environmentObject(AuthenticationService.shared)
}
