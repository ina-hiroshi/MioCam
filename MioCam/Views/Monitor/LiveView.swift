//
//  LiveView.swift
//  MioCam
//
//  ライブビュー画面（モニター側）
//

import SwiftUI
import WebRTC
import FirebaseFirestore

/// ライブビュー画面
struct LiveView: View {
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject var viewModel: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    
    let cameraLink: MonitorLinkModel
    /// fullScreenCover(item:)ではdismiss()だけでは閉じない場合があるため、親でbindingをnilにするためのコールバック
    var onDismiss: (() -> Void)?
    
    /// MonitorViewModelのcameraStatusesを参照（observeCamera重複を避け、Firestore read削減）
    private var cameraInfo: CameraModel? {
        viewModel.cameraStatuses[cameraLink.cameraId]
    }
    
    @State private var showSettings = false
    @State private var showOverlay = true
    @State private var hideOverlayTask: Task<Void, Never>?
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    @State private var isConnecting = true
    @State private var isReconnecting = false
    @State private var connectionError: String?
    @State private var videoTrack: RTCVideoTrack?
    @State private var audioTrack: RTCAudioTrack?
    @State private var sessionId: String?
    @State private var sessionMonitorListener: ListenerRegistration?  // Answerと音声設定を統合
    @State private var iceCandidateListener: ListenerRegistration?
    @State private var originalIdleTimerDisabled: Bool = false
    @State private var isMicActive = false
    @State private var showOfflineAlert = false
    @State private var offlineMessage: String?
    @State private var isSpeakerMuted = false
    @State private var isAudioPermitted = false  // カメラ側の音声許可状態
    @State private var lastKnownAudioEnabled = false  // セッション更新からのキャッシュ、getDocument回避用
    @State private var connectionTimeoutTask: Task<Void, Never>?
    @State private var connectionTimedOut = false
    @State private var reconnectAttempt = 0
    @State private var reconnectTask: Task<Void, Never>?
    @State private var hasEverConnected = false  // 一度でも接続に成功したか
    @State private var hasReceivedAnswer = false  // Answerを既に受信・設定済みか
    @State private var connectedUsers: [String] = []  // 接続中のユーザー名リスト
    @State private var connectedSessionsListener: ListenerRegistration?
    @State private var userDisplayNameCache: [String: String] = [:]  // ユーザーID -> displayNameのキャッシュ
    @State private var hasCleanedUp = false  // 二重クリーンアップ防止
    
    private let maxReconnectAttempts = 5
    
    private let webRTCService = WebRTCService.shared
    private let signalingService = SignalingService.shared
    private let backgroundAudioService = BackgroundAudioService.shared
    
    // WebRTCServiceDelegate用のヘルパー
    private class WebRTCDelegate: NSObject, WebRTCServiceDelegate {
        var onStateChange: ((WebRTCConnectionState, String) -> Void)?
        var onRemoteVideoTrack: ((RTCVideoTrack, String) -> Void)?
        var onRemoteAudioTrack: ((RTCAudioTrack) -> Void)?
        var onICECandidate: ((RTCIceCandidate, String) async -> Void)?
        var onOfferGenerated: ((RTCSessionDescription, String) async -> Void)?
        
        nonisolated func webRTCService(_ service: WebRTCService, didChangeState state: WebRTCConnectionState, for sessionId: String) {
            Task { @MainActor in
                onStateChange?(state, sessionId)
            }
        }
        
        nonisolated func webRTCService(_ service: WebRTCService, didReceiveRemoteVideoTrack track: RTCVideoTrack, for sessionId: String) {
            Task { @MainActor in
                onRemoteVideoTrack?(track, sessionId)
            }
        }
        
        nonisolated func webRTCService(_ service: WebRTCService, didReceiveRemoteAudioTrack track: RTCAudioTrack, for sessionId: String) {
            Task { @MainActor in
                onRemoteAudioTrack?(track)
            }
        }
        
        nonisolated func webRTCService(_ service: WebRTCService, didGenerateICECandidate candidate: RTCIceCandidate, for sessionId: String) {
            Task { @MainActor in
                await onICECandidate?(candidate, sessionId)
            }
        }
        
