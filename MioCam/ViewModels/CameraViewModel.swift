//
//  CameraViewModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import UIKit
import Combine
import FirebaseFirestore
import WebRTC

/// 接続中のモニター情報
struct ConnectedMonitorInfo: Identifiable {
    let id: String           // sessionId
    let monitorUserId: String
    let displayName: String  // Apple IDのユーザー名
    let deviceName: String   // デバイス名
    var isAudioEnabled: Bool = false  // デフォルトOFF
}

/// カメラ側の状態を管理するViewModel
@MainActor
class CameraViewModel: ObservableObject {
    @Published var cameraId: String? {
        didSet {
            nonisolatedCameraId = cameraId
        }
    }
    @Published var pairingCode: String?
    @Published var deviceName: String = ""
    @Published var isOnline: Bool = false
    @Published var batteryLevel: Int?
    @Published var connectedMonitorCount: Int = 0
    @Published var connectedMonitors: [ConnectedMonitorInfo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    /// 音声を許可済みのユーザーID（セッション中のみ保持）
    private var audioAllowedUserIds: Set<String> = []
    
    nonisolated(unsafe) private var nonisolatedCameraId: String?
    
    /// 処理済みセッションIDを追跡（重複処理防止）
    private var processedSessionIds: Set<String> = []
    
    private let cameraService = CameraFirestoreService.shared
    private let signalingService = SignalingService.shared
    private let webRTCService = WebRTCService.shared
    private let backgroundAudioService = BackgroundAudioService.shared
    
    private var cameraListener: ListenerRegistration?
    private var sessionListener: ListenerRegistration?
    private var batteryObserver: NSObjectProtocol?
    
    init() {
        deviceName = UIDevice.current.name
        setupBatteryMonitoring()
        // #region agent log
        print("[MioCam-Debug][H1] CameraViewModel.init - WebRTCService.delegate is currently: \(String(describing: webRTCService.delegate))")
        // #endregion
    }
    
    // MARK: - Camera Registration
    
    /// カメラを登録（既存カメラがあれば復元、なければ新規作成）
    func registerCamera(ownerUserId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let deviceModel = UIDevice.current.model
            let osVersion = UIDevice.current.systemVersion
            
            var id: String
            var isNewCamera = false
            
            // 既存のカメラを確認
            if let existingCamera = try await cameraService.getExistingCamera(ownerUserId: ownerUserId) {
                // 既存カメラを復元
                id = existingCamera.id ?? ""
                guard !id.isEmpty else {
                    throw NSError(domain: "CameraViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "カメラIDが無効です"])
                }
                
                // オンライン状態に復元
                try await cameraService.restoreExistingCamera(
                    cameraId: id,
                    ownerUserId: ownerUserId,
                    deviceName: deviceName
                )
            } else {
                // 新規カメラを作成
                id = try await cameraService.registerCamera(
                    ownerUserId: ownerUserId,
                    deviceName: deviceName,
                    deviceModel: deviceModel,
                    osVersion: osVersion
                )
                isNewCamera = true
            }
            
            cameraId = id
            
            // カメラ情報を取得
            if let camera = try await cameraService.getCamera(cameraId: id) {
                pairingCode = camera.pairingCode
                // deviceNameも設定
                if !camera.deviceName.isEmpty {
                    deviceName = camera.deviceName
                }
            }
            
            // カメラの状態監視を開始
            startObservingCamera(cameraId: id)
            
            // 新規セッション（モニター接続）の監視を開始
            startObservingSessions(cameraId: id)
            
            // WebRTCのローカルビデオトラックをセットアップ
            webRTCService.setupLocalVideoTrack(captureService: CameraCaptureService.shared)
            
            // WebRTCのローカルオーディオトラックをセットアップ
            webRTCService.setupLocalAudioTrack()
            
            // WebRTCデリゲートを設定（Answer/ICE Candidate送信に必須）
            webRTCService.delegate = self
            
            // #region agent log
            print("[MioCam-Debug][H1] registerCamera - AFTER delegate set: webRTCService.delegate = \(String(describing: webRTCService.delegate))")
            // #endregion
            
            // バックグラウンドオーディオを開始
            backgroundAudioService.startForCameraMode()
            
            // プッシュ通知トークンを保存
            if let cameraId = cameraId {
                try? await PushNotificationService.shared.saveTokenToCamera(cameraId: cameraId)
            }
            
            // オンライン状態を更新
            await updateStatus(isOnline: true, batteryLevel: currentBatteryLevel())
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Camera Observation
    
    /// カメラの状態を監視開始
    private func startObservingCamera(cameraId: String) {
        cameraListener = cameraService.observeCamera(cameraId: cameraId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let camera):
                    if let camera = camera {
                        // #region agent log
                        DebugLog.write([
                            "location": "CameraViewModel.swift:159",
                            "message": "startObservingCamera - camera received",
                            "data": [
                                "cameraDeviceName": camera.deviceName,
                                "currentDeviceName": self?.deviceName ?? "nil",
                                "cameraId": camera.id ?? "nil"
                            ],
                            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "K"
                        ])
                        // #endregion
                        self?.pairingCode = camera.pairingCode
                        self?.isOnline = camera.isOnline
                        self?.batteryLevel = camera.batteryLevel
                        self?.connectedMonitorCount = camera.connectedMonitorCount
                        // deviceNameも更新
                        if !camera.deviceName.isEmpty {
                            let beforeDeviceName = self?.deviceName ?? "nil"
                            self?.deviceName = camera.deviceName
                            // #region agent log
                            DebugLog.write([
                                "location": "CameraViewModel.swift:167",
                                "message": "startObservingCamera - deviceName updated from Firestore",
                                "data": [
                                    "beforeDeviceName": beforeDeviceName,
                                    "afterDeviceName": camera.deviceName,
                                    "cameraId": camera.id ?? "nil"
                                ],
                                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                                "sessionId": "debug-session",
                                "runId": "run1",
                                "hypothesisId": "L"
                            ])
                            // #endregion
                        }
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 新規セッション（モニター接続）を監視
    private func startObservingSessions(cameraId: String) {
        sessionListener = signalingService.observeNewSessions(cameraId: cameraId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let sessions):
                    for session in sessions {
                        await self?.handleNewSession(session, cameraId: cameraId)
                    }
                case .failure(let error):
                    print("セッション監視エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 新しいセッション（モニター接続要求）を処理
    private func handleNewSession(_ session: SessionModel, cameraId: String) async {
        // #region agent log
        print("[MioCam-Debug][H3] handleNewSession - session.id=\(String(describing: session.id)), hasOffer=\(session.offer != nil), status=\(session.status.rawValue)")
        // #endregion
        guard let sessionId = session.id,
              let offerDict = session.offer,
              let offer = RTCSessionDescription.from(dict: offerDict) else {
            // #region agent log
            print("[MioCam-Debug][H3] handleNewSession - GUARD FAILED: id=\(String(describing: session.id)), offer=\(String(describing: session.offer))")
            // #endregion
            return
        }
        
        // 重複処理を防止
        guard !processedSessionIds.contains(sessionId) else {
            // #region agent log
            print("[MioCam-Debug][H5] handleNewSession - SKIPPING already processed sessionId=\(sessionId)")
            // #endregion
            return
        }
        processedSessionIds.insert(sessionId)
        
        do {
            // #region agent log
            print("[MioCam-Debug][H1] handleNewSession - delegate BEFORE handleIncomingSession: \(String(describing: webRTCService.delegate))")
            // #endregion
            
            // ユーザー情報を取得（表示名用）
            var displayName = session.monitorDeviceName  // デフォルトはデバイス名
            do {
                let userDoc = try await FirestoreService.shared.db.collection("users").document(session.monitorUserId).getDocument()
                if let userData = userDoc.data(),
                   let name = userData["displayName"] as? String {
                    displayName = name
                }
            } catch {
                print("ユーザー情報取得エラー: \(error.localizedDescription)")
            }
            
            // WebRTCでOfferを処理してAnswerを生成
            try await webRTCService.handleIncomingSession(sessionId: sessionId, offer: offer, monitorUserId: session.monitorUserId)
            
            // 接続モニター情報を追加
            let isAudioAllowed = audioAllowedUserIds.contains(session.monitorUserId)
            let monitorInfo = ConnectedMonitorInfo(
                id: sessionId,
                monitorUserId: session.monitorUserId,
                displayName: displayName,
                deviceName: session.monitorDeviceName,
                isAudioEnabled: isAudioAllowed
            )
            connectedMonitors.append(monitorInfo)
            
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:234",
                "message": "handleNewSession - monitorInfo created",
                "data": [
                    "sessionId": sessionId,
                    "monitorUserId": session.monitorUserId,
                    "isAudioEnabled": isAudioAllowed,
                    "audioAllowedUserIds": Array(audioAllowedUserIds)
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "E"
            ])
            // #endregion
            
            // デフォルトで音声はOFF（明示的にOFFにする）
            webRTCService.setAudioEnabled(sessionId: sessionId, enabled: false)
            
            // 既に許可済みのユーザーの場合は即座に音声を有効化
            if isAudioAllowed {
                webRTCService.setAudioEnabled(sessionId: sessionId, enabled: true)
            }
            
            // #region agent log
            print("[MioCam-Debug][H1][H5] handleNewSession - Answer generated locally. Incrementing connectedMonitorCount from \(connectedMonitorCount) to \(connectedMonitorCount + 1). delegate=\(String(describing: webRTCService.delegate))")
            // #endregion
            
            // 接続モニター数を更新
            try await cameraService.updateConnectedMonitorCount(cameraId: cameraId, count: connectedMonitorCount + 1)
            
        } catch {
            print("セッション処理エラー: \(error.localizedDescription)")
            // #region agent log
            print("[MioCam-Debug][H1] handleNewSession - ERROR: \(error)")
            // #endregion
            // エラーの場合は再処理できるようにする
            processedSessionIds.remove(sessionId)
        }
    }
    
    // MARK: - Status Updates
    
    /// カメラの状態を更新
    func updateStatus(isOnline: Bool, batteryLevel: Int?) async {
        guard let cameraId = cameraId else { return }
        
        do {
            try await cameraService.updateCameraStatus(
                cameraId: cameraId,
                isOnline: isOnline,
                batteryLevel: batteryLevel
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// ペアリングコードを再生成（未接続状態でも可能）
    func regeneratePairingCode() async {
        guard let cameraId = cameraId else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 接続中のセッションがある場合は終了
            if !connectedMonitors.isEmpty {
                webRTCService.closeAllSessions()
                connectedMonitors.removeAll()
                connectedMonitorCount = 0
            }
            
            // 新しいペアリングコードを生成
            let newCode = try await cameraService.regeneratePairingCode(cameraId: cameraId)
            pairingCode = newCode
            
            // 処理済みセッションをリセット
            processedSessionIds.removeAll()
            
            // 接続モニター数をリセット
            try await cameraService.updateConnectedMonitorCount(cameraId: cameraId, count: 0)
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// カメラのデバイス名を更新（未接続状態でも可能）
    func updateDeviceName(_ newName: String) async {
        // #region agent log
        DebugLog.write([
            "location": "CameraViewModel.swift:339",
            "message": "updateDeviceName - ENTRY",
            "data": [
                "newName": newName,
                "currentDeviceName": deviceName,
                "cameraId": cameraId ?? "nil"
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "C"
        ])
        // #endregion
        guard let cameraId = cameraId else {
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:340",
                "message": "updateDeviceName - cameraId is nil",
                "data": [
                    "newName": newName
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "D"
            ])
            // #endregion
            return
        }
        guard !newName.isEmpty else {
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:341",
                "message": "updateDeviceName - newName is empty",
                "data": [
                    "cameraId": cameraId
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "E"
            ])
            // #endregion
            return
        }
        
        let beforeDeviceName = deviceName
        deviceName = newName
        
        // #region agent log
        DebugLog.write([
            "location": "CameraViewModel.swift:343",
            "message": "updateDeviceName - deviceName updated locally",
            "data": [
                "beforeDeviceName": beforeDeviceName,
                "afterDeviceName": deviceName,
                "cameraId": cameraId
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F"
        ])
        // #endregion
        
        do {
            // Firestoreのカメラドキュメントを更新
            try await cameraService.updateDeviceName(cameraId: cameraId, deviceName: newName)
            
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:347",
                "message": "updateDeviceName - Firestore updated",
                "data": [
                    "cameraId": cameraId,
                    "deviceName": newName
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "G"
            ])
            // #endregion
            
            // すべてのモニターリンクのcameraDeviceNameも更新
            try await MonitorLinkService.shared.updateCameraDeviceName(cameraId: cameraId, deviceName: newName)
            
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:350",
                "message": "updateDeviceName - MonitorLinkService updated",
                "data": [
                    "cameraId": cameraId,
                    "deviceName": newName
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "H"
            ])
            // #endregion
        } catch {
            // #region agent log
            DebugLog.write([
                "location": "CameraViewModel.swift:352",
                "message": "updateDeviceName - ERROR",
                "data": [
                    "error": error.localizedDescription,
                    "cameraId": cameraId,
                    "deviceName": newName
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "I"
            ])
            // #endregion
            errorMessage = "カメラ名の更新に失敗しました: \(error.localizedDescription)"
        }
        
        // #region agent log
        DebugLog.write([
            "location": "CameraViewModel.swift:356",
            "message": "updateDeviceName - EXIT",
            "data": [
                "finalDeviceName": deviceName,
                "cameraId": cameraId
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "J"
        ])
        // #endregion
    }
    
    // MARK: - Battery Monitoring
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                await self.updateStatus(isOnline: true, batteryLevel: self.currentBatteryLevel())
            }
        }
    }
    
    private func currentBatteryLevel() -> Int {
        let level = UIDevice.current.batteryLevel
        if level < 0 {
            return 100 // シミュレーターなど、バッテリー情報が取得できない場合
        }
        return Int(level * 100)
    }
    
    // MARK: - Cleanup
    
    func stopCamera() {
        // WebRTC接続を終了
        webRTCService.closeAllSessions()
        
        // バックグラウンドオーディオを停止
        backgroundAudioService.stopForCameraMode()
        
        // オフライン状態に更新
        Task {
            await updateStatus(isOnline: false, batteryLevel: nil)
        }
    }
    
    deinit {
        cameraListener?.remove()
        sessionListener?.remove()
        
        if let observer = batteryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        if let cameraId = nonisolatedCameraId {
            cameraService.stopObservingCamera(cameraId: cameraId)
        }
        signalingService.stopAllObservers()
    }
}

// MARK: - WebRTCServiceDelegate

extension CameraViewModel: WebRTCServiceDelegate {
    nonisolated func webRTCService(_ service: WebRTCService, didChangeState state: WebRTCConnectionState, for sessionId: String) {
        Task { @MainActor in
            switch state {
            case .disconnected, .failed, .closed:
                // 接続が切断された場合、モニター数を減らす
                guard let cameraId = cameraId else { return }
                
                // connectedMonitorsからセッションを削除
                connectedMonitors.removeAll { $0.id == sessionId }
                
                let newCount = max(0, connectedMonitorCount - 1)
                try? await cameraService.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
            default:
                break
            }
        }
    }
    
    nonisolated func webRTCService(_ service: WebRTCService, didReceiveRemoteVideoTrack track: RTCVideoTrack, for sessionId: String) {
        // カメラ側では使用しない
    }
    
    nonisolated func webRTCService(_ service: WebRTCService, didGenerateICECandidate candidate: RTCIceCandidate, for sessionId: String) {
        Task { @MainActor in
            guard let cameraId = cameraId else { return }
            
            do {
                try await signalingService.addICECandidate(
                    cameraId: cameraId,
                    sessionId: sessionId,
                    candidate: candidate.sdp,
                    sdpMid: candidate.sdpMid,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sender: .camera
                )
            } catch {
                print("ICE Candidate送信エラー: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated func webRTCService(_ service: WebRTCService, didGenerateAnswer sdp: RTCSessionDescription, for sessionId: String) {
        // #region agent log
        print("[MioCam-Debug][H1] CameraViewModel.didGenerateAnswer CALLED - sessionId=\(sessionId)")
        // #endregion
        Task { @MainActor in
            guard let cameraId = cameraId else {
                // #region agent log
                print("[MioCam-Debug][H1] didGenerateAnswer - cameraId is nil!")
                // #endregion
                return
            }
            
            do {
                // #region agent log
                print("[MioCam-Debug][H1] didGenerateAnswer - Writing answer to Firestore for cameraId=\(cameraId), sessionId=\(sessionId)")
                // #endregion
                try await signalingService.setAnswer(
                    cameraId: cameraId,
                    sessionId: sessionId,
                    answer: sdp.toDict()
                )
                // #region agent log
                print("[MioCam-Debug][H1] didGenerateAnswer - Answer successfully written to Firestore")
                // #endregion
            } catch {
                print("Answer送信エラー: \(error.localizedDescription)")
                // #region agent log
                print("[MioCam-Debug][H1] didGenerateAnswer - FIRESTORE ERROR: \(error)")
                // #endregion
            }
        }
    }
    
    nonisolated func webRTCService(_ service: WebRTCService, didGenerateOffer sdp: RTCSessionDescription, for sessionId: String) {
        // カメラ側では使用しない（モニター側のみ）
    }
    
    nonisolated func webRTCService(_ service: WebRTCService, didReceiveRemoteAudioTrack track: RTCAudioTrack, for sessionId: String) {
        // カメラ側では使用しない（モニター側のみ）
    }
    
    // MARK: - Audio Control
    
    /// 特定ユーザーの音声を許可/不許可にする
    func toggleAudioForUser(userId: String, enabled: Bool) {
        // #region agent log
        DebugLog.write([
            "location": "CameraViewModel.swift:448",
            "message": "toggleAudioForUser - BEFORE",
            "data": [
                "userId": userId,
                "enabled": enabled,
                "audioAllowedUserIds": Array(audioAllowedUserIds),
                "connectedMonitors": connectedMonitors.map { ["id": $0.id, "monitorUserId": $0.monitorUserId, "isAudioEnabled": $0.isAudioEnabled] }
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F"
        ])
        // #endregion
        
        // audioAllowedUserIdsを更新
        if enabled {
            audioAllowedUserIds.insert(userId)
        } else {
            audioAllowedUserIds.remove(userId)
        }
        
        // 該当ユーザーの全セッションに対して音声を制御
        webRTCService.setAudioEnabledForUser(userId: userId, enabled: enabled)
        
        // Firestoreのセッションドキュメントも更新（モニター側に通知）
        guard let cameraId = cameraId else { return }
        Task {
            for monitor in connectedMonitors where monitor.monitorUserId == userId {
                do {
                    try await signalingService.updateAudioEnabled(
                        cameraId: cameraId,
                        sessionId: monitor.id,
                        enabled: enabled
                    )
                } catch {
                    print("音声設定の更新に失敗しました: \(error.localizedDescription)")
                }
            }
        }
        
        // connectedMonitorsの該当ユーザーのisAudioEnabledを更新
        for index in connectedMonitors.indices {
            if connectedMonitors[index].monitorUserId == userId {
                connectedMonitors[index].isAudioEnabled = enabled
            }
        }
        
        // #region agent log
        DebugLog.write([
            "location": "CameraViewModel.swift:465",
            "message": "toggleAudioForUser - AFTER",
            "data": [
                "userId": userId,
                "enabled": enabled,
                "audioAllowedUserIds": Array(audioAllowedUserIds),
                "connectedMonitors": connectedMonitors.map { ["id": $0.id, "monitorUserId": $0.monitorUserId, "isAudioEnabled": $0.isAudioEnabled] }
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "F"
        ])
        // #endregion
    }
}
