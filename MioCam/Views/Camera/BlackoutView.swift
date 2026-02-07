//
//  BlackoutView.swift
//  MioCam
//
//  ブラックアウトモード画面（カメラ側）
//

import SwiftUI
import UIKit

/// ブラックアウトモード画面
struct BlackoutView: View {
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    
    /// カメラ停止時のコールバック（CameraModeViewで処理）
    var onStopCamera: (() -> Void)?
    
    @State private var showSettings = false
    @State private var originalBrightness: CGFloat = 0.5
    
    var body: some View {
        NavigationStack {
            ZStack {
            // 純黒背景
            Color.black
                .ignoresSafeArea()
            
            // ステータス表示
            VStack(spacing: 20) {
                Spacer()
                
                // 配信中ステータス
                VStack(spacing: 12) {
                    Text("配信中")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.5))
                    
                    // 接続数
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.mioSuccess)
                            .frame(width: 8, height: 8)
                        
                        Text("\(viewModel.connectedMonitorCount)台接続")
                            .font(.system(.subheadline))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    // 音声配信状態
                    let audioEnabledCount = viewModel.connectedMonitors.filter { $0.isAudioEnabled }.count
                    if audioEnabledCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14))
                            Text("\(audioEnabledCount)台に音声配信中")
                                .font(.system(.subheadline))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    
                    // バッテリー残量
                    if let batteryLevel = viewModel.batteryLevel {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon(level: batteryLevel))
                                .font(.system(size: 14))
                            Text("\(batteryLevel)%")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .foregroundColor(batteryColor(level: batteryLevel).opacity(0.5))
                    }
                }
                
                Spacer()
                
                // タップで設定を開くヒント
                Text("タップで設定を開く")
                    .font(.system(.caption))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 48)
            }
        }
        .navigationTitle(viewModel.deviceName.isEmpty ? "カメラ" : viewModel.deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .contentShape(Rectangle())
        .onTapGesture {
            showSettings = true
        }
        .onAppear {
            enterBlackoutMode()
        }
        .onDisappear {
            exitBlackoutMode()
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(viewModel: viewModel) {
                // カメラ停止時の処理
                // CameraModeViewのコールバックを呼ぶ（shouldDismissToRoleSelection等を設定）
                onStopCamera?()
            }
            .environmentObject(authService)
        }
        }
    }
    
    // MARK: - ブラックアウトモード制御
    
    private func enterBlackoutMode() {
        // 現在の輝度を保存
        originalBrightness = UIScreen.main.brightness
        
        // 画面輝度を最小化
        UIScreen.main.brightness = 0.0
        
        // アイドルタイマーを無効化（画面が自動でオフにならないようにする）
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    private func exitBlackoutMode() {
        // 画面輝度を元に戻す
        UIScreen.main.brightness = originalBrightness
        
        // アイドルタイマーを有効化
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    // MARK: - バッテリー表示
    
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
            return .white
        }
    }
}

#Preview {
    BlackoutView(viewModel: CameraViewModel(), onStopCamera: nil)
        .environmentObject(AuthenticationService.shared)
}
