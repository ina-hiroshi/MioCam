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
    private var connectedSessionListener: ListenerRegistration?
    private var batteryObserver: NSObjectProtocol?
    
    init() {
        deviceName = UIDevice.current.name
        setupBatteryMonitoring()
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
            
            // 接続済みセッションの監視を開始（切断検知用）
            startObservingConnectedSessions(cameraId: id)
            
            // WebRTCのローカルビデオトラックをセットアップ
            webRTCService.setupLocalVideoTrack(captureService: CameraCaptureService.shared)
            
            // WebRTCのローカルオーディオトラックをセットアップ
            webRTCService.setupLocalAudioTrack()
            
            // WebRTCデリゲートを設定（Answer/ICE Candidate送信に必須）
            webRTCService.delegate = self
            
            // バックグラウンドオーディオを開始
            backgroundAudioService.startForCameraMode()
            
            // プッシュ通知トークンを保存
            if let cameraId = cameraId {
                try? await PushNotificationService.shared.saveTokenToCamera(cameraId: cameraId)
            }
            
            // オンライン状態を更新
            await updateStatus(isOnline: true, batteryLevel: currentBatteryLevel())
            
            // 初期品質を設定（1台想定で1080p/30fps）
            adjustQualityBasedOnMonitorCount()
            
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
                        self?.pairingCode = camera.pairingCode
                        self?.isOnline = camera.isOnline
                        self?.batteryLevel = camera.batteryLevel
                        // connectedMonitorCountは、ローカルのconnectedMonitorsと同期を保つため、
                        // Firestoreの値で上書きしない（切断時の即座の更新を優先）
                        // self?.connectedMonitorCount = camera.connectedMonitorCount
                        // deviceNameも更新
                        if !camera.deviceName.isEmpty {
                            self?.deviceName = camera.deviceName
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
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "CameraViewModel.swift:174", "message": "セッション監視開始", "data": ["cameraId": cameraId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        
        // 既存のwaitingセッションを即座に処理（監視開始前に作成されたセッションに対応）
        Task { @MainActor in
            do {
                let existingSessions = try await signalingService.getWaitingSessions(cameraId: cameraId)
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "CameraViewModel.swift:180", "message": "既存セッション取得", "data": ["cameraId": cameraId, "sessionCount": existingSessions.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                for session in existingSessions {
                    await handleNewSession(session, cameraId: cameraId)
                }
            } catch {
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "CameraViewModel.swift:186", "message": "既存セッション取得エラー", "data": ["error": error.localizedDescription], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                print("既存セッション取得エラー: \(error.localizedDescription)")
            }
        }
        
        sessionListener = signalingService.observeNewSessions(cameraId: cameraId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let sessions):
                    // #region agent log
                    DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "CameraViewModel.swift:195", "message": "新規セッション検知", "data": ["cameraId": cameraId, "sessionCount": sessions.count], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                    // #endregion
                    for session in sessions {
                        await self?.handleNewSession(session, cameraId: cameraId)
                    }
                case .failure(let error):
                    // #region agent log
                    DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "H", "location": "CameraViewModel.swift:202", "message": "セッション監視エラー", "data": ["error": error.localizedDescription], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                    // #endregion
                    print("セッション監視エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 新しいセッション（モニター接続要求）を処理
    private func handleNewSession(_ session: SessionModel, cameraId: String) async {
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "I", "location": "CameraViewModel.swift:190", "message": "handleNewSession開始", "data": ["sessionId": session.id ?? "nil", "hasOffer": session.offer != nil], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        guard let sessionId = session.id,
              let offerDict = session.offer,
              let offer = RTCSessionDescription.from(dict: offerDict) else {
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "I", "location": "CameraViewModel.swift:193", "message": "セッションデータ不正", "data": ["sessionId": session.id ?? "nil", "hasOffer": session.offer != nil], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
            return
        }
        
        // 重複処理を防止
        guard !processedSessionIds.contains(sessionId) else {
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "I", "location": "CameraViewModel.swift:198", "message": "重複セッション", "data": ["sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
            return
        }
        processedSessionIds.insert(sessionId)
        
        do {
            
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
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "J", "location": "CameraViewModel.swift:218", "message": "handleIncomingSession呼び出し前", "data": ["sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
            try await webRTCService.handleIncomingSession(sessionId: sessionId, offer: offer, monitorUserId: session.monitorUserId)
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "J", "location": "CameraViewModel.swift:218", "message": "handleIncomingSession呼び出し後", "data": ["sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
            
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
            
            // デフォルトで音声はOFF（明示的にOFFにする）
            webRTCService.setAudioEnabled(sessionId: sessionId, enabled: false)
            
            // 既に許可済みのユーザーの場合は即座に音声を有効化（再接続対応）
            if isAudioAllowed {
                webRTCService.setAudioEnabled(sessionId: sessionId, enabled: true)
                
                // Firestoreのセッションドキュメントも更新（モニター側に音声ONを通知）
                try await signalingService.updateAudioEnabled(
                    cameraId: cameraId,
                    sessionId: sessionId,
                    enabled: true
                )
            }
            
            // 接続モニター数を更新（connectedMonitors.countを使用して同期を保つ）
            let newCount = connectedMonitors.count
            connectedMonitorCount = newCount
            try await cameraService.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
            
            // モニター数に応じて品質を自動調整
            adjustQualityBasedOnMonitorCount()
            
        } catch {
            print("セッション処理エラー: \(error.localizedDescription)")
            // エラーの場合は再処理できるようにする
            processedSessionIds.remove(sessionId)
        }
    }
    
    /// 接続済みセッションの監視（切断検知用）
    private func startObservingConnectedSessions(cameraId: String) {
        // #region agent log
        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "CameraViewModel.swift:215", "message": "接続済みセッション監視開始", "data": ["cameraId": cameraId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
        // #endregion
        connectedSessionListener = signalingService.observeConnectedSessions(cameraId: cameraId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let sessions):
                    // #region agent log
                    DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "CameraViewModel.swift:220", "message": "接続済みセッション変更検知", "data": ["cameraId": cameraId, "sessionCount": sessions.count, "currentMonitors": self?.connectedMonitors.count ?? 0], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                    // #endregion
                    // 現在のconnectedMonitorsと比較して、削除されたセッションを検知
                    let currentSessionIds = Set(self?.connectedMonitors.map { $0.id } ?? [])
                    let firestoreSessionIds = Set(sessions.map { $0.id ?? "" }.filter { !$0.isEmpty })
                    
                    // 削除されたセッション（Firestoreに存在しないが、connectedMonitorsに存在する）
                    let removedSessionIds = currentSessionIds.subtracting(firestoreSessionIds)
                    
                    if !removedSessionIds.isEmpty {
                        // #region agent log
                        DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "CameraViewModel.swift:230", "message": "セッション削除検知", "data": ["removedSessionIds": Array(removedSessionIds)], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                        // #endregion
                        guard let cameraId = self?.cameraId else { return }
                        
                        // connectedMonitorsから削除されたセッションを削除
                        self?.connectedMonitors.removeAll { removedSessionIds.contains($0.id) }
                        
                        // デバイス数を更新
                        let newCount = self?.connectedMonitors.count ?? 0
                        self?.connectedMonitorCount = newCount
                        
                        // Firestoreへの更新は非同期で実行
                        Task.detached {
                            try? await CameraFirestoreService.shared.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
                        }
                        
                        // processedSessionIdsからも削除
                        for sessionId in removedSessionIds {
                            self?.processedSessionIds.remove(sessionId)
                        }
                        
                        // モニター数に応じて品質を自動調整
                        self?.adjustQualityBasedOnMonitorCount()
                    }
                case .failure(let error):
                    // #region agent log
                    DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "Q", "location": "CameraViewModel.swift:252", "message": "接続済みセッション監視エラー", "data": ["error": error.localizedDescription], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                    // #endregion
                    print("接続済みセッション監視エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Quality Adjustment
    
    /// モニター数に応じて品質を自動調整
    private func adjustQualityBasedOnMonitorCount() {
        let preset: AVCaptureSession.Preset
        let frameRate: Int32 = 30
        
        if connectedMonitorCount <= 2 {
            // 1-2台: 1080p/30fps
            preset = .hd1920x1080
        } else {
            // 3台以上: 720p/30fps
            preset = .hd1280x720
        }
        
        CameraCaptureService.shared.updateQuality(preset: preset, frameRate: frameRate)
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
        guard let cameraId = cameraId else {
            return
        }
        guard !newName.isEmpty else {
            return
        }
        
        deviceName = newName
        
        do {
            // Firestoreのカメラドキュメントを更新
            try await cameraService.updateDeviceName(cameraId: cameraId, deviceName: newName)
            
            // すべてのモニターリンクのcameraDeviceNameも更新
            try await MonitorLinkService.shared.updateCameraDeviceName(cameraId: cameraId, deviceName: newName)
        } catch {
            errorMessage = "カメラ名の更新に失敗しました: \(error.localizedDescription)"
        }
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
        
        // カメラキャプチャを停止
        CameraCaptureService.shared.stopCapture()
        
        // Firestoreリスナーを停止
        cameraListener?.remove()
        cameraListener = nil
        sessionListener?.remove()
        sessionListener = nil
        connectedSessionListener?.remove()
        connectedSessionListener = nil
        
        // 接続モニター情報をクリア
        connectedMonitors.removeAll()
        connectedMonitorCount = 0
        
        // オフライン状態に更新
        Task {
            await updateStatus(isOnline: false, batteryLevel: nil)
        }
    }
    
    deinit {
        cameraListener?.remove()
        sessionListener?.remove()
        connectedSessionListener?.remove()
        
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
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "O", "location": "CameraViewModel.swift:464", "message": "接続切断検知", "data": ["sessionId": sessionId, "state": "\(state)", "currentCount": connectedMonitorCount], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                // 接続が切断された場合、モニター数を減らす
                guard let cameraId = cameraId else { return }
                
                // connectedMonitorsからセッションを削除
                connectedMonitors.removeAll { $0.id == sessionId }
                
                // connectedMonitors.countを使用して同期を保つ
                let newCount = connectedMonitors.count
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "O", "location": "CameraViewModel.swift:476", "message": "デバイス数更新前", "data": ["sessionId": sessionId, "oldCount": connectedMonitorCount, "newCount": newCount], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                connectedMonitorCount = newCount
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "O", "location": "CameraViewModel.swift:477", "message": "デバイス数更新後", "data": ["sessionId": sessionId, "connectedMonitorCount": connectedMonitorCount], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                
                // Firestoreへの更新は非同期で実行（UIの更新をブロックしない）
                Task.detached { [cameraId, newCount] in
                    try? await CameraFirestoreService.shared.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
                }
                
                // processedSessionIdsからも削除（再接続時に重複チェックでブロックされないように）
                processedSessionIds.remove(sessionId)
                
                // モニター数に応じて品質を自動調整
                adjustQualityBasedOnMonitorCount()
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
        Task { @MainActor in
            // #region agent log
            DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "CameraViewModel.swift:470", "message": "didGenerateAnswer呼び出し", "data": ["sessionId": sessionId, "cameraId": cameraId ?? "nil"], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            // #endregion
            guard let cameraId = cameraId else {
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "CameraViewModel.swift:473", "message": "cameraIdがnil", "data": [:], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                return
            }
            
            do {
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "CameraViewModel.swift:477", "message": "setAnswer呼び出し前", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                try await signalingService.setAnswer(
                    cameraId: cameraId,
                    sessionId: sessionId,
                    answer: sdp.toDict()
                )
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "CameraViewModel.swift:481", "message": "setAnswer呼び出し後", "data": ["cameraId": cameraId, "sessionId": sessionId], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
            } catch {
                // #region agent log
                DebugLog.write(["sessionId": "debug-session", "runId": "run1", "hypothesisId": "K", "location": "CameraViewModel.swift:483", "message": "Answer送信エラー", "data": ["error": error.localizedDescription], "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
                // #endregion
                print("Answer送信エラー: \(error.localizedDescription)")
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
    }
}
