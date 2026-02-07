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
    
    init(sessionId: String, peerConnection: RTCPeerConnection) {
        self.sessionId = sessionId
        self.peerConnection = peerConnection
        super.init()
    }
    
    /// オーディオ送信者を設定（カメラ側で使用）
    func setAudioSender(_ sender: RTCRtpSender) {
        self.audioSender = sender
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC: Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC: Did add stream: \(stream.streamId)")
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "L", "location": "WebRTCClient.swift:54", "message": "ストリーム追加", "data": ["streamId": stream.streamId, "videoTrackCount": stream.videoTracks.count, "audioTrackCount": stream.audioTracks.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        
        // リモートビデオトラックを取得
        if let videoTrack = stream.videoTracks.first {
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "L", "location": "WebRTCClient.swift:58", "message": "ビデオトラック検出", "data": ["trackId": videoTrack.trackId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
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
        print("WebRTC: ICE connection state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("WebRTC: ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("WebRTC: Did generate ICE candidate")
        delegate?.webRTCClient(self, didGenerateICECandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("WebRTC: Did remove ICE candidates: \(candidates.count)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("WebRTC: Did open data channel: \(dataChannel.label)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        print("WebRTC: Connection state changed: \(stateChanged.rawValue)")
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