        nonisolated func webRTCService(_ service: WebRTCService, didGenerateAnswer sdp: RTCSessionDescription, for sessionId: String) {
            // モニター側では使用しない
        }
        
        nonisolated func webRTCService(_ service: WebRTCService, didGenerateOffer sdp: RTCSessionDescription, for sessionId: String) {
            Task { @MainActor in
                await onOfferGenerated?(sdp, sessionId)
            }
        }
    }
    
    @State private var webRTCDelegate: WebRTCDelegate?
    
    /// ビデオ表示専用ビュー（他の状態変更から分離）
    private struct VideoPlayerView: View, Equatable {
        let videoTrack: RTCVideoTrack?
        let zoomScale: CGFloat
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.videoTrack === rhs.videoTrack && lhs.zoomScale == rhs.zoomScale
        }
        
        var body: some View {
            if let track = videoTrack {
                VideoView(videoTrack: track, contentMode: .scaleAspectFit)
                    .scaleEffect(zoomScale)
                    .ignoresSafeArea()
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 背景 + オーバーレイ切替用タップエリア
            Color.black
                .ignoresSafeArea()
                .onTapGesture { if !isConnecting && !isReconnecting && !connectionTimedOut { toggleOverlay() } }
            
            // 映像表示エリア（EquatableViewで分離）
            EquatableView(content: VideoPlayerView(videoTrack: videoTrack, zoomScale: zoomScale))
                .gesture(magnificationGesture)
                .gesture(doubleTapGesture)
                .onTapGesture { if !isConnecting && !isReconnecting && !connectionTimedOut { toggleOverlay() } }
            
            // 接続中/再接続中オーバーレイ
            if isConnecting || isReconnecting || connectionTimedOut {
                connectionOverlay
            }
            
            // ステータスオーバーレイ
            if showOverlay && !isConnecting && !isReconnecting {
                statusOverlay
            }
        }
        .navigationTitle(cameraInfo?.deviceName ?? String(localized: "live_view_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // アイドルタイマーを無効化（画面スリープを防止）
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            
            // WebRTCデリゲートを設定
            let delegate = WebRTCDelegate()
            delegate.onStateChange = { [self] state, sessionId in
                handleConnectionStateChange(state, sessionId: sessionId)
            }
            delegate.onRemoteVideoTrack = { [self] track, incomingSessionId in
                handleRemoteVideoTrack(track, incomingSessionId: incomingSessionId)
            }
            delegate.onRemoteAudioTrack = { [self] track in
                handleRemoteAudioTrack(track)
            }
            delegate.onICECandidate = { [self] candidate, sessionId in
                await handleICECandidate(candidate, sessionId: sessionId)
            }
            delegate.onOfferGenerated = { [self] offer, sessionId in
                await handleOfferGenerated(offer, sessionId: sessionId)
            }
            webRTCDelegate = delegate
            webRTCService.delegate = delegate
            
            // モニター側のAVAudioSession設定
            backgroundAudioService.startForMonitorMode()
            
            await startConnection()
        }
        .onDisappear {
            Task { await performCleanup() }
        }
        .sheet(isPresented: $showSettings) {
            MonitorSettingsSheet(
                viewModel: viewModel,
                cameraLink: cameraLink,
                cameraInfo: cameraInfo
            ) {
                onDismiss?() ?? dismiss()
            }
            .environmentObject(authService)
        }
        .alert(String(localized: "connection_error"), isPresented: $showOfflineAlert) {
            Button("OK") {
                Task {
                    await performCleanup()
                    await MainActor.run {
                        onDismiss?() ?? dismiss()
                    }
                }
            }
        } message: {
            if let message = offlineMessage {
                Text(message)
            }
        }
        .onChange(of: viewModel.cameraStatuses[cameraLink.cameraId]?.isOnline) { newValue in
            if newValue == false && hasEverConnected {
                offlineMessage = String(localized: "camera_went_offline")
                showOfflineAlert = true
            }
        }
    }
    
    // MARK: - 接続中オーバーレイ
    
    private var connectionOverlay: some View {
        ZStack {
            // 閉じるボタン（左上、最前面で常にタップ可能）
            VStack {
                HStack {
                    Button {
                        Task {
                            await performCleanup()
                            await MainActor.run {
                                onDismiss?() ?? dismiss()
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }
            .zIndex(1)
            
            // 接続状態表示（中央）
            VStack(spacing: 16) {
                if isReconnecting {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.7))
                } else if connectionTimedOut {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.mioError)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                Text(connectionTimedOut ? String(localized: "connection_timeout") : (isReconnecting ? String(localized: "reconnecting") : String(localized: "connecting")))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                if let error = connectionError {
                    Text(error)
                        .font(.system(.caption))
                        .foregroundColor(.mioError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                if connectionTimedOut {
                    Text(String(localized: "connection_please_retry"))
                        .font(.system(.caption))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // リトライボタン（タイムアウト時のみ表示）
                if connectionTimedOut {
                    Button {
                        connectionTimedOut = false
                        connectionError = nil
                        Task {
                            await startConnection()
                        }
                    } label: {
                        Text(String(localized: "retry"))
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.mioAccent)
                            )
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
            )
        }
    }
    
    // MARK: - ステータスオーバーレイ
    
    private var statusOverlay: some View {
        VStack {
            // 上部ステータスバー
            HStack {
                // 接続状態バッジ（オンライン時のみ、1ユーザー1バッジの列）
                if cameraInfo?.isOnline == true {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.mioSuccess)
                                .frame(width: 8, height: 8)
                                .padding(6)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                            ForEach(Array(connectedUsers.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(.caption))
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                    )
                            }
                        }
                    }
                }
                
                Spacer()
                
                // バッテリーバッジ
                if let battery = cameraInfo?.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(level: battery))
                            .font(.system(size: 12))
                        Text("\(battery)%")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundColor(batteryColor(level: battery))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            
            Spacer()
            
            // 下部コントロール
            HStack {
                // 設定ボタン
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
                
                Spacer()
                
                // スピーカーボタン（音声許可時のみ表示）
                if isAudioPermitted {
                    Button {
                        isSpeakerMuted.toggle()
                        audioTrack?.isEnabled = !isSpeakerMuted
                    } label: {
                        Image(systemName: isSpeakerMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    
                    Spacer()
                }
                
                // プッシュ・トゥ・トークマイクボタン
                Button {
                    // ボタンは押下中のみ有効（DragGestureで処理）
                } label: {
                    ZStack {
                        // パルスアニメーション（アクティブ時）
                        if isMicActive {
                            Circle()
                                .stroke(Color.mioAccent.opacity(0.4), lineWidth: 2)
                                .frame(width: 72, height: 72)
                                .scaleEffect(isMicActive ? 1.3 : 1.0)
                                .opacity(isMicActive ? 0 : 1)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isMicActive)
                        }
                        
                        // 破線リング（非アクティブ時）/ 実線リング（アクティブ時）
                        Circle()
                            .stroke(style: isMicActive ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .frame(width: 60, height: 60)
                            .foregroundColor(isMicActive ? .mioAccent : .white.opacity(0.5))
                        
                        // マイクアイコン
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundColor(isMicActive ? .white : .white.opacity(0.7))
                            .frame(width: 60, height: 60)
                            .background(
                                Group {
                                    if isMicActive {
                                        Circle().fill(Color.mioAccent)
                                    } else {
                                        Circle().fill(.ultraThinMaterial)
                                    }
                                }
                            )
                            .scaleEffect(isMicActive ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isMicActive)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isMicActive {
                                enableMic()
                            }
                        }
                        .onEnded { _ in
                            if isMicActive {
                                disableMic()
                            }
                        }
                )
                
                Spacer()
                
                // 閉じるボタン
                Button {
                    Task {
                        await performCleanup()
                        await MainActor.run {
                            onDismiss?() ?? dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
    
    // MARK: - Gestures
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastZoomScale
                lastZoomScale = value
                zoomScale = min(max(zoomScale * delta, 1.0), 3.0)
            }
            .onEnded { _ in
                lastZoomScale = 1.0
            }
    }
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring()) {
                    if zoomScale > 1.0 {
                        zoomScale = 1.0
                    } else {
                        zoomScale = 2.0
                    }
                }
            }
    }
    
    // MARK: - Actions
    
    private func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showOverlay.toggle()
        }
        
        // 3秒後に自動非表示
        hideOverlayTask?.cancel()
        if showOverlay {
            hideOverlayTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showOverlay = false
                    }
                }
            }
        }
    }
    
