//
//  ICECandidateModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore `/cameras/{cameraId}/sessions/{sessionId}/iceCandidates/{candidateId}` ドキュメントのデータモデル
struct ICECandidateModel: Codable, Identifiable {
    @DocumentID var id: String?
    var candidate: String // ICE Candidate文字列
    var sdpMid: String?
    var sdpMLineIndex: Int32?
    var sender: ICECandidateSender
    
    enum ICECandidateSender: String, Codable {
        case monitor
        case camera
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case candidate
        case sdpMid
        case sdpMLineIndex
        case sender
    }
}
