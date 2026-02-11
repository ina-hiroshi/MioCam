//
//  CameraSettingsSheet.swift
//  MioCam
//
//  カメラ側設定シート
//

import SwiftUI
import CoreImage.CIFilterBuiltins

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
                            Text("QRコードを表示")
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
                            Text("ペアリングコードを再生成")
                                .foregroundColor(.mioTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.mioTextSecondary)
                        }
                    }
                }
                
                // 接続中モニター
                Section(header: Text("接続中のモニター")) {
                    if viewModel.connectedMonitors.isEmpty {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.mioTextSecondary)
                                .frame(width: 24)
                            Text("接続中のモニターはありません")
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
                Section(header: Text("カメラ名")) {
                    TextField("カメラ名を入力", text: $cameraName)
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
                            Text("カメラを停止する")
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
            .navigationTitle("カメラ設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showQRCode) {
            qrCodeSheet
        }
        .alert("ペアリングコードを再生成", isPresented: $showRegeneratePairingCodeAlert) {
            Button("再生成", role: .destructive) {
                Task {
                    await viewModel.regeneratePairingCode()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if viewModel.connectedMonitors.isEmpty {
                Text("ペアリングコードを再生成します。")
            } else {
                Text("再生成すると、現在接続中のモニターはすべて切断されます。続けますか？")
            }
        }
        .alert("カメラを停止", isPresented: $showStopCameraAlert) {
            Button("停止", role: .destructive) {
                dismiss()
                onStopCamera()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("カメラを停止すると、すべてのモニターとの接続が切断されます。")
        }
        .alert("エラー", isPresented: $showNameUpdateError) {
            Button("OK") {
                showNameUpdateError = false
            }
        } message: {
            Text("カメラが登録されていません。カメラを起動してから再度お試しください。")
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
                            Text("QRコード以外でペアリングする")
                                .font(.system(.body))
                                .foregroundColor(.mioTextSecondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 16) {
                                VStack(spacing: 4) {
                                    Text("カメラID")
                                        .font(.system(.caption))
                                        .foregroundColor(.mioTextSecondary)
                                    
                                    Text(cameraId)
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.mioAccent)
                                        .onTapGesture {
                                            UIPasteboard.general.string = cameraId
                                        }
                                    
                                    Text("タップしてコピー")
                                        .font(.system(.caption2))
                                        .foregroundColor(.mioTextSecondary.opacity(0.7))
                                }
                                
                                VStack(spacing: 4) {
                                    Text("ペアリングコード")
                                        .font(.system(.caption))
                                        .foregroundColor(.mioTextSecondary)
                                    
                                    Text(formatPairingCode(pairingCode))
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.mioAccent)
                                        .onTapGesture {
                                            UIPasteboard.general.string = pairingCode
                                        }
                                    
                                    Text("タップしてコピー")
                                        .font(.system(.caption2))
                                        .foregroundColor(.mioTextSecondary.opacity(0.7))
                                }
                            }
                            
                            Button {
                                showManualPairing = false
                            } label: {
                                Text("QRコードに戻る")
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(.mioAccent)
                            }
                        }
                    } else {
                        // QRコード表示
                        Text("モニターでこのQRコードを読み取ってください")
                            .font(.system(.body))
                            .foregroundColor(.mioTextSecondary)
                            .multilineTextAlignment(.center)
                        
                        if let qrImage = generateQRCode(cameraId: cameraId, pairingCode: pairingCode) {
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
                            Text("QRコード以外でペアリングする")
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
            .navigationTitle("QRコード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        showQRCode = false
                    }
                }
            }
        }
    }
    
    // MARK: - QRコード生成
    
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
        
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func formatPairingCode(_ code: String) -> String {
        return code
    }
}

#Preview {
    CameraSettingsSheet(viewModel: CameraViewModel()) {}
        .environmentObject(AuthenticationService.shared)
}
