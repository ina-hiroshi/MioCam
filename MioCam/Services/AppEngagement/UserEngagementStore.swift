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

    /// この接続回数に達するたびにレビュー依頼を試みる。
    /// Apple は 365 日あたり最大 3 回まで表示を許容するため、複数のマイルストーンを置く。
    let reviewPromptConnectionMilestones = [3, 10, 25]

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
    ///
    /// - Parameter allowReviewPrompt: レビュー依頼を出してよい端末なら `true`。
    ///   カメラ役の端末は別室に置かれ画面も消灯しているため、依頼を出しても誰も見られない。
    ///   その場合は `false` を渡し、接続回数の記録だけを行う。
    func registerSuccessfulConnectionEvent(allowReviewPrompt: Bool = true) {
        let newCount = defaults.integer(forKey: Keys.lifetimeConnections) + 1
        defaults.set(newCount, forKey: Keys.lifetimeConnections)

        guard allowReviewPrompt else { return }

        let lastPromptAt = defaults.integer(forKey: Keys.lastReviewPromptConnectionCount)
        guard let milestone = reviewPromptConnectionMilestones.last(where: { newCount >= $0 }),
              lastPromptAt < milestone else { return }

        scheduleReviewRequest(markingMilestone: milestone)
    }

    private func scheduleReviewRequest(markingMilestone milestone: Int) {
        let defaults = self.defaults
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            // 表示できなかった場合はマイルストーンを消費せず、次の接続で再試行する。
            guard let scene else { return }
            SKStoreReviewController.requestReview(in: scene)
            defaults.set(milestone, forKey: Keys.lastReviewPromptConnectionCount)
            #if DEBUG
            print("UserEngagementStore: requested review (StoreKit) at milestone \(milestone)")
            #endif
        }
    }
}
