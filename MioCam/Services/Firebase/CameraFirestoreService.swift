//
//  CameraFirestoreService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore
import Combine

/// カメラのFirestore操作サービス
class CameraFirestoreService {
    static let shared = CameraFirestoreService()
    
    private let db = FirestoreService.shared.db
    private var cameraListeners: [String: ListenerRegistration] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let cameraIdKeyPrefix = "MioCam_CameraId_"
    
    private init() {}
    
    // MARK: - Camera ID Persistence
    
    /// カメラIDをUserDefaultsに保存
    private func saveCameraId(_ cameraId: String, ownerUserId: String) {
        let key = cameraIdKeyPrefix + ownerUserId
        userDefaults.set(cameraId, forKey: key)
    }
    
    /// UserDefaultsからカメラIDを取得
    func getSavedCameraId(ownerUserId: String) -> String? {
        let key = cameraIdKeyPrefix + ownerUserId
        return userDefaults.string(forKey: key)
    }
    
    /// 保存されたカメラIDを削除
    private func removeSavedCameraId(ownerUserId: String) {
        let key = cameraIdKeyPrefix + ownerUserId
        userDefaults.removeObject(forKey: key)
    }
    
    /// アカウント削除時にUserDefaultsからカメラIDをクリア（AccountDeletionService用）
    func clearSavedCameraIdForDeletion(ownerUserId: String) {
        removeSavedCameraId(ownerUserId: ownerUserId)
    }
    
    /// 既存のカメラを取得（UserDefaultsからcameraIdを取得してFirestoreから読み込む）
    func getExistingCamera(ownerUserId: String) async throws -> CameraModel? {
        guard let savedCameraId = getSavedCameraId(ownerUserId: ownerUserId) else {
            return nil
        }
        
        // Firestoreからカメラ情報を取得
        return try await getCamera(cameraId: savedCameraId)
    }
    
    /// カメラを登録（新規作成）
    func registerCamera(ownerUserId: String, deviceName: String, deviceModel: String?, osVersion: String?) async throws -> String {
        let cameraRef = db.collection("cameras").document()
        let cameraId = cameraRef.documentID
        let pairingCode = FirestoreService.shared.generatePairingCode()
        
        let cameraData: [String: Any] = [
            "ownerUserId": ownerUserId,
            "pairingCode": pairingCode,
            "deviceName": deviceName,
            "deviceModel": deviceModel ?? "",
            "osVersion": osVersion ?? "",
            "pushToken": "",
            "isOnline": true,
            "lastSeenAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
            "connectedMonitorCount": 0
        ]
        
        // batteryLevelはnilの場合は辞書に含めない（Firestoreはnilを直接サポートしない）
        // 必要に応じてNSNull()を使うこともできるが、ここでは省略
        
        try await cameraRef.setData(cameraData)
        
        // UserDefaultsに保存
        saveCameraId(cameraId, ownerUserId: ownerUserId)
        
        return cameraId
    }
    
    /// 既存のカメラを復元（オンライン状態に更新）
    func restoreExistingCamera(cameraId: String, ownerUserId: String, deviceName: String) async throws {
        // カメラが存在するか確認
        guard let camera = try await getCamera(cameraId: cameraId),
              camera.ownerUserId == ownerUserId else {
            // カメラが存在しない、または所有者が異なる場合は新規作成
            throw NSError(domain: "CameraFirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "カメラが見つかりません"])
        }
        
        // オンライン状態に更新
        try await updateCameraStatus(cameraId: cameraId, isOnline: true, batteryLevel: nil)
        
        // UserDefaultsに保存（念のため）
        saveCameraId(cameraId, ownerUserId: ownerUserId)
    }
    
    /// カメラ情報を取得
    func getCamera(cameraId: String) async throws -> CameraModel? {
        let doc = try await db.collection("cameras").document(cameraId).getDocument()
        return try? doc.data(as: CameraModel.self)
    }
    
    /// カメラの状態を更新
    func updateCameraStatus(cameraId: String, isOnline: Bool, batteryLevel: Int?) async throws {
        var updateData: [String: Any] = [
            "isOnline": isOnline,
            "lastSeenAt": FieldValue.serverTimestamp()
        ]
        
        if let batteryLevel = batteryLevel {
            updateData["batteryLevel"] = batteryLevel
        }
        
        try await db.collection("cameras").document(cameraId).updateData(updateData)
    }
    
    /// カメラのデバイス名を更新
    func updateDeviceName(cameraId: String, deviceName: String) async throws {
        try await db.collection("cameras").document(cameraId).updateData([
            "deviceName": deviceName
        ])
    }
    
    /// ペアリングコードを再生成
    func regeneratePairingCode(cameraId: String) async throws -> String {
        let newPairingCode = FirestoreService.shared.generatePairingCode()
        try await db.collection("cameras").document(cameraId).updateData([
            "pairingCode": newPairingCode
        ])
        return newPairingCode
    }
    
    /// 接続中のモニター数を更新
    func updateConnectedMonitorCount(cameraId: String, count: Int) async throws {
        try await db.collection("cameras").document(cameraId).updateData([
            "connectedMonitorCount": count
        ])
    }
    
    /// カメラドキュメントの変更を監視（リアルタイムリスナー）
    func observeCamera(cameraId: String, completion: @escaping (Result<CameraModel?, Error>) -> Void) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion(.success(nil))
                    return
                }
                
                // try?を使っているため、エラーはnilに変換される
                let camera = try? snapshot.data(as: CameraModel.self)
                completion(.success(camera))
            }
        
        cameraListeners[cameraId] = listener
        return listener
    }
    
    /// カメラの監視を停止
    func stopObservingCamera(cameraId: String) {
        cameraListeners[cameraId]?.remove()
        cameraListeners.removeValue(forKey: cameraId)
    }
    
    /// 全ての監視を停止
    func stopAllObservers() {
        cameraListeners.values.forEach { $0.remove() }
        cameraListeners.removeAll()
    }
}
