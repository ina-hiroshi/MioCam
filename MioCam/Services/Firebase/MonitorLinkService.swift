//
//  MonitorLinkService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// モニターリンク（ペアリング記録）のFirestore操作サービス
class MonitorLinkService {
    static let shared = MonitorLinkService()
    
    private let db = FirestoreService.shared.db
    
    private init() {}
    
    /// 同一ユーザーが同じcameraIdで複数リンクを持っている場合、古いリンクを無効化
    func deactivateDuplicateLinks(monitorUserId: String, cameraId: String, keepLinkId: String) async throws {
        let snapshot = try await db.collection("monitorLinks")
            .whereField("monitorUserId", isEqualTo: monitorUserId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let docsToDeactivate = snapshot.documents.filter {
            ($0.data()["cameraId"] as? String) == cameraId && $0.documentID != keepLinkId
        }
        guard !docsToDeactivate.isEmpty else { return }
        
        let batch = db.batch()
        for doc in docsToDeactivate {
            batch.updateData(["isActive": false], forDocument: doc.reference)
        }
        try await batch.commit()
    }
    
    /// ペアリング記録を作成（同一cameraIdの重複リンクは先に無効化）
    func createMonitorLink(
        monitorUserId: String,
        cameraId: String,
        cameraDeviceName: String
    ) async throws {
        let linkId = "\(monitorUserId)_\(cameraId)"
        
        // 同一ユーザー・同一カメラの既存アクティブリンクを無効化（異なるlinkIdのもの）
        try await deactivateDuplicateLinks(monitorUserId: monitorUserId, cameraId: cameraId, keepLinkId: linkId)
        
        let linkRef = db.collection("monitorLinks").document(linkId)
        let linkData: [String: Any] = [
            "monitorUserId": monitorUserId,
            "cameraId": cameraId,
            "cameraDeviceName": cameraDeviceName,
            "pairedAt": FieldValue.serverTimestamp(),
            "isActive": true
        ]
        
        try await linkRef.setData(linkData, merge: true)
    }
    
    /// ペアリング済みカメラ一覧を取得
    func getPairedCameras(monitorUserId: String) async throws -> [MonitorLinkModel] {
        let snapshot = try await db.collection("monitorLinks")
            .whereField("monitorUserId", isEqualTo: monitorUserId)
            .whereField("isActive", isEqualTo: true)
            .order(by: "pairedAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: MonitorLinkModel.self)
        }
    }
    
    /// ペアリングを解除（isActive: false）
    func deactivateMonitorLink(monitorUserId: String, cameraId: String) async throws {
        let linkId = "\(monitorUserId)_\(cameraId)"
        try await db.collection("monitorLinks").document(linkId).updateData([
            "isActive": false
        ])
    }
    
    /// カメラの存在確認とpairingCode検証を行い、検証成功時にCameraModelを返す（Firestore read 1回で済む）
    func verifyAndGetCamera(cameraId: String, pairingCode: String) async throws -> CameraModel? {
        let cameraDoc = try await db.collection("cameras").document(cameraId).getDocument()
        
        guard let data = cameraDoc.data(),
              let storedPairingCode = data["pairingCode"] as? String,
              storedPairingCode == pairingCode else {
            return nil
        }
        
        return try? cameraDoc.data(as: CameraModel.self)
    }
    
    /// カメラ名を更新（すべてのモニターリンクのcameraDeviceNameを更新）
    func updateCameraDeviceName(cameraId: String, deviceName: String) async throws {
        // 該当するカメラIDのすべてのモニターリンクを取得
        let snapshot = try await db.collection("monitorLinks")
            .whereField("cameraId", isEqualTo: cameraId)
            .getDocuments()
        
        // バッチ更新
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.updateData([
                "cameraDeviceName": deviceName
            ], forDocument: doc.reference)
        }
        
        try await batch.commit()
    }
    
    /// ペアリング済みカメラ一覧をリアルタイム監視
    func observePairedCameras(monitorUserId: String, completion: @escaping (Result<[MonitorLinkModel], Error>) -> Void) -> ListenerRegistration {
        return db.collection("monitorLinks")
            .whereField("monitorUserId", isEqualTo: monitorUserId)
            .whereField("isActive", isEqualTo: true)
            .order(by: "pairedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }
                
                let cameras = snapshot.documents.compactMap { doc in
                    try? doc.data(as: MonitorLinkModel.self)
                }
                
                completion(.success(cameras))
            }
    }
}
