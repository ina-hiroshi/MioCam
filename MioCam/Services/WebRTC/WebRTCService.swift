//
//  WebRTCService.swift
//  MioCam
//
//  WebRTC接続を管理するサービス
//

import Foundation
@preconcurrency import WebRTC
import Combine

/// WebRTC接続状態
enum WebRTCConnectionState {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

/// WebRTCサービスのデリゲートプロトコル
protocol WebRTCServiceDelegate: AnyObject {
    /// 接続状態が変化した時
    func webRTCService(_ service: WebRTCService, didChangeState state: WebRTCConnectionState, for sessionId: String)
    /// リモート映像トラックを受信した時（モニター側）
    func webRTCService(_ service: WebRTCService, didReceiveRemoteVideoTrack track: RTCVideoTrack, for sessionId: String)
    /// リモートオーディオトラックを受信した時（モニター側）
    func webRTCService(_ service: WebRTCService, didReceiveRemoteAudioTrack track: RTCAudioTrack, for sessionId: String)
    /// ICE Candidateが生成された時
    func webRTCService(_ service: WebRTCService, didGenerateICECandidate candidate: RTCIceCandidate, for sessionId: String)
    /// SDP Answerが生成された時（カメラ側）
    func webRTCService(_ service: WebRTCService, didGenerateAnswer sdp: RTCSessionDescription, for sessionId: String)
    /// SDP Offerが生成された時（モニター側）
    func webRTCService(_ service: WebRTCService, didGenerateOffer sdp: RTCSessionDescription, for sessionId: String)
}

/// WebRTC接続を管理するサービス
class WebRTCService: NSObject, @unchecked Sendable {
    static let shared = WebRTCService()
    
    weak var delegate: WebRTCServiceDelegate?
    
    // MARK: - Properties
    
    private static var peerConnectionFactory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }()
    
    /// アクティブなPeerConnection（sessionId -> WebRTCClient）
    private var clients: [String: WebRTCClient] = [:]
    
    /// ローカルビデオトラック（カメラ側用）
    private var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    
    /// ローカルオーディオトラック（カメラ側用）
    private var localAudioTrack: RTCAudioTrack?
    private var localAudioSource: RTCAudioSource?
    
    /// モニター側のローカルオーディオトラック（プッシュ・トゥ・トーク用）
    private var monitorLocalAudioTrack: RTCAudioTrack?
    private var monitorLocalAudioSource: RTCAudioSource?
    
    /// セッションIDからmonitorUserIdへのマッピング（ユーザー単位の音声制御用）
    private var sessionToUserId: [String: String] = [:]
    
