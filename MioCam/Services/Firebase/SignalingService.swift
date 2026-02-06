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
    
    // MARK: - セッション監視
    
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
                    guard let data = doc.data() as? [String: Any] else {
                        return nil
                    }
                    return SessionModel(from: data, documentId: doc.documentID)
                }
                completion(.success(sessions))
            }
        
        sessionListeners[cameraId] = listener
        return listener
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
