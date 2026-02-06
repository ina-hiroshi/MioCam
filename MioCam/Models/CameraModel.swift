//
//  CameraModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore `/cameras/{cameraId}` ドキュメントのデータモデル
struct CameraModel: Codable, Identifiable {
    @DocumentID var id: String?
    var ownerUserId: String
    var pairingCode: String // 6桁英数字
    var deviceName: String
    var deviceModel: String?
    var osVersion: String?
    var pushToken: String?
    var isOnline: Bool
    var batteryLevel: Int? // 0-100
    var lastSeenAt: Timestamp?
    var createdAt: Timestamp
    var connectedMonitorCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId
        case pairingCode
        case deviceName
        case deviceModel
        case osVersion
        case pushToken
        case isOnline
        case batteryLevel
        case lastSeenAt
        case createdAt
        case connectedMonitorCount
    }
}