    /// ICEサーバー設定
    private let iceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["stun:stun2.l.google.com:19302"])
    ]
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        configureRTCAudioSession()
    }
    
    /// RTCAudioSessionを設定してWebRTCがオーディオルートを上書きしないようにする
    private func configureRTCAudioSession() {
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        
        // WebRTCのデフォルトオーディオ設定を上書き
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        config.mode = AVAudioSession.Mode.videoChat.rawValue
        
        do {
            try rtcAudioSession.setConfiguration(config)
        } catch {
            print("WebRTCService: RTCAudioSession設定エラー - \(error.localizedDescription)")
        }
        
        rtcAudioSession.unlockForConfiguration()
        
        // WebRTCのデフォルト設定も更新
        RTCAudioSessionConfiguration.setWebRTC(config)
    }
    
    // MARK: - Camera Side (送信側)
    
    /// ローカルビデオトラックを作成（カメラ側）
    func setupLocalVideoTrack(captureService: CameraCaptureService) {
        let videoSource = Self.peerConnectionFactory.videoSource()
        localVideoSource = videoSource
        
        let videoTrack = Self.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        videoTrack.isEnabled = true
        localVideoTrack = videoTrack
        
        // CameraCaptureServiceからフレームを受け取る設定
        captureService.delegate = self
    }
    
    /// ローカルオーディオトラックを作成（カメラ側）
    func setupLocalAudioTrack() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = Self.peerConnectionFactory.audioSource(with: constraints)
        let audioTrack = Self.peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.isEnabled = true
        localAudioTrack = audioTrack
        localAudioSource = audioSource
    }
    
    /// 新しいモニター接続を処理（カメラ側: SDP Offerを受け取ってAnswerを返す）
    func handleIncomingSession(sessionId: String, offer: RTCSessionDescription, monitorUserId: String? = nil) async throws {
        let client = try createPeerConnection(sessionId: sessionId)
        
        // monitorUserIdをマッピングに保存
        if let userId = monitorUserId {
            sessionToUserId[sessionId] = userId
        }
        
        let streamId = "stream0"
        
        // ローカルビデオトラックを追加
        if let localVideoTrack = localVideoTrack {
            if let videoSender = client.peerConnection.add(localVideoTrack, streamIds: [streamId]) {
                client.setVideoSender(videoSender)
            }
        }
        
        // ローカルオーディオトラックを追加（デフォルトOFF）
        if let localAudioTrack = localAudioTrack {
            if let audioSender = client.peerConnection.add(localAudioTrack, streamIds: [streamId]) {
                client.setAudioSender(audioSender)
                // デフォルトOFF: 明示的に許可されるまで音声を送信しない
                audioSender.track = nil
            }
        }
        
        // Offerを設定（completion handler版を使用 - Swift async版は実機でハングする場合がある）
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.peerConnection.setRemoteDescription(offer) { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        
        // remote description設定後、キューに溜まったICE Candidateを処理
        drainPendingICECandidates(sessionId: sessionId)
        
        // Answerを生成（completion handler版を使用）
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            client.peerConnection.answer(for: constraints) { sdp, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let sdp = sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: WebRTCError.answerCreationFailed) }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.peerConnection.setLocalDescription(answer) { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        
        // SDP設定後にエンコーディングパラメータを設定（初期値は1080p、解像度優先）
        // 注意: SDPが設定された後にパラメータを設定する必要がある場合があります
        if let videoSender = client.videoSender {
            configureVideoEncoding(sender: videoSender, for1080p: true, preferResolution: true)
        }
        
        delegate?.webRTCService(self, didGenerateAnswer: answer, for: sessionId)
    }
    
    // MARK: - Monitor Side (受信側)
    
    /// モニター側から接続を開始（SDP Offerを生成）
    func startConnection(sessionId: String) async throws {
        let client = try createPeerConnection(sessionId: sessionId)
        
        // モニター側のローカルオーディオトラックを作成（プッシュ・トゥ・トーク用、初期状態は無効）
        if monitorLocalAudioTrack == nil {
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let audioSource = Self.peerConnectionFactory.audioSource(with: constraints)
            let audioTrack = Self.peerConnectionFactory.audioTrack(with: audioSource, trackId: "monitorAudio0")
            audioTrack.isEnabled = false  // 初期状態は無効
            monitorLocalAudioTrack = audioTrack
            monitorLocalAudioSource = audioSource
        }
        
        // モニター側のローカルオーディオトラックを追加
        if let monitorAudioTrack = monitorLocalAudioTrack {
            let streamId = "monitorStream0"
            client.peerConnection.add(monitorAudioTrack, streamIds: [streamId])
        }
        
        // Offerを生成（音声受信を有効化）
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        // completion handler版を使用（Swift async版は実機でハングする場合がある）
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            client.peerConnection.offer(for: constraints) { sdp, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let sdp = sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: WebRTCError.offerCreationFailed) }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.peerConnection.setLocalDescription(offer) { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        
        delegate?.webRTCService(self, didGenerateOffer: offer, for: sessionId)
    }
    
    /// SDP Answerを受け取って設定（モニター側）
    func handleAnswer(sessionId: String, answer: RTCSessionDescription) async throws {
        guard let client = clients[sessionId] else {
            print("WebRTCService.handleAnswer: セッションが見つかりません - \(sessionId)")
            throw WebRTCError.sessionNotFound
        }
        
        // 既にremote descriptionが設定されている場合はスキップ（重複呼び出し防止）
        if client.peerConnection.remoteDescription != nil {
            print("WebRTCService.handleAnswer: 既にremote descriptionが設定済みのためスキップ - \(sessionId)")
            return
        }
        
        print("WebRTCService.handleAnswer: Answerを設定します - \(sessionId), signalingState=\(client.peerConnection.signalingState.rawValue)")
        // completion handler版を使用（Swift async版は実機でcompletionが返らないケースがあるため）
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.peerConnection.setRemoteDescription(answer) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        // 即座にキューをドレイン（setRemoteDescription直後に実行し、既にキューされた候補を取りこぼさない）
        let immediatePending = client.drainPendingCandidates()
        for c in immediatePending {
            client.peerConnection.add(c) { _ in }
        }
        print("WebRTCService.handleAnswer: Answerを設定しました - \(sessionId)")
        
        // Unified Plan: デリゲートが呼ばれない場合のフォールバック - transceivers からトラックを取得
        if client.remoteVideoTrack == nil || client.remoteAudioTrack == nil {
            client.extractRemoteTracksFromTransceivers()
        }
        
        // 遅延フォールバック: receiver.track が非同期で設定される実装に対応（複数回試行）
        let sid = sessionId
        for delay in [0.3, 0.8, 1.5] as [Double] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self,
                      let c = self.clients[sid],
                      c.remoteVideoTrack == nil || c.remoteAudioTrack == nil else { return }
                c.extractRemoteTracksFromTransceivers()
                #if DEBUG
                print("WebRTCService.handleAnswer: 遅延フォールバック(\(delay)s)でtransceiversからトラック取得試行 - \(sid.prefix(8))")
                #endif
            }
        }
        
        // remote description設定後、キューに溜まったICE Candidateを処理（fire-and-forget）
        let pendingCandidates = client.drainPendingCandidates()
        #if DEBUG
        if !pendingCandidates.isEmpty {
            print("WebRTCService.handleAnswer: キューに溜まったICE候補 \(pendingCandidates.count)件を追加 - \(sessionId)")
        }
        #endif
        
        for candidate in pendingCandidates {
            client.peerConnection.add(candidate) { error in
                if let error = error {
                    print("WebRTCService.handleAnswer: キューからICE候補追加エラー - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Common
    
    /// ICE Candidateを追加（同期版 - async/awaitデッドロック回避）
    /// setRemoteDescription完了前はキューに保存、完了後はfire-and-forgetで直接追加
    func addICECandidate(sessionId: String, candidate: RTCIceCandidate) {
        guard let client = clients[sessionId] else { return }
        // remote descriptionが設定されていない場合はキューに保存
        guard client.peerConnection.remoteDescription != nil else {
            client.addPendingCandidate(candidate)
            #if DEBUG
            print("WebRTCService: ICE候補キューイング - \(candidate.sdp.prefix(80))")
            #endif
            return
        }
        // completion handler版で直接追加（fire-and-forget、awaitしない）
        client.peerConnection.add(candidate) { error in
            #if DEBUG
            if let error = error {
                print("WebRTCService: ICE候補追加エラー - \(error.localizedDescription)")
            } else {
                print("WebRTCService: ICE候補追加成功 - \(candidate.sdp.prefix(80))")
            }
            #endif
        }
    }
    
    /// キューに溜まったICE Candidateを処理（remote description設定後に呼び出す）- 同期版
    private func drainPendingICECandidates(sessionId: String) {
        guard let client = clients[sessionId] else { return }
        
        let pendingCandidates = client.drainPendingCandidates()
        guard !pendingCandidates.isEmpty else { return }
        
        #if DEBUG
        print("WebRTCService: キューに溜まったICE Candidateを処理開始: \(pendingCandidates.count)件")
        #endif
        
        for candidate in pendingCandidates {
            client.peerConnection.add(candidate) { error in
                if let error = error {
                    print("WebRTCService: キューからICE Candidate追加エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// セッションを終了
    func closeSession(sessionId: String) {
        guard let client = clients[sessionId] else { return }
        
        // 辞書から即座に削除（新しい操作を防止）
        clients.removeValue(forKey: sessionId)
        sessionToUserId.removeValue(forKey: sessionId)
        
        // デリゲートをnil化してコールバックを防止
        client.peerConnection.delegate = nil
        client.delegate = nil
        
        // 同期実行に戻す（バックグラウンド実行だと共有シグナリングスレッドでレースが発生し、
        // 次の接続の setRemoteDescription/add(candidate) のコールバックがハングする）
        client.peerConnection.close()
    }
    
    /// すべてのセッションを終了
    func closeAllSessions() {
        let clientsCopy = clients
        clients.removeAll()
        sessionToUserId.removeAll()
        
        for (_, client) in clientsCopy {
            client.peerConnection.delegate = nil
            client.delegate = nil
            client.peerConnection.close()
        }
    }
    
    /// ゴーストクライアント（切断/失敗/クローズ状態のまま残っているクライアント、または接続中でタイムアウトしたクライアント）を検出してクローズする。
    /// カメラ側で定期呼び出ししてリソース漏れを防止する。
    /// - Returns: クローズしたセッションIDのリスト（呼び出し側でFirestore等のクリーンアップに利用可能）
    func closeGhostClients() -> [String] {
        let ghostStates: Set<RTCPeerConnectionState> = [.disconnected, .failed, .closed]
        let now = Date()
        let timeoutSeconds: TimeInterval = 30
        let ghostIds = clients.filter { entry in
            let state = entry.value.peerConnection.connectionState
            if ghostStates.contains(state) { return true }
            // .new/.connecting が30秒以上続いている場合もゴーストとして扱う
            if state == .new || state == .connecting {
                return now.timeIntervalSince(entry.value.createdAt) > timeoutSeconds
            }
            return false
        }.map { $0.key }
        for sessionId in ghostIds {
            closeSession(sessionId: sessionId)
        }
        return ghostIds
    }
    
    /// セッションの接続状態を取得
    func connectionState(for sessionId: String) -> WebRTCConnectionState? {
        guard let client = clients[sessionId] else { return nil }
        return mapConnectionState(client.peerConnection.connectionState)
    }
    
    /// リモートビデオトラックを取得（モニター側）
    func remoteVideoTrack(for sessionId: String) -> RTCVideoTrack? {
        return clients[sessionId]?.remoteVideoTrack
    }
    
    /// リモートオーディオトラックを取得（モニター側）
    func remoteAudioTrack(for sessionId: String) -> RTCAudioTrack? {
        return clients[sessionId]?.remoteAudioTrack
    }
    
    // MARK: - Audio Control (Camera Side)
    
    /// 特定セッションの音声を有効/無効化（カメラ側）
    func setAudioEnabled(sessionId: String, enabled: Bool) {
        guard let client = clients[sessionId],
              let audioSender = client.audioSender else {
            print("WebRTCService: setAudioEnabled - sessionId not found or audioSender is nil")
            return
        }
        
        audioSender.track = enabled ? localAudioTrack : nil
        print("WebRTCService: setAudioEnabled - sessionId=\(sessionId), enabled=\(enabled)")
    }
    
    /// 特定ユーザーの全セッションの音声を有効/無効化（カメラ側）
    func setAudioEnabledForUser(userId: String, enabled: Bool) {
        let targetSessions = sessionToUserId.compactMap { sessionId, mappedUserId in
            mappedUserId == userId ? sessionId : nil
        }
        
        for sessionId in targetSessions {
            setAudioEnabled(sessionId: sessionId, enabled: enabled)
        }
        
        print("WebRTCService: setAudioEnabledForUser - userId=\(userId), enabled=\(enabled), sessions=\(targetSessions)")
    }
    
    // MARK: - Audio Control (Monitor Side)
    
    /// モニター側のマイクを有効/無効化（プッシュ・トゥ・トーク用）
    func setMonitorMicEnabled(sessionId: String, enabled: Bool) {
        monitorLocalAudioTrack?.isEnabled = enabled
        print("WebRTCService: setMonitorMicEnabled - sessionId=\(sessionId), enabled=\(enabled)")
    }
    
    // MARK: - Video Encoding Control
    
    /// ビデオエンコーディングパラメータを設定
    private func configureVideoEncoding(sender: RTCRtpSender, for1080p: Bool, preferResolution: Bool = true) {
        let params = sender.parameters
        
        // degradationPreference を設定
        // maintainResolution: 解像度を優先（帯域幅不足時はフレームレートを下げる）
        // maintainFramerate: フレームレートを優先（帯域幅不足時は解像度を下げる）
        // balanced: バランス型（解像度とフレームレートの両方を調整）
        if preferResolution {
            // 解像度を優先（デフォルト）
            params.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        } else {
            // フレームレートが低すぎる場合はバランス型に切り替え
            params.degradationPreference = NSNumber(value: RTCDegradationPreference.balanced.rawValue)
        }
        
        if params.encodings.isEmpty {
            params.encodings = [RTCRtpEncodingParameters()]
        }
        for encoding in params.encodings {
            encoding.isActive = true
            encoding.maxFramerate = NSNumber(value: 30)
            encoding.scaleResolutionDownBy = NSNumber(value: 1.0)  // スケールダウンを防止（解像度維持のため）
            if for1080p {
                encoding.maxBitrateBps = NSNumber(value: 8_000_000)  // 8Mbps（1080p、Wi-Fi環境での高画質化）
                encoding.minBitrateBps = NSNumber(value: 2_000_000)  // 最低2Mbps（1080p）
            } else {
                encoding.maxBitrateBps = NSNumber(value: 3_500_000)  // 3.5Mbps（720p）
                encoding.minBitrateBps = NSNumber(value: 1_000_000)  // 最低1Mbps（720p）
            }
        }
        
        // パラメータを送信者に設定（copyセマンティクスのため明示的に設定が必要）
        sender.parameters = params
    }
    
    /// 全セッションのビデオエンコーディングパラメータを更新（品質変更時）
    func updateVideoEncodingForAllSessions(for1080p: Bool, preferResolution: Bool = true) {
        for (_, client) in clients {
            if let videoSender = client.videoSender {
                configureVideoEncoding(sender: videoSender, for1080p: for1080p, preferResolution: preferResolution)
            }
        }
    }
    
    /// フレームレートに基づいて動的にエンコーディングパラメータを更新
    /// フレームレートが低すぎる場合は解像度を下げてフレームレートを回復させる
    func updateVideoEncodingBasedOnFrameRate(for1080p: Bool, currentFrameRate: Double) {
        // 1080pを維持しつつ、フレームレートを24fps以上に保つ
        // 24fps未満の場合はバランス型に切り替え（解像度を下げてフレームレートを回復）
        // 24fps以上の場合、または1080pでない場合は解像度優先を維持
        let preferResolution = currentFrameRate >= 24.0 || !for1080p
        
        for (_, client) in clients {
            if let videoSender = client.videoSender {
                configureVideoEncoding(sender: videoSender, for1080p: for1080p, preferResolution: preferResolution)
            }
        }
    }
    
    /// ビットレートを動的に調整してフレームレートを改善
    func adjustBitrateForFrameRate(for1080p: Bool, currentFrameRate: Double) {
        for (_, client) in clients {
            guard let videoSender = client.videoSender else { continue }
            let params = videoSender.parameters
            
            if params.encodings.isEmpty {
                continue
            }
            
            for encoding in params.encodings {
                encoding.isActive = true
                encoding.maxFramerate = NSNumber(value: 30)
                
                if for1080p {
                    // フレームレートが24fps未満の場合、ビットレートを少し下げて安定性を向上
                    if currentFrameRate < 24.0 {
                        // ビットレートを下げて帯域幅不足を解消（フレームレートを回復）
                        encoding.maxBitrateBps = NSNumber(value: 5_000_000)  // 5Mbps（少し下げる）
                        encoding.minBitrateBps = NSNumber(value: 1_500_000)  // 1.5Mbps
                    } else {
                        // フレームレートが十分な場合は通常のビットレート
                        encoding.maxBitrateBps = NSNumber(value: 8_000_000)  // 8Mbps
                        encoding.minBitrateBps = NSNumber(value: 2_000_000)  // 2Mbps
                    }
                } else {
                    // 720pの場合
                    encoding.maxBitrateBps = NSNumber(value: 3_500_000)  // 3.5Mbps（720p）
                    encoding.minBitrateBps = NSNumber(value: 1_000_000)  // 1Mbps
                }
            }
            
            videoSender.parameters = params
        }
    }
    
    // MARK: - Statistics
    
    /// セッションの統計情報を取得
    func getStats(for sessionId: String) async -> RTCStatisticsReport? {
        guard let client = clients[sessionId] else { return nil }
        return await client.peerConnection.statistics()
    }
    
    /// 全セッションの統計情報を取得
    func getAllSessionStats() async -> [String: RTCStatisticsReport] {
        var stats: [String: RTCStatisticsReport] = [:]
        for (sessionId, client) in clients {
            // 接続中のセッションのみ統計情報を取得
            if client.peerConnection.connectionState == .connected {
                let report = await client.peerConnection.statistics()
                stats[sessionId] = report
            }
        }
        return stats
    }
    
    // MARK: - Private Methods
    
    private func createPeerConnection(sessionId: String) throws -> WebRTCClient {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually  // ネットワーク変動時にも新しいICE候補を生成
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        guard let peerConnection = Self.peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: nil
        ) else {
            throw WebRTCError.peerConnectionCreationFailed
        }
        
        let client = WebRTCClient(sessionId: sessionId, peerConnection: peerConnection)
        client.delegate = self
        peerConnection.delegate = client
        
        clients[sessionId] = client
        return client
    }
    
    private func mapConnectionState(_ state: RTCPeerConnectionState) -> WebRTCConnectionState {
        switch state {
        case .new:
            return .new
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .disconnected:
            return .disconnected
        case .failed:
            return .failed
        case .closed:
            return .closed
        @unknown default:
            return .new
        }
    }
}

// MARK: - CameraCaptureDelegate

extension WebRTCService: CameraCaptureDelegate {
    func cameraCaptureService(_ service: CameraCaptureService, didCapture sampleBuffer: CMSampleBuffer) {
        guard let videoSource = localVideoSource,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._90, timeStampNs: Int64(timeStampNs))
        
        videoSource.capturer(RTCVideoCapturer(), didCapture: videoFrame)
    }
}

// MARK: - WebRTCClientDelegate

extension WebRTCService: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState) {
        let mappedState = mapConnectionState(state)
        delegate?.webRTCService(self, didChangeState: mappedState, for: client.sessionId)
    }
    
    func webRTCClient(_ client: WebRTCClient, didGenerateICECandidate candidate: RTCIceCandidate) {
        delegate?.webRTCService(self, didGenerateICECandidate: candidate, for: client.sessionId)
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        delegate?.webRTCService(self, didReceiveRemoteVideoTrack: track, for: client.sessionId)
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteAudioTrack track: RTCAudioTrack) {
        delegate?.webRTCService(self, didReceiveRemoteAudioTrack: track, for: client.sessionId)
    }
}

// MARK: - Error

enum WebRTCError: LocalizedError {
    case sessionNotFound
    case connectionFailed
    case offerCreationFailed
    case answerCreationFailed
    case peerConnectionCreationFailed

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "セッションが見つかりません"
        case .connectionFailed:
            return "接続に失敗しました"
        case .offerCreationFailed:
            return "Offerの作成に失敗しました"
        case .answerCreationFailed:
            return "Answerの作成に失敗しました"
        case .peerConnectionCreationFailed:
            return "接続の初期化に失敗しました"
        }
    }
}

