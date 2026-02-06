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
                Section(header: Text("カメラ情報")) {
                    HStack {
                        Text("カメラ名")
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(cameraLink.cameraDeviceName)
                            .foregroundColor(.mioTextPrimary)
                    }
                    
                    if let camera = cameraInfo {
                        HStack {
                            Text("機種")
                                .foregroundColor(.mioTextSecondary)
                            Spacer()
                            Text(camera.deviceModel ?? "不明")
                                .foregroundColor(.mioTextPrimary)
                        }
                        
                        HStack {
                            Text("接続状態")
                                .foregroundColor(.mioTextSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(camera.isOnline ? Color.mioSuccess : Color.mioError)
                                    .frame(width: 8, height: 8)
                                Text(camera.isOnline ? "オンライン" : "オフライン")
                                    .foregroundColor(camera.isOnline ? .mioSuccess : .mioError)
                            }
                        }
                        
                        if let batteryLevel = camera.batteryLevel {
                            HStack {
                                Text("バッテリー")
                                    .foregroundColor(.mioTextSecondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: batteryIcon(level: batteryLevel))
                                        .foregroundColor(batteryColor(level: batteryLevel))
                                    Text("\(batteryLevel)%")
                                        .foregroundColor(batteryColor(level: batteryLevel))
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
                            Text("カメラの接続を解除")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
                
                // アカウント情報
                Section {
                    HStack {
                        Text("アカウント")
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(authService.currentUser?.displayName ?? "匿名ユーザー")
                            .foregroundColor(.mioTextSecondary)
                    }
                    
                    HStack {
                        Text("バージョン")
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.mioTextSecondary)
                    }
                }
            }
            .navigationTitle("モニター設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .alert("接続を解除", isPresented: $showDisconnectAlert) {
            Button("解除", role: .destructive) {
                disconnect()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このカメラとの接続を解除しますか？再度接続するにはQRコードのスキャンが必要です。")
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
    
    // MARK: - Battery Display
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<10:
            return "battery.0"
        case 10..<25:
            return "battery.25"
        case 25..<50:
            return "battery.50"
        case 50..<75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0..<10:
            return .mioError
        case 10..<20:
            return .mioWarning
        default:
            return .mioTextPrimary
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
