//
//  UserEngagementStore.swift
//  MioCam
//

import Foundation
import StoreKit
import UIKit

/// オンボーディング完了状態・接続ベースのレビュー依頼を UserDefaults で保持する。
final class UserEngagementStore {
    static let shared = UserEngagementStore()

    private let defaults: UserDefaults

    /// この回数以上「接続成功」とみなしたあと、レビュー依頼を試みる（変更はこの定数のみ）。
    let reviewPromptMinSuccessfulConnections = 3

    private enum Keys {
        static let cameraOnboarding = "mio.userEngagement.cameraOnboardingComplete"
        static let monitorOnboarding = "mio.userEngagement.monitorOnboardingComplete"
        static let lifetimeConnections = "mio.userEngagement.lifetimeSuccessfulConnections"
        static let lastReviewPromptConnectionCount = "mio.userEngagement.lastReviewPromptConnectionCount"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedCameraRoleOnboarding: Bool {
        defaults.bool(forKey: Keys.cameraOnboarding)
    }

    var hasCompletedMonitorRoleOnboarding: Bool {
        defaults.bool(forKey: Keys.monitorOnboarding)
    }

    func markCameraOnboardingComplete() {
        defaults.set(true, forKey: Keys.cameraOnboarding)
    }

    func markMonitorOnboardingComplete() {
        defaults.set(true, forKey: Keys.monitorOnboarding)
    }

    func resetCameraOnboardingForHelpReplay() {
        defaults.set(false, forKey: Keys.cameraOnboarding)
    }

    func resetMonitorOnboardingForHelpReplay() {
        defaults.set(false, forKey: Keys.monitorOnboarding)
    }

    func resetAllOnboardingForHelpReplay() {
        resetCameraOnboardingForHelpReplay()
        resetMonitorOnboardingForHelpReplay()
    }

    /// 接続が成立したときに 1 セッションにつき 1 回呼ぶ（呼び出し側で sessionId 単位の重複排除を行う）。
    func registerSuccessfulConnectionEvent() {
        let newCount = defaults.integer(forKey: Keys.lifetimeConnections) + 1
        defaults.set(newCount, forKey: Keys.lifetimeConnections)

        let threshold = reviewPromptMinSuccessfulConnections
        let lastPromptAt = defaults.integer(forKey: Keys.lastReviewPromptConnectionCount)

        guard newCount >= threshold, lastPromptAt < threshold else { return }

        defaults.set(newCount, forKey: Keys.lastReviewPromptConnectionCount)
        scheduleReviewRequest()
    }

    private func scheduleReviewRequest() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else { return }
            SKStoreReviewController.requestReview(in: scene)
            #if DEBUG
            print("UserEngagementStore: requested review (StoreKit)")
            #endif
        }
    }
}
