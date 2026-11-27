//
//  InterstitialAdService.swift
//  MioCam
//
//  モニター切り替え（ライブ視聴終了）時などの節目でインタースティシャル広告を表示する。
//  UX を損なわないよう、表示頻度に下限インターバルを設ける。
//

import Foundation
import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdService: NSObject, ObservableObject {
    static let shared = InterstitialAdService()

    /// 前回表示からこの秒数が経過するまでは再表示しない
    private let minimumInterval: TimeInterval = 180

    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var lastShownAt: Date?

    private override init() {
        super.init()
    }

    /// UMP同意 + Mobile Ads 初期化完了後に呼ぶ（先読みロード）
    func preloadIfNeeded() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        InterstitialAd.load(with: AdMobConfig.interstitialUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    print("InterstitialAdService: load failed - \(error.localizedDescription)")
                    return
                }
                self.interstitial = ad
                self.interstitial?.fullScreenContentDelegate = self
            }
        }
    }

    /// 条件を満たす場合のみ表示する（呼び出し側は広告非表示の判定を意識しなくてよい）
    /// - Parameters:
    ///   - shouldShowAds: プレミアム等で広告非表示対象なら false
    ///   - canRequestAds: UMP同意状況
    ///   - isMobileAdsReady: Mobile Ads SDK 初期化完了フラグ
    ///   - rootViewController: 表示元 VC
    func presentIfEligible(
        shouldShowAds: Bool,
        canRequestAds: Bool,
        isMobileAdsReady: Bool,
        from rootViewController: UIViewController?
    ) {
        guard shouldShowAds, canRequestAds, isMobileAdsReady else { return }
        guard let rootViewController else { return }

        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < minimumInterval {
            return
        }

        guard let interstitial else {
            preloadIfNeeded()
            return
        }

        lastShownAt = Date()
        interstitial.present(from: rootViewController)
    }
}

extension InterstitialAdService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        preloadIfNeeded()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("InterstitialAdService: present failed - \(error.localizedDescription)")
        interstitial = nil
        preloadIfNeeded()
    }
}
