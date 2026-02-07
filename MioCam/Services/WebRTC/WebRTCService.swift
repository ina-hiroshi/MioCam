//
//  WebRTCService.swift
//  MioCam
//
//  WebRTC接続を管理するサービス
//

import Foundation
import WebRTC
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
class WebRTCService: NSObject {
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
        let client = createPeerConnection(sessionId: sessionId)
        
        // monitorUserIdをマッピングに保存
        if let userId = monitorUserId {
            sessionToUserId[sessionId] = userId
        }
        
        let streamId = "stream0"
        
        // ローカルビデオトラックを追加
        if let localVideoTrack = localVideoTrack {
            client.peerConnection.add(localVideoTrack, streamIds: [streamId])
        }
        
        // ローカルオーディオトラックを追加（デフォルトOFF）
        if let localAudioTrack = localAudioTrack {
            if let audioSender = client.peerConnection.add(localAudioTrack, streamIds: [streamId]) {
                client.setAudioSender(audioSender)
                // デフォルトOFF: 明示的に許可されるまで音声を送信しない
                audioSender.track = nil
            }
        }
        
        // Offerを設定
        try await client.peerConnection.setRemoteDescription(offer)
        
        // Answerを生成
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let answer = try await client.peerConnection.answer(for: constraints)
        try await client.peerConnection.setLocalDescription(answer)
        
        delegate?.webRTCService(self, didGenerateAnswer: answer, for: sessionId)
    }
    
    // MARK: - Monitor Side (受信側)
    
    /// モニター側から接続を開始（SDP Offerを生成）
    func startConnection(sessionId: String) async throws {
        let client = createPeerConnection(sessionId: sessionId)
        
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
        let offer = try await client.peerConnection.offer(for: constraints)
        try await client.peerConnection.setLocalDescription(offer)
        
        delegate?.webRTCService(self, didGenerateOffer: offer, for: sessionId)
    }
    
    /// SDP Answerを受け取って設定（モニター側）
    func handleAnswer(sessionId: String, answer: RTCSessionDescription) async throws {
        guard let client = clients[sessionId] else {
            throw WebRTCError.sessionNotFound
        }
        
        try await client.peerConnection.setRemoteDescription(answer)
    }
    
    // MARK: - Common
    
    /// ICE Candidateを追加
    func addICECandidate(sessionId: String, candidate: RTCIceCandidate) async throws {
        guard let client = clients[sessionId] else {
            throw WebRTCError.sessionNotFound
        }
        
        // remote descriptionが設定されていない場合はエラーを無視（後で再試行される）
        guard client.peerConnection.remoteDescription != nil else {
            return
        }
        
        try await client.peerConnection.add(candidate)
    }
    
    /// セッションを終了
    func closeSession(sessionId: String) {
        guard let client = clients[sessionId] else { return }
        client.peerConnection.close()
        clients.removeValue(forKey: sessionId)
        sessionToUserId.removeValue(forKey: sessionId)
    }
    
    /// すべてのセッションを終了
    func closeAllSessions() {
        for (sessionId, client) in clients {
            client.peerConnection.close()
            clients.removeValue(forKey: sessionId)
        }
        sessionToUserId.removeAll()
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
    
    // MARK: - Private Methods
    
    private func createPeerConnection(sessionId: String) -> WebRTCClient {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        guard let peerConnection = Self.peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: nil
        ) else {
            fatalError("Failed to create peer connection")
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
        }
    }
}
