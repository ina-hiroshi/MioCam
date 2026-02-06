//
//  UserModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore `/users/{userId}` ドキュメントのデータモデル
struct UserModel: Codable, Identifiable {
    @DocumentID var id: String?
    var appleUserId: String
    var displayName: String?
    var createdAt: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case id
        case appleUserId
        case displayName
        case createdAt
    }
}
