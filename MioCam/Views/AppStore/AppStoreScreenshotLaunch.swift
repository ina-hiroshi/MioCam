//
//  AppStoreScreenshotLaunch.swift
//  MioCam
//
//  App Store スクリーンショット撮影用（シミュレータ起動引数）
//

import SwiftUI

/// 起動引数 `-AppStoreScreenshot <id>` で表示する画面（App Store モックアップ順）
enum AppStoreScreenshot: String, CaseIterable {
    case qrCode = "qr_code"
    case cameraSettings = "camera_settings"
    case roleSelection = "role_selection"
    case monitorList = "monitor_list"
    case liveNursery = "live_nursery"
    case liveLivingroom = "live_livingroom"

    var outputFilename: String {
        switch self {
        case .qrCode: return "01_qr_code.png"
        case .cameraSettings: return "02_camera_settings.png"
        case .roleSelection: return "03_role_selection.png"
        case .monitorList: return "04_monitor_list.png"
        case .liveNursery: return "05_live_nursery.png"
        case .liveLivingroom: return "06_live_livingroom.png"
        }
    }
}

enum AppStoreScreenshotLaunch {
    static var current: AppStoreScreenshot? {
        if let stored = UserDefaults.standard.string(forKey: "APPSTORE_SCREENSHOT"),
           let screen = AppStoreScreenshot(rawValue: stored) {
            return screen
        }

        if let env = ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT"],
           let screen = AppStoreScreenshot(rawValue: env) {
            return screen
        }

        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-AppStoreScreenshot"),
              index + 1 < args.count else { return nil }
        return AppStoreScreenshot(rawValue: args[index + 1])
    }
}

/// スクリーンショット撮影時のルートビュー
struct AppStoreScreenshotHostView: View {
    let screen: AppStoreScreenshot

    var body: some View {
        Group {
            switch screen {
            case .qrCode:
                AppStoreMockQRSheetView()
            case .cameraSettings:
                AppStoreMockCameraSettingsView()
            case .roleSelection:
                NavigationStack {
                    AppStoreMockRoleSelectionView()
                }
            case .monitorList:
                NavigationStack {
                    AppStoreMockMonitorListView()
                }
            case .liveNursery:
                AppStoreMockLiveView()
            case .liveLivingroom:
                AppStoreMockLiveView(
                    feedImageName: "AppStoreMockFeedLivingRoom",
                    cameraName: AppStoreMockData.livingRoomCameraName
                )
            }
        }
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SubscriptionService.shared)
        .environmentObject(ConsentService.shared)
        .preferredColorScheme(.light)
    }
}
