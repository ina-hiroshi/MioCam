//
//  MioCamApp.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth

@main
struct MioCamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthenticationService.shared
    
    init() {
        // Firebase初期化はAppDelegate.didFinishLaunchingWithOptionsで実施
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(SubscriptionService.shared)
                .preferredColorScheme(.light)
        }
    }
}

/// メインコンテンツビュー（認証状態に応じて画面を切り替え）
struct ContentView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var subscriptionService: SubscriptionService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                RoleSelectionView()
            } else {
                SignInWithAppleView()
            }
        }
        .onChange(of: authService.currentUser?.uid) { newUserId in
            subscriptionService.startObserving(userId: newUserId)
        }
        .task {
            subscriptionService.startObserving(userId: authService.currentUser?.uid)
        }
    }
}

/// 役割選択画面
struct RoleSelectionView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var subscriptionService: SubscriptionService
    @State private var showAppSettings = false

    enum AppRole {
        case camera
        case monitor
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // タイトルエリア
                VStack(spacing: 12) {
                    Image("AppIconImage")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                    
                    Text(String(localized: "app_name"))
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.mioTextPrimary)
                    
                    Text(String(localized: "select_role_prompt"))
                        .font(.system(.body))
                        .foregroundColor(.mioTextSecondary)
                }
                
                Spacer()
                
                // 役割選択ボタン
                VStack(spacing: 16) {
                    // カメラボタン
                    NavigationLink(value: AppRole.camera) {
                        HStack(spacing: 16) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 28))
                                .frame(width: 44)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "camera_role"))
                                    .font(.system(.title3, design: .rounded))
                                    .fontWeight(.semibold)
                                
                                Text(String(localized: "camera_role_desc"))
                                    .font(.system(.caption))
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.mioAccent)
                        )
                    }
                    
                    // モニターボタン
                    NavigationLink(value: AppRole.monitor) {
                        HStack(spacing: 16) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 28))
                                .frame(width: 44)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "monitor_role"))
                                    .font(.system(.title3, design: .rounded))
                                    .fontWeight(.semibold)
                                
                                Text(String(localized: "monitor_role_desc"))
                                    .font(.system(.caption))
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.mioAccentSub)
                        )
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // サインアウトボタン
                Button {
                    try? authService.signOut()
                } label: {
                    Text(String(localized: "sign_out"))
                        .font(.system(.footnote))
                        .foregroundColor(.mioTextSecondary)
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mioPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAppSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showAppSettings) {
                AppSettingsSheet()
                    .environmentObject(authService)
                    .environmentObject(subscriptionService)
            }
            .navigationDestination(for: AppRole.self) { role in
                switch role {
                case .camera:
                    CameraModeView()
                        .environmentObject(authService)
                case .monitor:
                    MonitorModeView()
                        .environmentObject(authService)
                }
            }
        }
    }
}

// Hashableに準拠させてnavigationDestinationで使えるようにする
extension RoleSelectionView.AppRole: Hashable {}