    private func startConnection() async {
        guard authService.currentUser?.uid != nil else {
            connectionError = String(localized: "auth_required")
            isConnecting = false
            return
        }
        
        // 再接続時にクリーンアップフラグをリセット（fullScreenCoverでViewが再利用される場合に備える）
        hasCleanedUp = false
        
        // 前回のセッションをクリーンアップ（再接続時）
        if let oldSessionId = sessionId {
            sessionMonitorListener?.remove()
            sessionMonitorListener = nil
            iceCandidateListener?.remove()
            iceCandidateListener = nil
            connectedSessionsListener?.remove()
            connectedSessionsListener = nil
            webRTCService.closeSession(sessionId: oldSessionId)
            // Firestoreのゴーストセッション削除
            try? await signalingService.updateSessionStatus(
                cameraId: cameraLink.cameraId, sessionId: oldSessionId, status: .disconnected
            )
            try? await signalingService.deleteSession(
                cameraId: cameraLink.cameraId, sessionId: oldSessionId
            )
        }
        
        isConnecting = true
        connectionError = nil
        connectionTimedOut = false
        hasReceivedAnswer = false
        
        // 既存のタイムアウトタスクをキャンセル
        connectionTimeoutTask?.cancel()
        
        // 30秒のタイムアウトタスクを開始
        connectionTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30秒
            if !Task.isCancelled && isConnecting && videoTrack == nil {
                connectionTimedOut = true
                connectionError = String(localized: "connection_timing_out")
                isConnecting = false
            }
        }
        
