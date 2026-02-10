//
//  SignalingService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// WebRTCシグナリング用のFirestore操作サービス
class SignalingService {
    static let shared = SignalingService()
    
    private let db = FirestoreService.shared.db
    private var sessionListeners: [String: ListenerRegistration] = [:]
    private var answerListeners: [String: ListenerRegistration] = [:]
    private var iceCandidateListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - セッション管理
    
    /// セッションを作成（モニター側: SDP Offer書き込み）
    func createSession(
        cameraId: String,
        sessionId: String,
        monitorUserId: String,
        monitorDeviceId: String,
        monitorDeviceName: String,
        pairingCode: String,
        offer: [String: Any],
        displayName: String? = nil
    ) async throws -> String {
        let sessionRef = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
        
        var sessionData: [String: Any] = [
            "monitorUserId": monitorUserId,
            "monitorDeviceId": monitorDeviceId,
            "monitorDeviceName": monitorDeviceName,
            "pairingCode": pairingCode,
            "offer": offer,
            "status": SessionModel.SessionStatus.waiting.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // displayNameが提供されている場合は追加
        if let displayName = displayName, !displayName.isEmpty {
            sessionData["displayName"] = displayName
        }
        
        try await sessionRef.setData(sessionData)
        return sessionId
    }
    
    /// セッションのSDP Answerを書き込み（カメラ側）
    func setAnswer(cameraId: String, sessionId: String, answer: [String: Any]) async throws {
        try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .updateData([
                "answer": answer,
                "status": SessionModel.SessionStatus.connected.rawValue
            ])
    }
    
    /// セッションステータスを更新
    func updateSessionStatus(cameraId: String, sessionId: String, status: SessionModel.SessionStatus) async throws {
        try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .updateData([
                "status": status.rawValue
            ])
    }
    
    /// セッションの音声設定を更新（カメラ側）
    func updateAudioEnabled(cameraId: String, sessionId: String, enabled: Bool) async throws {
        try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .updateData([
                "isAudioEnabled": enabled
            ])
    }
    
    /// セッションを削除
    func deleteSession(cameraId: String, sessionId: String) async throws {
        try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .delete()
    }
    
    /// 同じmonitorUserIdの既存セッションを削除（現在のセッションIDを除く）
    func deleteExistingSessionsForUser(cameraId: String, monitorUserId: String, excludeSessionId: String) async throws {
        let snapshot = try await db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("monitorUserId", isEqualTo: monitorUserId)
            .getDocuments()
        
        let sessionsToDelete = snapshot.documents.filter { doc in
            doc.documentID != excludeSessionId
        }
        
        if !sessionsToDelete.isEmpty {
            let batch = db.batch()
            for doc in sessionsToDelete {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            
            #if DEBUG
            print("SignalingService: 同じユーザーの既存セッション \(sessionsToDelete.count)件を削除しました")
            #endif
        }
    }
    
    // MARK: - セッション監視
    
    /// 既存のwaitingセッションを取得（カメラ側: 監視開始前に作成されたセッションに対応）
    func getWaitingSessions(cameraId: String) async throws -> [SessionModel] {
        let snapshot = try await db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.waiting.rawValue)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> SessionModel? in
            let data = doc.data()
            return SessionModel(from: data, documentId: doc.documentID)
        }
    }
    
