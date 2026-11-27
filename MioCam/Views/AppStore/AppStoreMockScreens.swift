//
//  AppStoreMockScreens.swift
//  MioCam
//
//  App Store 掲載用モック画面（ライブ映像はイメージ画像を使用）
//

import SwiftUI

// MARK: - 共通

enum AppStoreMockData {
    static var nurseryCameraName: String { String(localized: "mock_nursery_camera_name") }
    static var livingRoomCameraName: String { String(localized: "mock_livingroom_camera_name") }
    static var testCameraName: String { String(localized: "mock_test_camera_name") }
    static let cameraId = "cam-living-01"
    static let pairingCode = "ABC123"
    static var connectedUser: String { String(localized: "mock_connected_user") }
    static let batteryLevel = 100

    static var cameras: [(name: String, status: String)] {
        [
            (nurseryCameraName, String(localized: "mock_online_updated_recently")),
            (livingRoomCameraName, String(localized: "mock_online_only")),
        ]
    }
}

// MARK: - ライブビュー（モック映像）

struct AppStoreMockLiveView: View {
    var feedImageName: String = "AppStoreMockFeedNursery"
    var cameraName: String = AppStoreMockData.nurseryCameraName
    var connectedUser: String = AppStoreMockData.connectedUser
    var batteryLevel: Int = AppStoreMockData.batteryLevel
    var showAudioControls: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                Image(feedImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.mioSuccess)
                            .frame(width: 8, height: 8)
                            .padding(6)
                            .background(Capsule().fill(.ultraThinMaterial))

                        Text(connectedUser)
                            .font(.system(.caption))
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "battery.100")
                            .font(.system(size: 12))
                        Text("\(batteryLevel)%")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                Spacer()

                HStack {
                    mockControlCircle(systemName: "gearshape.fill")

                    Spacer()

                    if showAudioControls {
                        mockControlCircle(systemName: "speaker.wave.2.fill")
                        Spacer()
                    }

                    ZStack {
                        Circle()
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .frame(width: 60, height: 60)
                            .foregroundColor(.white.opacity(0.5))

                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Spacer()

                    mockControlCircle(systemName: "xmark", weight: .bold)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle(cameraName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func mockControlCircle(systemName: String, weight: Font.Weight = .regular) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: weight))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.ultraThinMaterial))
    }
}

// MARK: - カメラ一覧

struct AppStoreMockMonitorListView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(AppStoreMockData.cameras.enumerated()), id: \.offset) { _, camera in
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.mioAccent.opacity(0.15))
                                .frame(width: 48, height: 48)

                            Image(systemName: "video.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.mioAccent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.name)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.mioTextPrimary)

                            HStack(spacing: 6) {
                                Text(camera.status)
                                    .font(.system(.caption))
                                    .foregroundColor(.mioSuccess)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.mioTextSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.mioSecondaryBg)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mioPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "monitor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "qrcode.viewfinder")
                    .foregroundColor(.mioAccent)
            }
        }
    }
}

// MARK: - QR コード（シート）

struct AppStoreMockQRSheetView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(String(localized: "qr_instruction"))
                    .font(.system(.body))
                    .foregroundColor(.mioTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let qrImage = QRCodeGenerator.generateQRCode(
                    cameraId: AppStoreMockData.cameraId,
                    pairingCode: AppStoreMockData.pairingCode
                ) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                }

                Button {} label: {
                    Text(String(localized: "pairing_alternative"))
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.mioAccent)
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .background(Color.mioPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "qr_code_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "close")) {}
                }
            }
        }
    }
}

// MARK: - カメラ設定

