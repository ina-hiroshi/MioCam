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
    @State private var showSettingsIcon = false
    @State private var originalBrightness: CGFloat = 0.5
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 純黒背景
                Color.black
                    .ignoresSafeArea()
                
                if showSettingsIcon {
                    // アイコン以外をタップでアイコンを非表示
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showSettingsIcon = false
                        }
                    
                    // 設定アイコン（タップで設定を開く）
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(viewModel.deviceName.isEmpty ? "カメラ" : viewModel.deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .contentShape(Rectangle())
            .onTapGesture {
                if !showSettingsIcon {
                    showSettingsIcon = true
                }
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
}

#Preview {
    BlackoutView(viewModel: CameraViewModel(), onStopCamera: nil)
        .environmentObject(AuthenticationService.shared)
}
