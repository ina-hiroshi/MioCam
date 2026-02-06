//
//  MonitorLinkModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore `/monitorLinks/{linkId}` ドキュメントのデータモデル
struct MonitorLinkModel: Codable, Identifiable {
    @DocumentID var id: String?
    var monitorUserId: String
    var cameraId: String
    var cameraDeviceName: String
    var pairedAt: Timestamp
    var isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case monitorUserId
        case cameraId
        case cameraDeviceName
        case pairedAt
        case isActive
    }
}