struct AppStoreMockCameraSettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    mockSettingsRow(icon: "qrcode", title: String(localized: "show_qr_code"))
                    mockSettingsRow(icon: "arrow.triangle.2.circlepath", title: String(localized: "regenerate_pairing_code"))
                }

                Section(header: Text(String(localized: "connected_monitors"))) {
                    HStack {
                        Image(systemName: "eye.slash")
                            .foregroundColor(.mioTextSecondary)
                            .frame(width: 24)
                        Text(String(localized: "no_connected_monitors"))
                            .foregroundColor(.mioTextSecondary)
                    }
                }

                Section(header: Text(String(localized: "camera_name"))) {
                    Text(AppStoreMockData.testCameraName)
                        .foregroundColor(.mioTextPrimary)
                }

                Section {
                    Button(role: .destructive) {} label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "stop_camera"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }

                Section {
                    HStack {
                        Text(String(localized: "account"))
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(String(localized: "anonymous_user"))
                            .foregroundColor(.mioTextSecondary)
                    }

                    HStack {
                        Text(String(localized: "version"))
                            .foregroundColor(.mioTextSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.2")
                            .foregroundColor(.mioTextSecondary)
                    }
                }
            }
            .navigationTitle(String(localized: "camera_settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) {}
                }
            }
        }
    }

    private func mockSettingsRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.mioAccent)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.mioTextPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mioTextSecondary)
        }
    }
}

// MARK: - カメラ QR 表示（ライブ映像オーバーレイ）

struct AppStoreMockCameraView: View {
    var feedImageName: String = "AppStoreMockFeedLivingRoom"

    var body: some View {
        ZStack {
            Image(feedImageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                Spacer()

                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.mioSuccess)
                            .frame(width: 10, height: 10)
                        Text(String(localized: "online"))
                            .font(.system(.subheadline))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.5)))

                    VStack(spacing: 12) {
                        Text(String(localized: "qr_instruction"))
                            .font(.system(.subheadline))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)

                        if let qrImage = QRCodeGenerator.generateQRCode(
                            cameraId: AppStoreMockData.cameraId,
                            pairingCode: AppStoreMockData.pairingCode
                        ) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        }

                        Text(String(localized: "pairing_alternative"))
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.mioAccent)
                            .frame(width: 8, height: 8)
                            .opacity(0.7)
                        Text(String(localized: "waiting_for_monitors"))
                            .font(.system(.caption))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 48)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .navigationTitle(AppStoreMockData.livingRoomCameraName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - 役割選択

struct AppStoreMockRoleSelectionView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

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

            VStack(spacing: 16) {
                roleButton(
                    icon: "video.fill",
                    title: String(localized: "camera_role"),
                    subtitle: String(localized: "camera_role_desc"),
                    color: .mioAccent
                )

                roleButton(
                    icon: "eye.fill",
                    title: String(localized: "monitor_role"),
                    subtitle: String(localized: "monitor_role_desc"),
                    color: .mioAccentSub
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Text(String(localized: "sign_out"))
                .font(.system(.footnote))
                .foregroundColor(.mioTextSecondary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mioPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Image(systemName: "questionmark.circle")
                Image(systemName: "gearshape")
            }
        }
    }

    private func roleButton(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)

                Text(subtitle)
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
                .fill(color)
        )
    }
}

// MARK: - ギャラリー（Xcode Preview 用）

struct AppStoreMockGalleryView: View {
    var body: some View {
        TabView {
            NavigationStack {
                AppStoreMockLiveView()
            }
            .tabItem { Label("ライブ", systemImage: "video.fill") }

            NavigationStack {
                AppStoreMockCameraView()
            }
            .tabItem { Label("カメラ", systemImage: "qrcode") }

            NavigationStack {
                AppStoreMockMonitorListView()
            }
            .tabItem { Label("一覧", systemImage: "list.bullet") }
        }
    }
}

#Preview("ライブビュー（寝室）") {
    NavigationStack {
        AppStoreMockLiveView()
    }
    .preferredColorScheme(.light)
}

#Preview("ライブビュー（リビング）") {
    NavigationStack {
        AppStoreMockLiveView(
            feedImageName: "AppStoreMockFeedLivingRoom",
            cameraName: AppStoreMockData.livingRoomCameraName
        )
    }
    .preferredColorScheme(.light)
}

#Preview("カメラ QR") {
    NavigationStack {
        AppStoreMockCameraView()
    }
    .preferredColorScheme(.light)
}

#Preview("カメラ一覧") {
    NavigationStack {
        AppStoreMockMonitorListView()
    }
    .preferredColorScheme(.light)
}

#Preview("ギャラリー") {
    AppStoreMockGalleryView()
        .preferredColorScheme(.light)
}