        do {
            // カメラ情報を取得（MonitorViewModelのcameraStatusesを優先、未ロード時のみFirestoreから取得）
            var camera = viewModel.cameraStatuses[cameraLink.cameraId]
            if camera == nil {
                camera = try await CameraFirestoreService.shared.getCamera(cameraId: cameraLink.cameraId)
            }
            guard let camera = camera else {
                connectionError = String(localized: "camera_not_found")
                isConnecting = false
                return
            }
            
            // カメラがオフラインの場合は接続を試みない
            guard camera.isOnline else {
                connectionError = String(localized: "camera_offline")
                isConnecting = false
                offlineMessage = String(localized: "camera_offline")
                showOfflineAlert = true
                return
            }
            
            // セッションIDを生成（UUID）
            let newSessionId = UUID().uuidString
            sessionId = newSessionId
            
            // 1. WebRTC接続を開始してOfferを生成
            // Offerはdelegate経由で受け取る（handleOfferGenerated）
            try await webRTCService.startConnection(sessionId: newSessionId)
            
            // 接続済みセッションを監視（接続中のユーザー名を取得）
            // 接続確立後に開始（handleRemoteVideoTrackで開始）
            
        } catch {
            connectionError = error.localizedDescription
            isConnecting = false
        }
    }
    
    // MARK: - Connected Sessions Observation
    
    /// 接続済みセッションを監視して接続中のユーザー名を取得
    private func startObservingConnectedSessions(cameraId: String, currentSessionId: String?) {
        // 既存のリスナーを削除
        connectedSessionsListener?.remove()
        connectedSessionsListener = nil
        
        connectedSessionsListener = signalingService.observeConnectedSessions(cameraId: cameraId) { [self] result in
            Task { @MainActor in
                switch result {
                case .success(let sessions):
                    // 接続中のユーザーのdisplayNameを取得（自分のセッションも含む）
                    // monitorUserIdで重複を排除（同じユーザーは1回だけ表示）
                    var userNames: [String] = []
                    var seenUserIds: Set<String> = []
                    
                    #if DEBUG
                    print("接続済みセッション数: \(sessions.count)")
                    #endif
                    
                    // フィルタリング: 重複ユーザーIDを排除（自分のセッションも含める）
                    var targetSessions: [SessionModel] = []
                    for session in sessions {
                        // 同じユーザーIDのセッションは1回だけ表示（重複排除）
                        if seenUserIds.contains(session.monitorUserId) {
                            #if DEBUG
                            print("重複ユーザーをスキップ: \(session.monitorUserId)")
                            #endif
                            continue
                        }
                        seenUserIds.insert(session.monitorUserId)
                        targetSessions.append(session)
                    }
                    
                    #if DEBUG
                    print("フィルタリング後のセッション数: \(targetSessions.count)")
                    #endif
                    
                    // session.displayName を優先し、キャッシュ、monitorDeviceName の順で使用（users read 削減）
                    for session in targetSessions {
                        let displayName: String
                        if let name = session.displayName, !name.isEmpty {
                            displayName = name
                            userDisplayNameCache[session.monitorUserId] = name
                        } else if let cached = userDisplayNameCache[session.monitorUserId], !cached.isEmpty {
                            displayName = cached
                        } else {
                            displayName = session.monitorDeviceName
                        }
                        if !displayName.isEmpty {
                            userNames.append(displayName)
                        }
                    }
                    
                    #if DEBUG
                    print("表示するユーザー名: \(userNames)")
                    #endif
                    
                    // 実際に変更があった場合のみ更新（不要な再描画を防止）
                    if self.connectedUsers != userNames {
                        self.connectedUsers = userNames
                    }
                    
                case .failure(let error):
                    print("接続済みセッション監視エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - WebRTC Delegate Handlers
    
    func handleOfferGenerated(_ offer: RTCSessionDescription, sessionId: String) async {
        guard let monitorUserId = authService.currentUser?.uid else {
            connectionError = String(localized: "auth_required")
            isConnecting = false
            return
        }
        
        // セッションIDが一致しているか確認
        guard sessionId == self.sessionId else {
            return
        }
        
        // cameraInfoはviewModel.cameraStatusesを参照。nilの場合はgetCameraで取得
        var camera = viewModel.cameraStatuses[cameraLink.cameraId]
        if camera == nil {
            do {
                camera = try await CameraFirestoreService.shared.getCamera(cameraId: cameraLink.cameraId)
            } catch {
                connectionError = String(format: String(localized: "camera_info_fetch_failed"), error.localizedDescription)
                isConnecting = false
                return
            }
        }
        
        guard let camera = camera else {
            connectionError = String(localized: "camera_info_unavailable")
            isConnecting = false
            return
        }
        
        do {
            // デバイス情報を取得
            let monitorDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let monitorDeviceName = UIDevice.current.name
            
            // 2. Firestoreにセッション + Offerを書き込み（UUIDをドキュメントIDとして使用）
            // displayName: Authを優先（DB読み取り削減）、未設定時のみFirestoreから取得
            var displayName = authService.currentUser?.displayName
            if displayName == nil || displayName?.isEmpty == true {
                do {
                    let userDoc = try await FirestoreService.shared.db
                        .collection("users")
                        .document(monitorUserId)
                        .getDocument()
                    if let userData = userDoc.data(),
                       let name = userData["displayName"] as? String,
                       !name.isEmpty {
                        displayName = name
                    }
                } catch {
                    print("ユーザー情報取得エラー: \(error.localizedDescription)")
                }
            }
            
            #if DEBUG
            print("セッション作成時のdisplayName: \(displayName ?? "nil")")
            #endif
            
            // セッションを作成
            _ = try await signalingService.createSession(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId,
                monitorUserId: monitorUserId,
                monitorDeviceId: monitorDeviceId,
                monitorDeviceName: monitorDeviceName,
                pairingCode: camera.pairingCode,
                offer: offer.toDict(),
                displayName: displayName
            )
            
            // 3. セッション監視（Answer・音声設定を1リスナーで取得、DB読み取り削減）
            sessionMonitorListener = signalingService.observeSessionForMonitor(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId,
                onAnswer: { [self] result in
                    Task { @MainActor in
                        await self.handleAnswerReceived(result, sessionId: sessionId)
                    }
                },
                onSessionUpdate: { [self] result in
                    Task { @MainActor in
                        await self.handleSessionUpdate(result)
                    }
                }
            )
            
            // 4. ICE Candidatesを監視（カメラ側から）
            iceCandidateListener = signalingService.observeICECandidates(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId
            ) { [self] result in
                Task { @MainActor in
                    await self.handleICECandidatesReceived(result, sessionId: sessionId)
                }
            }
            
        } catch {
            connectionError = error.localizedDescription
            isConnecting = false
        }
    }
    
    func handleAnswerReceived(_ result: Result<[String: Any]?, Error>, sessionId: String) async {
        guard !hasCleanedUp else { return }
        // セッションIDが一致しているか確認
        guard sessionId == self.sessionId else {
            #if DEBUG
            print("handleAnswerReceived: セッションID不一致 (expected: \(self.sessionId ?? "nil"), received: \(sessionId))")
            #endif
            return
        }
        
        // 既にAnswerを設定済みの場合はスキップ（重複処理防止）
        guard !hasReceivedAnswer else {
            #if DEBUG
            print("handleAnswerReceived: 既にAnswerを設定済みのためスキップ")
            #endif
            return
        }
        
        switch result {
        case .success(let answerDict):
            guard let answerDict = answerDict,
                  let answer = RTCSessionDescription.from(dict: answerDict) else {
                // Answerがまだない場合は待機
                #if DEBUG
                print("handleAnswerReceived: Answerがまだありません")
                #endif
                return
            }
            
            // フラグを先に立てて重複呼び出しを防止
            hasReceivedAnswer = true
            
            #if DEBUG
            print("handleAnswerReceived: Answerを受信しました")
            #endif
            
            do {
                // 5. Answerを設定
                try await webRTCService.handleAnswer(sessionId: sessionId, answer: answer)
                #if DEBUG
                print("handleAnswerReceived: Answerを設定しました")
                #endif
            } catch {
                // エラー時はフラグをリセットして再試行可能にする
                hasReceivedAnswer = false
                connectionError = String(format: String(localized: "answer_set_failed"), error.localizedDescription)
                isConnecting = false
                #if DEBUG
                print("handleAnswerReceived: Answer設定エラー - \(error.localizedDescription)")
                #endif
            }
            
        case .failure(let error):
            connectionError = String(format: String(localized: "answer_receive_failed"), error.localizedDescription)
            isConnecting = false
            #if DEBUG
            print("handleAnswerReceived: Answer受信エラー - \(error.localizedDescription)")
            #endif
        }
    }
    
    func handleICECandidatesReceived(_ result: Result<[ICECandidateModel], Error>, sessionId: String) async {
        guard !hasCleanedUp else { return }
        switch result {
        case .success(let candidates):
            let cameraCandidates = candidates.filter { $0.sender == .camera }
            #if DEBUG
            print("Monitor: カメラICE候補受信 - カメラ側:\(cameraCandidates.count)件")
            for c in cameraCandidates {
                print("Monitor: 候補内容 - \(String(c.candidate.prefix(120)))")
            }
            #endif
            
            for candidateModel in cameraCandidates {
                guard let iceCandidate = RTCIceCandidate.from(dict: [
                    "candidate": candidateModel.candidate,
                    "sdpMid": candidateModel.sdpMid as Any,
                    "sdpMLineIndex": candidateModel.sdpMLineIndex ?? 0
                ]) else {
                    continue
                }
                
                // 同期版addICECandidate（async/awaitデッドロック回避）
                webRTCService.addICECandidate(sessionId: sessionId, candidate: iceCandidate)
            }
            
        case .failure(let error):
            print("ICE Candidate監視エラー: \(error.localizedDescription)")
        }
    }
    
    func handleSessionUpdate(_ result: Result<[String: Any]?, Error>) async {
        guard !hasCleanedUp else { return }
        switch result {
        case .success(let sessionData):
            guard let sessionData = sessionData else { return }
            
            // isAudioEnabledがnilの場合はfalseとして扱う（デフォルトOFF）
            let isAudioEnabled = sessionData["isAudioEnabled"] as? Bool ?? false
            lastKnownAudioEnabled = isAudioEnabled
            
            // カメラ側の音声許可状態を更新
            isAudioPermitted = isAudioEnabled
            
            // オーディオトラックが既にあれば設定を適用（なければhandleRemoteAudioTrackで適用）
            if let track = audioTrack {
                track.isEnabled = isAudioEnabled && !isSpeakerMuted
            }
            
        case .failure(let error):
            print("セッション監視エラー: \(error.localizedDescription)")
        }
    }
    
    func handleICECandidate(_ candidate: RTCIceCandidate, sessionId: String) async {
        // モニター側で生成されたICE CandidateをFirestoreに書き込み
        guard authService.currentUser?.uid != nil else { return }
        
        do {
            try await signalingService.addICECandidate(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId,
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex,
                sender: .monitor
            )
        } catch {
            print("ICE Candidate送信エラー: \(error.localizedDescription)")
        }
    }
    
    func handleRemoteVideoTrack(_ track: RTCVideoTrack, incomingSessionId: String) {
        #if DEBUG
        print("handleRemoteVideoTrack: リモートビデオトラックを受信しました")
        #endif
        
        // リモートビデオトラックを受信
        videoTrack = track
        isConnecting = false
        connectionError = nil
        connectionTimedOut = false
        // タイムアウトタスクをキャンセル
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        
        // 接続確立後に接続済みセッションの監視を開始
        if connectedSessionsListener == nil, let sessionId = sessionId {
            #if DEBUG
            print("handleRemoteVideoTrack: 接続済みセッションの監視を開始します")
            #endif
            startObservingConnectedSessions(cameraId: cameraLink.cameraId, currentSessionId: sessionId)
        }
    }
    
    func handleRemoteAudioTrack(_ track: RTCAudioTrack) {
        // リモートオーディオトラックを受信（カメラ側からの音声）
        audioTrack = track
        
        // セッション監視からのキャッシュ値を使用（getDocumentを回避してDB読み取り削減）
        let isAudioEnabled = lastKnownAudioEnabled
        isAudioPermitted = isAudioEnabled
        track.isEnabled = isAudioEnabled && !isSpeakerMuted
        
        // WebRTCがオーディオルートを変更している可能性があるため、スピーカー出力を強制
        backgroundAudioService.ensureSpeakerOutput()
    }
    
    // MARK: - Push-to-Talk
    
    private func enableMic() {
        guard let sessionId = sessionId else { return }
        isMicActive = true
        webRTCService.setMonitorMicEnabled(sessionId: sessionId, enabled: true)
    }
    
    private func disableMic() {
        guard let sessionId = sessionId else { return }
        isMicActive = false
        webRTCService.setMonitorMicEnabled(sessionId: sessionId, enabled: false)
    }
    
    func handleConnectionStateChange(_ state: WebRTCConnectionState, sessionId: String) {
        // セッションIDが一致しているか確認
        guard sessionId == self.sessionId else {
            return
        }
        
        switch state {
        case .connected:
            isConnecting = false
            isReconnecting = false
            connectionError = nil
            connectionTimedOut = false
            hasEverConnected = true
            reconnectAttempt = 0
            // タイムアウトタスクをキャンセル
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            reconnectTask?.cancel()
            reconnectTask = nil
            
            // WebRTC接続完了後にスピーカー出力を確実にする
            backgroundAudioService.ensureSpeakerOutput()
            // 接続確立後に接続済みセッションの監視を開始（まだ開始されていない場合）
            if connectedSessionsListener == nil, let currentSessionId = self.sessionId {
                startObservingConnectedSessions(cameraId: cameraLink.cameraId, currentSessionId: currentSessionId)
            }
        case .disconnected, .failed:
            // タイムアウトタスクをキャンセル
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            
            // 一度接続に成功していた場合のみ自動再接続を試みる
            if hasEverConnected && reconnectAttempt < maxReconnectAttempts {
                isReconnecting = true
                isConnecting = false
                connectionError = nil
                
                let attempt = reconnectAttempt
                let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s, 8s, 16s
                
                reconnectTask?.cancel()
                reconnectTask = Task { @MainActor in
                    print("WebRTC: 再接続試行 \(attempt + 1)/\(maxReconnectAttempts) (\(Int(delay))秒後)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    guard !Task.isCancelled else { return }
                    
                    // 再接続前に古いセッションIDをクリーンアップ
                    if let oldSessionId = self.sessionId {
                        // 古いセッションをクリーンアップ
                        self.webRTCService.closeSession(sessionId: oldSessionId)
                        // Firestoreのセッションも削除
                        Task {
                            try? await self.signalingService.updateSessionStatus(
                                cameraId: self.cameraLink.cameraId,
                                sessionId: oldSessionId,
                                status: .disconnected
                            )
                            try? await self.signalingService.deleteSession(cameraId: self.cameraLink.cameraId, sessionId: oldSessionId)
                        }
                    }
                    
                    reconnectAttempt += 1
                    // 新しいセッションIDを生成
                    self.sessionId = UUID().uuidString
                    await startConnection()
                }
            } else {
                isConnecting = false
                isReconnecting = false
                if connectionError == nil {
                    connectionError = hasEverConnected ? String(localized: "connection_lost_reconnect_failed") : String(localized: "connection_lost")
                }
            }
        case .closed:
            // 再接続中でない場合のみ状態をリセット
            if reconnectTask == nil {
                isConnecting = false
                isReconnecting = false
            }
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
        case .connecting:
            isConnecting = true
        case .new:
            break
        }
    }
    
    @MainActor
    private func performCleanup() async {
        // 二重実行防止（MainActor上で排他制御して競合を防ぐ）
        guard !hasCleanedUp else { return }
        hasCleanedUp = true
        
        // すべてのタスクをキャンセル
        hideOverlayTask?.cancel()
        hideOverlayTask = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // マイクを無効化
        if isMicActive {
            disableMic()
        }
        
        // リスナーを削除
        sessionMonitorListener?.remove()
        sessionMonitorListener = nil
        iceCandidateListener?.remove()
        iceCandidateListener = nil
        connectedSessionsListener?.remove()
        connectedSessionsListener = nil
        
        // WebRTCセッションを終了
        let sessionIdToCleanup = sessionId
        if let sid = sessionIdToCleanup {
            webRTCService.closeSession(sessionId: sid)
            
            // Firestoreのセッションを確実に更新・削除（個別に try? で実行し、updateStatus 失敗時も deleteSession を確実に実行）
            try? await signalingService.updateSessionStatus(
                cameraId: cameraLink.cameraId,
                sessionId: sid,
                status: .disconnected
            )
            try? await signalingService.deleteSession(cameraId: cameraLink.cameraId, sessionId: sid)
        }
        
        webRTCService.delegate = nil
        webRTCDelegate = nil
        
        // セッションIDをnilに設定して再使用を防止
        sessionId = nil
        
        // 状態をリセット
        isConnecting = false
        isReconnecting = false
        hasEverConnected = false
        hasReceivedAnswer = false
        reconnectAttempt = 0
        connectionError = nil
        connectionTimedOut = false
        videoTrack = nil
        audioTrack = nil
        connectedUsers = []
        userDisplayNameCache.removeAll()  // キャッシュをクリア
        
        // モニター側のAVAudioSession設定を解除
        backgroundAudioService.stopForMonitorMode()
        
        // アイドルタイマーを元に戻す
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
    }
    
    // MARK: - Battery Display
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<10:
            return "battery.0"
        case 10..<25:
            return "battery.25"
        case 25..<50:
            return "battery.50"
        case 50..<75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0..<10:
            return .mioError
        case 10..<20:
            return .mioWarning
        default:
            return .white
        }
    }
}

#Preview {
    let link = MonitorLinkModel(
        id: "test",
        monitorUserId: "user1",
        cameraId: "camera1",
        cameraDeviceName: "リビングのカメラ",
        pairedAt: Timestamp(date: Date()),
        isActive: true
    )
    
    LiveView(viewModel: MonitorViewModel(), cameraLink: link)
        .environmentObject(AuthenticationService.shared)
}
