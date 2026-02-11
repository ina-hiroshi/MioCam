//
//  WebRTCClient.swift
//  MioCam
//
//  個別のWebRTC接続を管理するクライアント
//

import Foundation
import WebRTC

/// WebRTCクライアントのデリゲートプロトコル
protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCPeerConnectionState)
    func webRTCClient(_ client: WebRTCClient, didGenerateICECandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack)
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteAudioTrack track: RTCAudioTrack)
}

/// 個別のWebRTC接続を管理するクライアント
class WebRTCClient: NSObject {
    let sessionId: String
    let peerConnection: RTCPeerConnection
    
    weak var delegate: WebRTCClientDelegate?
    
    /// リモートビデオトラック（モニター側で受信）
    private(set) var remoteVideoTrack: RTCVideoTrack?
    
    /// リモートオーディオトラック（モニター側で受信）
    private(set) var remoteAudioTrack: RTCAudioTrack?
    
    /// オーディオ送信者（カメラ側で音声のミュート制御に使用）
    private(set) var audioSender: RTCRtpSender?
    
    /// ビデオ送信者（カメラ側でエンコーディングパラメータ制御に使用）
    private(set) var videoSender: RTCRtpSender?
    
    /// remote description設定前のICE Candidateキュー
    private var pendingICECandidates: [RTCIceCandidate] = []
    private let pendingCandidatesQueue = DispatchQueue(label: "MioCam.WebRTCClient.pendingCandidates")
    
    init(sessionId: String, peerConnection: RTCPeerConnection) {
        self.sessionId = sessionId
        self.peerConnection = peerConnection
        super.init()
    }
    
    /// オーディオ送信者を設定（カメラ側で使用）
    func setAudioSender(_ sender: RTCRtpSender) {
        self.audioSender = sender
    }
    
    /// ビデオ送信者を設定（カメラ側で使用）
    func setVideoSender(_ sender: RTCRtpSender) {
        self.videoSender = sender
    }
    
    /// remote description設定前のICE Candidateをキューに追加
    func addPendingCandidate(_ candidate: RTCIceCandidate) {
        pendingCandidatesQueue.async { [weak self] in
            self?.pendingICECandidates.append(candidate)
        }
    }
    
    /// キューに溜まったICE Candidateを取得してクリア（remote description設定後に呼び出す）
    func drainPendingCandidates() -> [RTCIceCandidate] {
        return pendingCandidatesQueue.sync {
            let candidates = pendingICECandidates
            pendingICECandidates.removeAll()
            return candidates
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC: Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC: Did add stream: \(stream.streamId)")
        
        // リモートビデオトラックを取得
        if let videoTrack = stream.videoTracks.first {
            remoteVideoTrack = videoTrack
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: videoTrack)
            }
        }
        
        // リモートオーディオトラックを取得
        if let audioTrack = stream.audioTracks.first {
            remoteAudioTrack = audioTrack
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.webRTCClient(self, didReceiveRemoteAudioTrack: audioTrack)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("WebRTC: Did remove stream: \(stream.streamId)")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("WebRTC: Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateNames = ["new", "checking", "connected", "completed", "failed", "disconnected", "closed", "count"]
        let stateName = newState.rawValue < stateNames.count ? stateNames[Int(newState.rawValue)] : "unknown"
        print("WebRTC: ICE connection state changed: \(stateName) (\(newState.rawValue))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("WebRTC: ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let typ = candidateType(from: candidate.sdp)
        print("WebRTC: Did generate ICE candidate (\(typ))")
        delegate?.webRTCClient(self, didGenerateICECandidate: candidate)
    }
    
    private func candidateType(from candidate: String) -> String {
        let parts = candidate.split(separator: " ")
        if let idx = parts.firstIndex(where: { $0 == "typ" }), idx + 1 < parts.count {
            return String(parts[idx + 1])
        }
        return "unknown"
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("WebRTC: Did remove ICE candidates: \(candidates.count)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("WebRTC: Did open data channel: \(dataChannel.label)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        let stateNames = ["new", "connecting", "connected", "disconnected", "failed", "closed"]
        let stateName = stateChanged.rawValue < stateNames.count ? stateNames[Int(stateChanged.rawValue)] : "unknown"
        print("WebRTC: Connection state changed: \(stateName) (\(stateChanged.rawValue))")
        delegate?.webRTCClient(self, didChangeConnectionState: stateChanged)
    }
}

// MARK: - SDP Helpers

extension RTCSessionDescription {
    /// SDPをDictionary形式に変換（Firestore保存用）
    func toDict() -> [String: Any] {
        return [
            "type": RTCSessionDescription.string(for: self.type),
            "sdp": self.sdp
        ]
    }
    
    /// DictionaryからRTCSessionDescriptionを生成
    static func from(dict: [String: Any]) -> RTCSessionDescription? {
        guard let typeString = dict["type"] as? String,
              let sdp = dict["sdp"] as? String else {
            return nil
        }
        
        let type: RTCSdpType
        switch typeString.lowercased() {
        case "offer":
            type = .offer
        case "pranswer":
            type = .prAnswer
        case "answer":
            type = .answer
        case "rollback":
            type = .rollback
        default:
            return nil
        }
        
        return RTCSessionDescription(type: type, sdp: sdp)
    }
}

extension RTCIceCandidate {
    /// ICE CandidateをDictionary形式に変換（Firestore保存用）
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "candidate": self.sdp
        ]
        if let sdpMid = self.sdpMid {
            dict["sdpMid"] = sdpMid
        }
        dict["sdpMLineIndex"] = self.sdpMLineIndex
        return dict
    }
    
    /// DictionaryからRTCIceCandidateを生成
    static func from(dict: [String: Any]) -> RTCIceCandidate? {
        guard let candidate = dict["candidate"] as? String else {
            return nil
        }
        
        let sdpMid = dict["sdpMid"] as? String
        let sdpMLineIndex = dict["sdpMLineIndex"] as? Int32 ?? 0
        
        return RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}
