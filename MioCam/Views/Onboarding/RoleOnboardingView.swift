//
//  RoleOnboardingView.swift
//  MioCam
//

import SwiftUI

/// カメラ／モニター役割ごとの初回オンボーディング（スワイプでページ切り替え）。
struct RoleOnboardingView: View {
    enum Role: Hashable {
        case camera
        case monitor
    }

    let role: Role
    var onComplete: () -> Void

    @State private var pageIndex = 0

    private struct PageItem: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let body: String
    }

    private var pageItems: [PageItem] {
        switch role {
        case .camera:
            return [
                PageItem(
                    id: "camera-0",
                    symbol: "video.fill",
                    title: String(localized: "onboarding_camera_page1_title"),
                    body: String(localized: "onboarding_camera_page1_body")
                ),
                PageItem(
                    id: "camera-1",
                    symbol: "qrcode",
                    title: String(localized: "onboarding_camera_page2_title"),
                    body: String(localized: "onboarding_camera_page2_body")
                ),
                PageItem(
                    id: "camera-2",
                    symbol: "waveform",
                    title: String(localized: "onboarding_camera_page3_title"),
                    body: String(localized: "onboarding_camera_page3_body")
                )
            ]
        case .monitor:
            return [
                PageItem(
                    id: "monitor-0",
                    symbol: "qrcode.viewfinder",
                    title: String(localized: "onboarding_monitor_page1_title"),
                    body: String(localized: "onboarding_monitor_page1_body")
                ),
                PageItem(
                    id: "monitor-1",
                    symbol: "eye.fill",
                    title: String(localized: "onboarding_monitor_page2_title"),
                    body: String(localized: "onboarding_monitor_page2_body")
                ),
                PageItem(
                    id: "monitor-2",
                    symbol: "speaker.wave.2.fill",
                    title: String(localized: "onboarding_monitor_page3_title"),
                    body: String(localized: "onboarding_monitor_page3_body")
                )
            ]
        }
    }

    private var lastPageIndex: Int {
        max(pageItems.count - 1, 0)
    }

    var body: some View {
        ZStack {
            Color.mioPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                        onboardingPage(symbol: item.symbol, title: item.title, body: item.body)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)

                Button {
                    if pageIndex < lastPageIndex {
                        withAnimation {
                            pageIndex += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(
                        pageIndex < lastPageIndex
                            ? String(localized: "onboarding_next")
                            : String(localized: "onboarding_get_started")
                    )
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(role == .camera ? Color.mioAccent : Color.mioAccentSub)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
        }
        .id(role)
        .onAppear {
            pageIndex = 0
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func onboardingPage(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(role == .camera ? Color.mioAccent : Color.mioAccentSub)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.mioTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(body)
                .font(.system(.body))
                .foregroundColor(.mioTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
    }
}

#Preview("Camera") {
    RoleOnboardingView(role: .camera) {}
}

#Preview("Monitor") {
    RoleOnboardingView(role: .monitor) {}
}
