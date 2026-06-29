//
//  AppStoreScreenshotLaunch.swift
//  MioCam
//
//  App Store スクリーンショット撮影用（シミュレータ起動引数）
//

import SwiftUI

/// 起動引数 `-AppStoreScreenshot <id>` で表示する画面
enum AppStoreScreenshot: String, CaseIterable {
    case liveNursery = "live_nursery"
    case liveLivingroom = "live_livingroom"
    case cameraQR = "camera_qr"
    case monitorList = "monitor_list"
    case roleSelection = "role_selection"

    var outputFilename: String {
        switch self {
        case .liveNursery: return "01_live_view_nursery.png"
        case .liveLivingroom: return "02_live_view_livingroom.png"
        case .cameraQR: return "03_camera_qr.png"
        case .monitorList: return "04_monitor_list.png"
        case .roleSelection: return "05_role_selection.png"
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
            case .liveNursery:
                AppStoreMockLiveView()
            case .liveLivingroom:
                AppStoreMockLiveView(
                    feedImageName: "AppStoreMockFeedLivingRoom",
                    cameraName: AppStoreMockData.livingRoomCameraName
                )
            case .cameraQR:
                NavigationStack {
                    AppStoreMockCameraView()
                }
            case .monitorList:
                NavigationStack {
                    AppStoreMockMonitorListView()
                }
            case .roleSelection:
                NavigationStack {
                    AppStoreMockRoleSelectionView()
                }
            }
        }
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SubscriptionService.shared)
        .environmentObject(ConsentService.shared)
        .preferredColorScheme(.light)
    }
}
