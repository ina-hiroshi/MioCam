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
        offer: [String: Any]
    ) async throws -> String {
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "SignalingService.swift:24", "message": "createSession開始", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        let sessionRef = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
        
        let sessionData: [String: Any] = [
            "monitorUserId": monitorUserId,
            "monitorDeviceId": monitorDeviceId,
            "monitorDeviceName": monitorDeviceName,
            "pairingCode": pairingCode,
            "offer": offer,
            "status": SessionModel.SessionStatus.waiting.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "SignalingService.swift:46", "message": "Firestore書き込み前", "data": ["cameraId": cameraId, "sessionId": sessionId, "status": SessionModel.SessionStatus.waiting.rawValue], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        try await sessionRef.setData(sessionData)
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "F", "location": "SignalingService.swift:46", "message": "Firestore書き込み後", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        return sessionId
    }
    
    /// セッションのSDP Answerを書き込み（カメラ側）
    func setAnswer(cameraId: String, sessionId: String, answer: [String: Any]) async throws {
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "SignalingService.swift:51", "message": "setAnswer開始", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "SignalingService.swift:52", "message": "Firestore更新前", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        try await db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .updateData([
                "answer": answer,
                "status": SessionModel.SessionStatus.connected.rawValue
            ])
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "SignalingService.swift:57", "message": "Firestore更新後", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
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
    
    /// 接続済みセッションを監視（カメラ側: 切断検知用）
    func observeConnectedSessions(cameraId: String, completion: @escaping (Result<[SessionModel], Error>) -> Void) -> ListenerRegistration {
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "SignalingService.swift:113", "message": "observeConnectedSessions設定", "data": ["cameraId": cameraId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.connected.rawValue)
            .addSnapshotListener { snapshot, error in
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "SignalingService.swift:118", "message": "接続済みセッション監視コールバック", "data": ["cameraId": cameraId, "hasError": error != nil, "hasSnapshot": snapshot != nil, "docCount": snapshot?.documents.count ?? 0], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
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
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "SignalingService.swift:88", "message": "observeNewSessions設定", "data": ["cameraId": cameraId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions")
            .whereField("status", isEqualTo: SessionModel.SessionStatus.waiting.rawValue)
            .addSnapshotListener { snapshot, error in
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "SignalingService.swift:92", "message": "セッション監視コールバック", "data": ["cameraId": cameraId, "hasError": error != nil, "hasSnapshot": snapshot != nil, "docCount": snapshot?.documents.count ?? 0], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
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
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "G", "location": "SignalingService.swift:116", "message": "observeAnswer設定", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        let listener = db.collection("cameras").document(cameraId)
            .collection("sessions").document(sessionId)
            .addSnapshotListener { snapshot, error in
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "G", "location": "SignalingService.swift:119", "message": "Answer監視コールバック", "data": ["cameraId": cameraId, "sessionId": sessionId, "hasError": error != nil, "hasSnapshot": snapshot != nil, "hasAnswer": (snapshot?.data()?["answer"] as? [String: Any]) != nil], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
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
        
        let key = "\(cameraId)_\(sessionId)"
        iceCandidateListeners[key] = listener
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
        iceCandidateListeners[key] = listener
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
    
    /// ICE Candidatesを監視
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
                
                let candidates = snapshot.documents.compactMap { doc -> ICECandidateModel? in
                    try? doc.data(as: ICECandidateModel.self)
                }
                completion(.success(candidates))
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
        iceCandidateListeners.values.forEach { $0.remove() }
        sessionListeners.removeAll()
        iceCandidateListeners.removeAll()
    }
}