    /// 接続済みセッションを取得（カメラ側: 起動時のクリーンアップ用）
    func getConnectedSessions(cameraId: String) async throws -> [SessionModel] {
        let snapshot = try await db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.connected.rawValue)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> SessionModel? in
            let data = doc.data()
            return SessionModel(from: data, documentId: doc.documentID)
        }
    }
    
    /// すべての接続済みセッションを削除（カメラ側: 起動時のクリーンアップ用）
    func cleanupAllConnectedSessions(cameraId: String) async throws {
        let sessions = try await getConnectedSessions(cameraId: cameraId)
        
        // バッチ削除
        let batch = db.batch()
        for session in sessions {
            guard let sessionId = session.id else { continue }
            let sessionRef = db.collection("cameras").document(cameraId)
                .collection("sessions").document(sessionId)
            batch.deleteDocument(sessionRef)
        }
        
        if !sessions.isEmpty {
            try await batch.commit()
        }
    }
    
    /// すべてのwaitingセッションを削除（カメラ側: 起動時のクリーンアップ用）
    func cleanupAllWaitingSessions(cameraId: String) async throws {
        let sessions = try await getWaitingSessions(cameraId: cameraId)
        
        // バッチ削除
        let batch = db.batch()
        for session in sessions {
            guard let sessionId = session.id else { continue }
            let sessionRef = db.collection("cameras").document(cameraId)
                .collection("sessions").document(sessionId)
            batch.deleteDocument(sessionRef)
        }
        
        if !sessions.isEmpty {
            try await batch.commit()
        }
    }
    
    /// 接続済みセッションを監視（カメラ側: 切断検知用）
    func observeConnectedSessions(cameraId: String, completion: @escaping (Result<[SessionModel], Error>) -> Void) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.connected.rawValue)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }
                
                let sessions = snapshot.documents.compactMap { doc -> SessionModel? in
                    let data = doc.data()
                    return SessionModel(from: data, documentId: doc.documentID)
                }
                completion(.success(sessions))
            }
        
        let key = "\(cameraId)_connected"
        sessionListeners[key] = listener
        return listener
    }
    
    /// カメラの新規セッションを監視（カメラ側）
    func observeNewSessions(cameraId: String, completion: @escaping (Result<[SessionModel], Error>) -> Void) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.waiting.rawValue)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }
                
                let sessions = snapshot.documents.compactMap { doc -> SessionModel? in
                    // doc.data()から直接SessionModelを初期化して、offerを含める
                    let data = doc.data()
                    return SessionModel(from: data, documentId: doc.documentID)
                }
                completion(.success(sessions))
            }
        
        sessionListeners[cameraId] = listener
        return listener
    }
    
    /// セッションのAnswerを取得（モニター側: 既存のAnswerを確認するため）
    func getAnswer(cameraId: String, sessionId: String) async throws -> [String: Any]? {
        let doc = try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .getDocument()
        
        guard let data = doc.data(),
              let answer = data["answer"] as? [String: Any] else {
            return nil
        }
        
        return answer
    }
    
    /// セッションのAnswerを監視（モニター側）
    func observeAnswer(cameraId: String, sessionId: String, completion: @escaping (Result<[String: Any]?, Error>) -> Void) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot,
                      let data = snapshot.data(),
                      let answer = data["answer"] as? [String: Any] else {
                    completion(.success(nil))
                    return
                }
                
                completion(.success(answer))
            }
        
        let key = "\(cameraId)_\(sessionId)_answer"
        answerListeners[key] = listener
        return listener
    }
    
    /// セッション全体を監視（モニター側: 音声設定変更を検知するため）
    func observeSession(cameraId: String, sessionId: String, completion: @escaping (Result<[String: Any]?, Error>) -> Void) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot,
                      let data = snapshot.data() else {
                    completion(.success(nil))
                    return
                }
                
                completion(.success(data))
            }
        
        let key = "\(cameraId)_\(sessionId)_session"
        sessionListeners[key] = listener
        return listener
    }
    
    // MARK: - ICE Candidates
    
    /// ICE Candidateを追加
    func addICECandidate(
        cameraId: String,
        sessionId: String,
        candidate: String,
        sdpMid: String?,
        sdpMLineIndex: Int32?,
        sender: ICECandidateModel.ICECandidateSender
    ) async throws {
        let candidateRef = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .collection("iceCandidates").document()
        
        var candidateData: [String: Any] = [
            "candidate": candidate,
            "sender": sender.rawValue
        ]
        
        if let sdpMid = sdpMid {
            candidateData["sdpMid"] = sdpMid
        }
        
        if let sdpMLineIndex = sdpMLineIndex {
            candidateData["sdpMLineIndex"] = sdpMLineIndex
        }
        
        try await candidateRef.setData(candidateData)
    }
    
    /// ICE Candidatesを監視（新規追加分のみコールバック）
    func observeICECandidates(
        cameraId: String,
        sessionId: String,
        completion: @escaping (Result<[ICECandidateModel], Error>) -> Void
    ) -> ListenerRegistration {
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .collection("iceCandidates")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }
                
                // documentChangesの.addedのみを処理し、既存候補の再処理を防止
                let newCandidates = snapshot.documentChanges
                    .filter { $0.type == .added }
                    .compactMap { change -> ICECandidateModel? in
                        try? change.document.data(as: ICECandidateModel.self)
                    }
                
                if !newCandidates.isEmpty {
                    completion(.success(newCandidates))
                }
            }
        
        let key = "\(cameraId)_\(sessionId)_ice"
        iceCandidateListeners[key] = listener
        return listener
    }
    
    // MARK: - クリーンアップ
    
    /// セッション監視を停止
    func stopObservingSession(cameraId: String) {
        sessionListeners[cameraId]?.remove()
        sessionListeners.removeValue(forKey: cameraId)
    }
    
    /// ICE Candidate監視を停止
    func stopObservingICECandidates(cameraId: String, sessionId: String) {
        let key = "\(cameraId)_\(sessionId)_ice"
        iceCandidateListeners[key]?.remove()
        iceCandidateListeners.removeValue(forKey: key)
    }
    
    /// 全ての監視を停止
    func stopAllObservers() {
        sessionListeners.values.forEach { $0.remove() }
        answerListeners.values.forEach { $0.remove() }
        iceCandidateListeners.values.forEach { $0.remove() }
        sessionListeners.removeAll()
        answerListeners.removeAll()
        iceCandidateListeners.removeAll()
    }
}
