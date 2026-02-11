//
//  AccountDeletionService.swift
//  MioCam
//
//  アカウント削除時のFirestoreデータ削除を担当
//

import Foundation
import FirebaseFirestore

/// ユーザーアカウントに関連するFirestoreデータを削除するサービス
class AccountDeletionService {
    static let shared = AccountDeletionService()
    
    private let db = FirestoreService.shared.db

    private init() {}
    
    /// 指定ユーザーに関連するすべてのFirestoreデータを削除
    func deleteAllUserData(userId: String) async throws {
        // 1. 自分のカメラを取得（ownerUserIdでクエリ）
        let camerasSnapshot = try await db.collection("cameras")
            .whereField("ownerUserId", isEqualTo: userId)
            .getDocuments()
        
        // 2. 各カメラについて: sessions → iceCandidates → session → camera の順で削除
        for cameraDoc in camerasSnapshot.documents {
            let cameraId = cameraDoc.documentID
            try await deleteCameraAndSubcollections(cameraId: cameraId)
        }
        
        // 3. monitorLinks（monitorUserIdでクエリ）を削除
        let linksSnapshot = try await db.collection("monitorLinks")
            .whereField("monitorUserId", isEqualTo: userId)
            .getDocuments()
        
        if !linksSnapshot.documents.isEmpty {
            let batch = db.batch()
            for doc in linksSnapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }
        
        // 4. users/{userId}/subscription/current を削除
        let subscriptionRef = db.collection("users").document(userId)
            .collection("subscription").document("current")
        try await subscriptionRef.delete()
        
        // 5. users/{userId} を削除
        let userRef = db.collection("users").document(userId)
        try await userRef.delete()
        
        // 6. UserDefaultsのカメラIDをクリア
        CameraFirestoreService.shared.clearSavedCameraIdForDeletion(ownerUserId: userId)
    }
    
    /// カメラとそのサブコレクション（sessions, iceCandidates）を削除
    private func deleteCameraAndSubcollections(cameraId: String) async throws {
        let sessionsRef = db.collection("cameras").document(cameraId).collection("sessions")
        let sessionsSnapshot = try await sessionsRef.getDocuments()
        
        for sessionDoc in sessionsSnapshot.documents {
            let sessionId = sessionDoc.documentID
            
            // iceCandidates サブコレクションを削除
            let iceCandidatesRef = sessionsRef.document(sessionId).collection("iceCandidates")
            let iceSnapshot = try await iceCandidatesRef.getDocuments()
            
            if !iceSnapshot.documents.isEmpty {
                let batch = db.batch()
                for doc in iceSnapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                try await batch.commit()
            }
            
            // session ドキュメントを削除
            try await sessionDoc.reference.delete()
        }
        
        // カメラドキュメントを削除
        try await db.collection("cameras").document(cameraId).delete()
    }
}
