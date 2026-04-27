//
//  AdBannerView.swift
//  MioCam
//
//  アダプティブバナー（Google Mobile Ads）
//

import GoogleMobileAds
import SwiftUI
import UIKit

/// モニター Live 等に配置するバナー行
struct AdBannerView: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var consentService: ConsentService

    var body: some View {
        Group {
            if subscriptionService.shouldShowAds, consentService.canRequestAds, consentService.isMobileAdsReady {
                AdaptiveAdBannerContainer()
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }
}

/// 幅に合わせた高さで GADBannerView を表示（全画面 Live 想定で画面幅を使用）
private struct AdaptiveAdBannerContainer: View {
    var body: some View {
        let width = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        AdaptiveBannerRepresentable(adWidth: width)
            .frame(height: adSize.size.height)
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }
}

private struct AdaptiveBannerRepresentable: UIViewRepresentable {
    let adWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let size = currentOrientationAnchoredAdaptiveBanner(width: adWidth)
        let banner = BannerView(adSize: size)
        banner.adUnitID = AdMobConfig.bannerUnitID
        banner.delegate = context.coordinator
        context.coordinator.banner = banner
        context.coordinator.lastWidth = adWidth
        if let root = UIApplication.topViewControllerForAds() {
            banner.rootViewController = root
        }
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        guard abs(context.coordinator.lastWidth - adWidth) > 0.5 else { return }
        context.coordinator.lastWidth = adWidth
        let newSize = currentOrientationAnchoredAdaptiveBanner(width: adWidth)
        uiView.adSize = newSize
        if let root = UIApplication.topViewControllerForAds() {
            uiView.rootViewController = root
        }
        uiView.load(Request())
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        weak var banner: BannerView?
        var lastWidth: CGFloat = 0
    }
}

// MARK: - Window / VC 解決

private extension UIApplication {
    static func topViewControllerForAds() -> UIViewController? {
        guard let scene = shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .rootViewController
        }
        return topMost(from: root)
    }

    private static func topMost(from vc: UIViewController?) -> UIViewController? {
        if let presented = vc?.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = vc as? UINavigationController {
            return topMost(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return topMost(from: tab.selectedViewController)
        }
        return vc
    }
}
