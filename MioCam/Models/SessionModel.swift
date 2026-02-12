//
//  SessionModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore `/cameras/{cameraId}/sessions/{sessionId}` ドキュメントのデータモデル
struct SessionModel: Codable, Identifiable {
    @DocumentID var id: String?
    var monitorUserId: String
    var monitorDeviceId: String
    var monitorDeviceName: String
    var displayName: String? // モニター側の表示名（オプショナル）
    var offer: [String: Any]? // SDP Offer (RTCSessionDescription)
    var answer: [String: Any]? // SDP Answer (RTCSessionDescription)
    var status: SessionStatus
    var isAudioEnabled: Bool? // カメラ側からの音声送信が有効かどうか（デフォルト: false）
    var createdAt: Timestamp
    
    enum SessionStatus: String, Codable {
        case waiting
        case connected
        case disconnected
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case monitorUserId
        case monitorDeviceId
        case monitorDeviceName
        case displayName
        case offer
        case answer
        case status
        case isAudioEnabled
        case createdAt
    }
    
    // SDPは[String: Any]として扱うため、カスタムエンコード/デコードが必要
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        monitorUserId = try container.decode(String.self, forKey: .monitorUserId)
        monitorDeviceId = try container.decode(String.self, forKey: .monitorDeviceId)
        monitorDeviceName = try container.decode(String.self, forKey: .monitorDeviceName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        status = try container.decode(SessionStatus.self, forKey: .status)
        isAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAudioEnabled)
        createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        
        // SDPは[String: Any]としてデコードを試みる
        // Firestoreから直接取得する場合は、doc.data()から取得する方が確実
        offer = nil
        answer = nil
    }
    
    /// Firestoreのドキュメントデータから直接初期化（SDPを含む）
    init?(from documentData: [String: Any], documentId: String?) {
        guard let monitorUserId = documentData["monitorUserId"] as? String,
              let monitorDeviceId = documentData["monitorDeviceId"] as? String,
              let monitorDeviceName = documentData["monitorDeviceName"] as? String,
              let statusString = documentData["status"] as? String,
              let status = SessionStatus(rawValue: statusString),
              let createdAt = documentData["createdAt"] as? Timestamp else {
            return nil
        }
        
        self.id = documentId
        self.monitorUserId = monitorUserId
        self.monitorDeviceId = monitorDeviceId
        self.monitorDeviceName = monitorDeviceName
        self.displayName = documentData["displayName"] as? String
        self.status = status
        self.isAudioEnabled = documentData["isAudioEnabled"] as? Bool
        self.createdAt = createdAt
        
        // SDPを[String: Any]として取得
        self.offer = documentData["offer"] as? [String: Any]
        self.answer = documentData["answer"] as? [String: Any]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(monitorUserId, forKey: .monitorUserId)
        try container.encode(monitorDeviceId, forKey: .monitorDeviceId)
        try container.encode(monitorDeviceName, forKey: .monitorDeviceName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(isAudioEnabled, forKey: .isAudioEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        // offer/answerは別途Firestoreに書き込む
    }
}
