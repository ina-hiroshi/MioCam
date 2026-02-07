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
    
    @State private var showSettings = false
    @State private var showOverlay = true
    @State private var hideOverlayTask: Task<Void, Never>?
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    
    @State private var isConnecting = true
    @State private var isReconnecting = false
    @State private var connectionError: String?
    @State private var cameraInfo: CameraModel?
    @State private var videoTrack: RTCVideoTrack?
    @State private var audioTrack: RTCAudioTrack?
    @State private var sessionId: String?
    @State private var answerListener: ListenerRegistration?
    @State private var iceCandidateListener: ListenerRegistration?
    @State private var sessionListener: ListenerRegistration?
    @State private var cameraListener: ListenerRegistration?
    @State private var originalIdleTimerDisabled: Bool = false
    @State private var isMicActive = false
    @State private var showOfflineAlert = false
    @State private var offlineMessage: String?
    
    private let webRTCService = WebRTCService.shared
    private let signalingService = SignalingService.shared
    private let backgroundAudioService = BackgroundAudioService.shared
    
    // WebRTCServiceDelegate用のヘルパー
    private class WebRTCDelegate: NSObject, WebRTCServiceDelegate {
        var onStateChange: ((WebRTCConnectionState, String) -> Void)?
        var onRemoteVideoTrack: ((RTCVideoTrack) -> Void)?
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
                onRemoteVideoTrack?(track)
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
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()
            
            // 映像表示エリア
            if let track = videoTrack {
                VideoView(videoTrack: track, contentMode: .scaleAspectFit)
                    .scaleEffect(zoomScale)
                    .gesture(magnificationGesture)
                    .gesture(doubleTapGesture)
                    .ignoresSafeArea()
            }
            
            // 接続中/再接続中オーバーレイ
            if isConnecting || isReconnecting {
                connectionOverlay
            }
            
            // ステータスオーバーレイ
            if showOverlay && !isConnecting && !isReconnecting {
                statusOverlay
            }
        }
        .navigationBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleOverlay()
        }
        .task {
            // アイドルタイマーを無効化（画面スリープを防止）
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            
            // WebRTCデリゲートを設定
            let delegate = WebRTCDelegate()
            delegate.onStateChange = { [self] state, sessionId in
                handleConnectionStateChange(state, sessionId: sessionId)
            }
            delegate.onRemoteVideoTrack = { [self] track in
                handleRemoteVideoTrack(track)
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
            cleanup()
        }
        .sheet(isPresented: $showSettings) {
            MonitorSettingsSheet(
                viewModel: viewModel,
                cameraLink: cameraLink,
                cameraInfo: cameraInfo
            ) {
                dismiss()
            }
            .environmentObject(authService)
        }
        .alert("接続エラー", isPresented: $showOfflineAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            if let message = offlineMessage {
                Text(message)
            }
        }
    }
    
    // MARK: - 接続中オーバーレイ
    
    private var connectionOverlay: some View {
        VStack(spacing: 16) {
            if isReconnecting {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text(isReconnecting ? "再接続中..." : "接続中...")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            
            if let error = connectionError {
                Text(error)
                    .font(.system(.caption))
                    .foregroundColor(.mioError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
        )
    }
    
    // MARK: - ステータスオーバーレイ
    
    private var statusOverlay: some View {
        VStack {
            // 上部ステータスバー
            HStack {
                // 接続状態バッジ
                HStack(spacing: 6) {
                    Circle()
                        .fill(cameraInfo?.isOnline == true ? Color.mioSuccess : Color.mioError)
                        .frame(width: 8, height: 8)
                    Text(cameraInfo?.isOnline == true ? "接続中" : "オフライン")
                        .font(.system(.caption))
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                
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
                
                // プッシュ・トゥ・トークマイクボタン
                Button {
                    // ボタンは押下中のみ有効（DragGestureで処理）
                } label: {
                    Image(systemName: isMicActive ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isMicActive ? .white : .white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(
                            Group {
                                if isMicActive {
                                    Circle()
                                        .fill(Color.mioAccent)
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                            }
                        )
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
                    dismiss()
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
            connectionError = "認証が必要です"
            isConnecting = false
            return
        }
        
        // 前回のセッションをクリーンアップ（再接続時）
        if let oldSessionId = sessionId {
            answerListener?.remove()
            answerListener = nil
            iceCandidateListener?.remove()
            iceCandidateListener = nil
            sessionListener?.remove()
            sessionListener = nil
            webRTCService.closeSession(sessionId: oldSessionId)
        }
        
        isConnecting = true
        connectionError = nil
        
        do {
            // カメラ情報を取得
            guard let camera = try await CameraFirestoreService.shared.getCamera(cameraId: cameraLink.cameraId) else {
                connectionError = "カメラが見つかりません"
                isConnecting = false
                return
            }
            
            // カメラがオフラインの場合は接続を試みない
            guard camera.isOnline else {
                connectionError = "カメラがオフラインです"
                isConnecting = false
                offlineMessage = "カメラがオフラインです"
                showOfflineAlert = true
                return
            }
            
            cameraInfo = camera
            
            // カメラの状態をリアルタイム監視開始
            cameraListener = CameraFirestoreService.shared.observeCamera(
                cameraId: cameraLink.cameraId
            ) { [self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let updatedCamera):
                        if let updatedCamera = updatedCamera {
                            // 既に接続済みの状態でオフラインになった場合のみアラートを表示
                            if let currentCamera = self.cameraInfo,
                               currentCamera.isOnline && !updatedCamera.isOnline {
                                self.offlineMessage = "カメラがオフラインになりました"
                                self.showOfflineAlert = true
                            }
                            self.cameraInfo = updatedCamera
                        }
                    case .failure(let error):
                        print("カメラ監視エラー: \(error.localizedDescription)")
                    }
                }
            }
            
            // セッションIDを生成（UUID）
            let newSessionId = UUID().uuidString
            sessionId = newSessionId
            
            // 1. WebRTC接続を開始してOfferを生成
            // Offerはdelegate経由で受け取る（handleOfferGenerated）
            try await webRTCService.startConnection(sessionId: newSessionId)
            
        } catch {
            connectionError = error.localizedDescription
            isConnecting = false
        }
    }
    
    // MARK: - WebRTC Delegate Handlers
    
    func handleOfferGenerated(_ offer: RTCSessionDescription, sessionId: String) async {
        guard let monitorUserId = authService.currentUser?.uid else {
            connectionError = "認証が必要です"
            isConnecting = false
            return
        }
        
        // セッションIDが一致しているか確認
        guard sessionId == self.sessionId else {
            return
        }
        
        // cameraInfoが設定されていない場合は再取得
        var camera = cameraInfo
        if camera == nil {
            do {
                camera = try await CameraFirestoreService.shared.getCamera(cameraId: cameraLink.cameraId)
                cameraInfo = camera
            } catch {
                connectionError = "カメラ情報の取得に失敗しました: \(error.localizedDescription)"
                isConnecting = false
                return
            }
        }
        
        guard let camera = camera else {
            connectionError = "カメラ情報が取得できません"
            isConnecting = false
            return
        }
        
        do {
            // デバイス情報を取得
            let monitorDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let monitorDeviceName = UIDevice.current.name
            
            // 2. Firestoreにセッション + Offerを書き込み（UUIDをドキュメントIDとして使用）
            _ = try await signalingService.createSession(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId,
                monitorUserId: monitorUserId,
                monitorDeviceId: monitorDeviceId,
                monitorDeviceName: monitorDeviceName,
                pairingCode: camera.pairingCode,
                offer: offer.toDict()
            )
            
            // 3. Answerを監視（既存のAnswerも即座に確認）
            Task { @MainActor in
                do {
                    // 既存のAnswerを確認（監視開始前に書き込まれたAnswerに対応）
                    if let existingAnswer = try await signalingService.getAnswer(cameraId: cameraLink.cameraId, sessionId: sessionId) {
                        await handleAnswerReceived(.success(existingAnswer), sessionId: sessionId)
                    }
                } catch {
                }
            }
            
            answerListener = signalingService.observeAnswer(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId
            ) { [self] result in
                Task { @MainActor in
                    await self.handleAnswerReceived(result, sessionId: sessionId)
                }
            }
            
            // 4. ICE Candidatesを監視（カメラ側から）
            iceCandidateListener = signalingService.observeICECandidates(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId
            ) { [self] result in
                Task { @MainActor in
                    await self.handleICECandidatesReceived(result, sessionId: sessionId)
                }
            }
            
            // 5. セッションの音声設定を監視
            sessionListener = signalingService.observeSession(
                cameraId: cameraLink.cameraId,
                sessionId: sessionId
            ) { [self] result in
                Task { @MainActor in
                    await self.handleSessionUpdate(result)
                }
            }
            
        } catch {
            connectionError = error.localizedDescription
            isConnecting = false
        }
    }
    
    func handleAnswerReceived(_ result: Result<[String: Any]?, Error>, sessionId: String) async {
        // セッションIDが一致しているか確認
        guard sessionId == self.sessionId else {
            return
        }
        
        switch result {
        case .success(let answerDict):
            guard let answerDict = answerDict,
                  let answer = RTCSessionDescription.from(dict: answerDict) else {
                // Answerがまだない場合は待機
                return
            }
            
            do {
                // 5. Answerを設定
                try await webRTCService.handleAnswer(sessionId: sessionId, answer: answer)
            } catch {
                connectionError = "Answerの設定に失敗しました: \(error.localizedDescription)"
                isConnecting = false
            }
            
        case .failure(let error):
            connectionError = "Answerの受信に失敗しました: \(error.localizedDescription)"
            isConnecting = false
        }
    }
    
    func handleICECandidatesReceived(_ result: Result<[ICECandidateModel], Error>, sessionId: String) async {
        switch result {
        case .success(let candidates):
            // カメラ側からのICE Candidateを処理
            for candidateModel in candidates {
                // カメラ側からのもののみ処理（モニター側は自分で生成したもの）
                guard candidateModel.sender == .camera,
                      let iceCandidate = RTCIceCandidate.from(dict: [
                        "candidate": candidateModel.candidate,
                        "sdpMid": candidateModel.sdpMid as Any,
                        "sdpMLineIndex": candidateModel.sdpMLineIndex ?? 0
                      ]) else {
                    continue
                }
                
                do {
                    try await webRTCService.addICECandidate(sessionId: sessionId, candidate: iceCandidate)
                } catch {
                    // remote descriptionが設定される前のエラーは無視（後で再試行される）
                    if !error.localizedDescription.contains("remote description was null") {
                        print("ICE Candidate追加エラー: \(error.localizedDescription)")
                    }
                }
            }
            
        case .failure(let error):
            print("ICE Candidate監視エラー: \(error.localizedDescription)")
        }
    }
    
    func handleSessionUpdate(_ result: Result<[String: Any]?, Error>) async {
        switch result {
        case .success(let sessionData):
            guard let sessionData = sessionData,
                  let audioTrack = audioTrack else {
                return
            }
            
            // isAudioEnabledがnilの場合はfalseとして扱う（デフォルトOFF）
            let isAudioEnabled = sessionData["isAudioEnabled"] as? Bool ?? false
            
            // カメラ側の音声設定に応じてリモートオーディオトラックのisEnabledを更新
            audioTrack.isEnabled = isAudioEnabled
            
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
    
    func handleRemoteVideoTrack(_ track: RTCVideoTrack) {
        // リモートビデオトラックを受信
        videoTrack = track
        isConnecting = false
        connectionError = nil
    }
    
    func handleRemoteAudioTrack(_ track: RTCAudioTrack) {
        // リモートオーディオトラックを受信（カメラ側からの音声）
        audioTrack = track
        
        // セッションドキュメントから現在のisAudioEnabledを取得して設定
        Task { @MainActor in
            guard let sessionId = sessionId else { return }
            
            do {
                let sessionDoc = try await FirestoreService.shared.db
                    .collection("cameras").document(cameraLink.cameraId)
                    .collection("sessions").document(sessionId)
                    .getDocument()
                
                if let data = sessionDoc.data(),
                   let isAudioEnabled = data["isAudioEnabled"] as? Bool {
                    // FirestoreのisAudioEnabledに基づいて設定
                    track.isEnabled = isAudioEnabled
                } else {
                    // isAudioEnabledがnilの場合はfalseとして扱う（デフォルトOFF）
                    track.isEnabled = false
                }
            } catch {
                // エラーの場合はデフォルトOFF
                track.isEnabled = false
            }
        }
        
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
            connectionError = nil
            // WebRTC接続完了後にスピーカー出力を確実にする
            backgroundAudioService.ensureSpeakerOutput()
        case .disconnected, .failed, .closed:
            isConnecting = false
            if connectionError == nil {
                connectionError = "接続が切断されました"
            }
        case .connecting:
            isConnecting = true
        case .new:
            break
        }
    }
    
    private func cleanup() {
        hideOverlayTask?.cancel()
        
        // マイクを無効化
        if isMicActive {
            disableMic()
        }
        
        // リスナーを削除
        answerListener?.remove()
        answerListener = nil
        iceCandidateListener?.remove()
        iceCandidateListener = nil
        sessionListener?.remove()
        sessionListener = nil
        cameraListener?.remove()
        cameraListener = nil
        
        // WebRTCセッションを終了
        if let sessionId = sessionId {
            webRTCService.closeSession(sessionId: sessionId)
            
            // Firestoreのセッションを削除（カメラ側のデバイス数更新を即座に反映）
            Task {
                do {
                    // まずセッションのステータスをdisconnectedに更新（カメラ側が即座に検知できるように）
                    try await signalingService.updateSessionStatus(
                        cameraId: cameraLink.cameraId,
                        sessionId: sessionId,
                        status: .disconnected
                    )
                    // その後、セッションを削除
                    try await signalingService.deleteSession(cameraId: cameraLink.cameraId, sessionId: sessionId)
                } catch {
                    print("セッション削除エラー: \(error.localizedDescription)")
                }
            }
        }
        
        // モニター側のAVAudioSession設定を解除
        backgroundAudioService.stopForMonitorMode()
        
        // アイドルタイマーを元に戻す
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        
        // デリゲートをクリア
        webRTCService.delegate = nil
        webRTCDelegate = nil
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
