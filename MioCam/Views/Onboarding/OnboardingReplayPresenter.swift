//
//  OnboardingReplayPresenter.swift
//  MioCam
//

import SwiftUI
import Combine

/// カメラ→モニターのオンボーディング再表示をまとめる（設定の「使い方」やツールバーの ? から共有）。
@MainActor
final class OnboardingReplayPresenter: ObservableObject {
    @Published var showCamera = false
    @Published var showMonitor = false

    func startReplay() {
        UserEngagementStore.shared.resetAllOnboardingForHelpReplay()
        showMonitor = false
        showCamera = true
    }
}

private struct OnboardingReplaySheetsModifier: ViewModifier {
    @ObservedObject var presenter: OnboardingReplayPresenter

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $presenter.showCamera) {
                RoleOnboardingView(role: .camera) {
                    UserEngagementStore.shared.markCameraOnboardingComplete()
                    presenter.showCamera = false
                    Task { @MainActor in
                        // カメラカバーが閉じきってからモニター用を出す（連続表示の取りこぼし防止）
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        presenter.showMonitor = true
                    }
                }
            }
            .fullScreenCover(isPresented: $presenter.showMonitor) {
                RoleOnboardingView(role: .monitor) {
                    UserEngagementStore.shared.markMonitorOnboardingComplete()
                    presenter.showMonitor = false
                }
            }
    }
}

extension View {
    func onboardingReplaySheets(presenter: OnboardingReplayPresenter) -> some View {
        modifier(OnboardingReplaySheetsModifier(presenter: presenter))
    }
}
