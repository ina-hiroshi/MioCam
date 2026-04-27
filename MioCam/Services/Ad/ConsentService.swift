//
//  ConsentService.swift
//  MioCam
//
//  UMP 同意 → ATT → Mobile Ads 初期化
//

import AppTrackingTransparency
import Combine
import Foundation
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class ConsentService: ObservableObject {
    static let shared = ConsentService()

    /// 広告をリクエスト可能か（UMP + canRequestAds）
    @Published private(set) var canRequestAds: Bool = false
    /// 設定に「プライバシーオプション」入口を出すか
    @Published private(set) var isPrivacyOptionsRequired: Bool = false
    /// `MobileAds.shared.start` 完了後、または初期化不要と判断した直後
    @Published private(set) var isMobileAdsReady: Bool = false

    private var isMobileAdsStartCalled = false
    private var consentFlowStarted = false

    private init() {}

    /// 起動時に1回: UMP 同意取得 → 必要に応じフォーム表示 → ATT → GMA 初期化
    func startConsentAndAdsFlowIfNeeded() {
        guard !consentFlowStarted else { return }
        consentFlowStarted = true

        gatherConsent { [weak self] _ in
            Task { @MainActor in
                self?.syncConsentState()
                self?.requestTrackingAuthorizationIfNeeded()
            }
        }
    }

    /// 設定画面から: UMP プライバシーオプション
    func presentPrivacyOptionsForm() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UMPConsentForm.presentPrivacyOptionsForm(from: nil) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        syncConsentState()
    }

    // MARK: - UMP

    private func gatherConsent(consentGatheringComplete: @escaping (Error?) -> Void) {
        let parameters = UMPRequestParameters()
        #if DEBUG
        let debug = UMPDebugSettings()
        parameters.debugSettings = debug
        #endif

        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] requestConsentError in
            DispatchQueue.main.async {
                if let requestConsentError {
                    self?.syncConsentState()
                    consentGatheringComplete(requestConsentError)
                    return
                }
                UMPConsentForm.loadAndPresentIfRequired(from: nil) { formError in
                    self?.syncConsentState()
                    consentGatheringComplete(formError)
                }
            }
        }
    }

    private func requestTrackingAuthorizationIfNeeded() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
                Task { @MainActor in
                    self?.startMobileAdsSDKIfAllowed()
                }
            }
        } else {
            startMobileAdsSDKIfAllowed()
        }
    }

    /// Google Mobile Ads SDK は同意後、かつ canRequestAds のときのみ初期化
    private func startMobileAdsSDKIfAllowed() {
        syncConsentState()
        guard UMPConsentInformation.sharedInstance.canRequestAds, !isMobileAdsStartCalled else {
            isMobileAdsReady = true
            return
        }
        isMobileAdsStartCalled = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.syncConsentState()
                self?.isMobileAdsReady = true
            }
        }
    }

    private func syncConsentState() {
        canRequestAds = UMPConsentInformation.sharedInstance.canRequestAds
        isPrivacyOptionsRequired =
            UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }
}
