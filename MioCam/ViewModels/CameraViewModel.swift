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
import AudioToolbox
import AVFoundation

/// 接続中のモニター情報
struct ConnectedMonitorInfo: Identifiable {
    let id: String           // sessionId
    let monitorUserId: String
    let displayName: String  // Apple IDのユーザー名
    let deviceName: String   // デバイス名
    var isAudioEnabled: Bool = false  // デフォルトOFF
}

/// ビデオ品質
private enum VideoQuality {
    case p1080p
    case p720p
}

/// 帯域幅指標
private struct BandwidthMetrics {
    let availableBitrate: Int64  // bps
    let averagePacketLossRate: Double  // 0.0-1.0
    let averageRtt: Double  // ms
    let averageFrameRate: Double  // fps
    let sessionCount: Int
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
    /// ICE候補リスナーの管理（カメラ側）
    private var iceCandidateListeners: [String: ListenerRegistration] = [:]
    
    /// 帯域幅監視用のタスク
    private var bandwidthMonitorTask: Task<Void, Never>?
    /// 現在の品質状態
    private var currentQuality: VideoQuality = .p1080p
    /// 統計情報の更新間隔（秒）
    private let statsUpdateInterval: TimeInterval = 3.0
    /// 品質切り替えの頻度抑制用: 連続して同じ判定が出た回数
    private var consecutiveQualityDecision: (quality: VideoQuality, count: Int) = (.p1080p, 0)
    /// 品質切り替えに必要な連続判定回数（頻繁な切り替えを防ぐ）
    private let qualityChangeThreshold: Int = 2
    
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
            
            // 起動時に古い接続済みセッションとwaitingセッションをクリーンアップ（アプリクラッシュ時の残存セッションを削除）
            do {
                try await signalingService.cleanupAllConnectedSessions(cameraId: id)
                try await signalingService.cleanupAllWaitingSessions(cameraId: id)
                // 接続モニター数を0にリセット（クリーンアップ後は接続がないため）
                try await cameraService.updateConnectedMonitorCount(cameraId: id, count: 0)
                connectedMonitorCount = 0
                connectedMonitors.removeAll()
            } catch {
                print("セッションクリーンアップエラー: \(error.localizedDescription)")
            }
            
            // WebRTCのローカルビデオトラックをセットアップ（セッション監視開始前に準備）
            webRTCService.setupLocalVideoTrack(captureService: CameraCaptureService.shared)
            
            // WebRTCのローカルオーディオトラックをセットアップ（セッション監視開始前に準備）
            webRTCService.setupLocalAudioTrack()
            
            // WebRTCデリゲートを設定（Answer/ICE Candidate送信に必須。セッション監視開始前に設定）
            webRTCService.delegate = self
            
            // 新規セッション（モニター接続）の監視を開始（WebRTC準備完了後）
            startObservingSessions(cameraId: id)
            
            // 接続済みセッションの監視を開始（切断検知用）
            startObservingConnectedSessions(cameraId: id)
            
            // バックグラウンドオーディオを開始
            backgroundAudioService.startForCameraMode()
            
            // プッシュ通知トークンを保存
            if let cameraId = cameraId {
                try? await PushNotificationService.shared.saveTokenToCamera(cameraId: cameraId)
            }
            
            // オンライン状態を更新
            let initialBatteryLevel = currentBatteryLevel()
            lastReportedBatteryLevel = initialBatteryLevel
            await updateStatus(isOnline: true, batteryLevel: initialBatteryLevel)
            
            // 初期品質を設定（1台想定で1080p/30fps）
            // 帯域幅監視が有効なため、初期は1080pで開始（帯域幅監視が自動調整する）
            currentQuality = .p1080p
            let preset: AVCaptureSession.Preset = .hd1920x1080
            let frameRate: Int32 = 30
            CameraCaptureService.shared.updateQuality(preset: preset, frameRate: frameRate)
            WebRTCService.shared.updateVideoEncodingForAllSessions(for1080p: true)
            
            // 帯域幅監視を開始
            startBandwidthMonitoring()
            
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
    /// Firestoreスナップショットリスナーは初回で現在のwaitingセッションを返すため、observeNewSessionsのみで十分
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
        guard let sessionId = session.id,
              let offerDict = session.offer,
              let offer = RTCSessionDescription.from(dict: offerDict) else {
            return
        }
        
        // 重複処理を防止
        guard !processedSessionIds.contains(sessionId) else {
            return
        }
        processedSessionIds.insert(sessionId)
        
        do {
            
            // 表示名を取得（セッションから取得、なければデバイス名を使用）
            let displayName = session.displayName ?? session.monitorDeviceName
            
            // WebRTCでOfferを処理してAnswerを生成
            try await webRTCService.handleIncomingSession(sessionId: sessionId, offer: offer, monitorUserId: session.monitorUserId)
            
            // モニター側からのICE Candidatesを監視（カメラ側）
            let listener = signalingService.observeICECandidates(
                cameraId: cameraId,
                sessionId: sessionId
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let candidates):
                        let monitorCandidates = candidates.filter { $0.sender == .monitor }
                        #if DEBUG
                        print("Camera: モニターICE候補受信 - モニター側:\(monitorCandidates.count)件")
                        for c in monitorCandidates {
                            print("Camera: 候補内容 - \(String(c.candidate.prefix(120)))")
                        }
                        #endif
                        
                        for candidateModel in monitorCandidates {
                            guard let iceCandidate = RTCIceCandidate.from(dict: [
                                "candidate": candidateModel.candidate,
                                "sdpMid": candidateModel.sdpMid as Any,
                                "sdpMLineIndex": candidateModel.sdpMLineIndex ?? 0
                            ]) else {
                                continue
                            }
                            
                            do {
                                try await self?.webRTCService.addICECandidate(sessionId: sessionId, candidate: iceCandidate)
                            } catch {
                                // 追加失敗は後続ログで判断するためここでは黙殺
                            }
                        }
                    case .failure(let error):
                        print("セッションICE候補監視エラー: \(error.localizedDescription)")
                    }
                }
            }
            iceCandidateListeners[sessionId] = listener
            
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
            // 値が変わった場合のみFirestoreを更新（読み書きを最小限に）
            let newCount = connectedMonitors.count
            if connectedMonitorCount != newCount {
                connectedMonitorCount = newCount
                try await cameraService.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
            }
            
            // 帯域幅監視が品質を自動調整するため、ここでは調整しない
            
        } catch {
            print("セッション処理エラー: \(error.localizedDescription)")
            // エラーの場合は再処理できるようにする
            processedSessionIds.remove(sessionId)
            
            // エラー時はconnectedMonitorsに追加しない（接続台数が増えないようにする）
            // セッションはFirestoreに残るが、statusはwaitingのままなので問題ない
        }
    }
    
    /// 接続済みセッションの監視（切断検知用）
    /// 切断検知は webRTCService(_:didChangeState:for:) に委ねる
    private func startObservingConnectedSessions(cameraId: String) {
        connectedSessionListener = signalingService.observeConnectedSessions(cameraId: cameraId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let sessions):
                    // 現在のconnectedMonitorsと比較して、削除されたセッションを検知
                    let currentSessionIds = Set(self?.connectedMonitors.map { $0.id } ?? [])
                    let firestoreSessionIds = Set(sessions.map { $0.id ?? "" }.filter { !$0.isEmpty })
                    
                    // 削除されたセッション（Firestoreに存在しない）
                    let removedSessionIds = currentSessionIds.subtracting(firestoreSessionIds)
                    
                    if !removedSessionIds.isEmpty {
                        guard let cameraId = self?.cameraId else { return }
                        
                        // connectedMonitorsから削除されたセッションを削除
                        self?.connectedMonitors.removeAll { removedSessionIds.contains($0.id) }
                        
                        // デバイス数を更新（値が変わった場合のみFirestoreを更新）
                        let newCount = self?.connectedMonitors.count ?? 0
                        let oldCount = self?.connectedMonitorCount ?? 0
                        if oldCount != newCount {
                            self?.connectedMonitorCount = newCount
                            
                            // Firestoreへの更新は非同期で実行
                            Task.detached {
                                try? await CameraFirestoreService.shared.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
                            }
                        }
                        
                        // processedSessionIdsからも削除
                        for sessionId in removedSessionIds {
                            self?.processedSessionIds.remove(sessionId)
                        }
                        
                        // 帯域幅監視が品質を自動調整するため、ここでは調整しない
                        // モニター数が変更されたことを帯域幅監視に通知するため、次回の更新を待つ
                    }
                case .failure(let error):
                    print("接続済みセッション監視エラー: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Quality Adjustment
    
    /// モニター数に応じて品質を自動調整（後方互換性のため残す）
    private func adjustQualityBasedOnMonitorCount() {
        let is1080p = connectedMonitorCount <= 2
        let preset: AVCaptureSession.Preset = is1080p ? .hd1920x1080 : .hd1280x720
        let frameRate: Int32 = 30
        
        CameraCaptureService.shared.updateQuality(preset: preset, frameRate: frameRate)
        // 解像度を優先（デフォルト）
        WebRTCService.shared.updateVideoEncodingForAllSessions(for1080p: is1080p, preferResolution: true)
    }
    
    /// 帯域幅指標を集計
    private func aggregateBandwidthMetrics(from stats: [String: RTCStatisticsReport]) -> BandwidthMetrics {
        var totalAvailableBitrate: Int64 = 0
        var totalPacketLoss: Double = 0
        var totalRtt: Double = 0
        var totalFrameRate: Double = 0
        var activeSessionCount = 0
        var sessionsWithBitrate = 0
        var sessionsWithPacketLoss = 0
        var sessionsWithRtt = 0
        var sessionsWithFrameRate = 0
        
        for (_, report) in stats {
            // availableOutgoingBitrate を取得（合計を使用）
            if let candidateStats = report.statistics.values.first(where: { $0.type == "candidate-pair" }),
               let availableBitrate = candidateStats.values["availableOutgoingBitrate"] as? NSNumber {
                totalAvailableBitrate += availableBitrate.int64Value
                sessionsWithBitrate += 1
            }
            
            // packetLossRate を取得（outbound-rtpから取得、カメラ側は送信側）
            if let outboundStats = report.statistics.values.first(where: { $0.type == "outbound-rtp" }),
               let packetsLost = outboundStats.values["packetsLost"] as? NSNumber,
               let packetsSent = outboundStats.values["packetsSent"] as? NSNumber,
               packetsSent.intValue > 0 {
                let lossRate = Double(packetsLost.intValue) / Double(packetsSent.intValue)
                totalPacketLoss += lossRate
                sessionsWithPacketLoss += 1
            }
            
            // rtt を取得
            if let candidateStats = report.statistics.values.first(where: { $0.type == "candidate-pair" }),
               let rtt = candidateStats.values["currentRtt"] as? NSNumber {
                totalRtt += rtt.doubleValue
                sessionsWithRtt += 1
            }
            
            // フレームレートを取得（outbound-rtpから取得）
            if let outboundStats = report.statistics.values.first(where: { $0.type == "outbound-rtp" }) {
                // framesPerSecond を直接取得（利用可能な場合）
                if let framesPerSecond = outboundStats.values["framesPerSecond"] as? NSNumber {
                    totalFrameRate += framesPerSecond.doubleValue
                    sessionsWithFrameRate += 1
                }
                // framesPerSecondが取得できない場合、framesEncodedとtimestampから計算を試みる
                // ただし、これは前回の統計情報との差分が必要なため、今回はframesPerSecondのみを使用
            }
            
            activeSessionCount += 1
        }
        
        // 帯域幅は合計を使用（各セッションの利用可能帯域幅の合計）
        // 統計情報が取得できない場合は、デフォルトで十分な帯域幅があると仮定（10Mbps × セッション数）
        let availableBitrate = sessionsWithBitrate > 0 ? totalAvailableBitrate : Int64(10_000_000) * Int64(activeSessionCount)
        
        // フレームレートは平均を使用（各セッションの平均フレームレートの平均）
        // 統計情報が取得できない場合は、デフォルトで30fpsと仮定
        let averageFrameRate = sessionsWithFrameRate > 0 ? totalFrameRate / Double(sessionsWithFrameRate) : 30.0
        
        return BandwidthMetrics(
            availableBitrate: availableBitrate,
            averagePacketLossRate: sessionsWithPacketLoss > 0 ? totalPacketLoss / Double(sessionsWithPacketLoss) : 0.0,
            averageRtt: sessionsWithRtt > 0 ? totalRtt / Double(sessionsWithRtt) : 0.0,
            averageFrameRate: averageFrameRate,
            sessionCount: activeSessionCount
        )
    }
    
    /// 帯域幅に基づいて品質を判定
    private func determineQuality(
        bandwidthMetrics: BandwidthMetrics,
        monitorCount: Int
    ) -> VideoQuality {
        // セッションがない場合はデフォルトで1080p
        guard bandwidthMetrics.sessionCount > 0, monitorCount > 0 else {
            return .p1080p
        }
        
        // フレームレートチェック（ヒステリシス付き）
        // 1080p → 720p: 15fps未満で切り替え（閾値緩和により1080p維持を優先）
        // 720p → 1080p: 26fps以上で戻す（頻繁な切り替えを防ぐ）
        if currentQuality == .p1080p && bandwidthMetrics.averageFrameRate < 15.0 {
            // フレームレートが15fps未満の場合は解像度を下げる
            return .p720p
        } else if currentQuality == .p720p && bandwidthMetrics.averageFrameRate >= 26.0 {
            // 720pから1080pに戻す条件: フレームレートが26fps以上かつ、2台以下接続
            if monitorCount <= 2 {
                return .p1080p
            }
            // 3台以上接続の場合は帯域幅もチェック（後続のロジックで判定）
            // ここでは何も返さず、後続のロジックで判定される
        }
        
        // 2台以下接続の場合は統計情報に関係なく1080p（フレームレートチェックは上で実施済み）
        if monitorCount <= 2 {
            return .p1080p
        }
        
        // 3台以上接続の場合のみ帯域幅に応じて判定
        // 1080pに必要な帯域幅: 4.5Mbps × 接続台数
        let requiredBitrateFor1080p = Int64(4_500_000) * Int64(monitorCount)
        
        // 統計情報が取得できていない可能性がある場合（デフォルト値の10Mbps × セッション数）
        // この場合は帯域幅に余裕があると仮定して720pを維持（安全側に倒す）
        let defaultBitrate = Int64(10_000_000) * Int64(bandwidthMetrics.sessionCount)
        let isUsingDefaultBitrate = bandwidthMetrics.availableBitrate >= defaultBitrate * 9 / 10
        
        // 現在の品質に応じたヒステリシス
        let isCurrently1080p = currentQuality == .p1080p
        
        if isCurrently1080p {
            // 1080p → 720p: 帯域幅が不足（必要帯域幅の90%未満）またはパケットロス率5%以上
            // ただし、統計情報が取得できていない場合は720pに下げる（安全側に倒す）
            if isUsingDefaultBitrate {
                return .p720p
            }
            
            let hasEnoughBandwidth = bandwidthMetrics.availableBitrate >= Int64(Double(requiredBitrateFor1080p) * 0.9)
            // パケットロス率が取得できていない場合は0.0なので、条件を満たす
            let hasLowPacketLoss = bandwidthMetrics.averagePacketLossRate < 0.05
            // RTTが取得できていない場合は0.0なので、条件を満たす
            let hasLowRtt = bandwidthMetrics.averageRtt < 200 && bandwidthMetrics.averageRtt > 0
            
            if hasEnoughBandwidth && hasLowPacketLoss && hasLowRtt {
                return .p1080p
            } else {
                return .p720p
            }
        } else {
            // 720p → 1080p: 帯域幅が十分（必要帯域幅の100%以上）かつパケットロス率5%以下
            // 統計情報が取得できていない場合は720pを維持（安全側に倒す）
            if isUsingDefaultBitrate {
                return .p720p
            }
            
            // 720pから1080pに上げる条件を緩和（100%以上、パケットロス5%以下、RTTは取得できていない場合は無視）
            let hasEnoughBandwidth = bandwidthMetrics.availableBitrate >= requiredBitrateFor1080p
            let hasLowPacketLoss = bandwidthMetrics.averagePacketLossRate < 0.05
            // RTTが0の場合は統計情報が取得できていないと判断し、条件から除外
            let hasLowRtt = bandwidthMetrics.averageRtt == 0 || bandwidthMetrics.averageRtt < 200
            
            if hasEnoughBandwidth && hasLowPacketLoss && hasLowRtt {
                return .p1080p
            } else {
                return .p720p
            }
        }
    }
    
    // MARK: - Bandwidth Monitoring
    
    /// 帯域幅監視タスクを開始
    private func startBandwidthMonitoring() {
        stopBandwidthMonitoring()  // 既存のタスクがあれば停止
        
        bandwidthMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateQualityBasedOnBandwidth()
                try? await Task.sleep(nanoseconds: UInt64((self?.statsUpdateInterval ?? 3.0) * 1_000_000_000))
            }
        }
    }
    
    /// 帯域幅監視タスクを停止
    private func stopBandwidthMonitoring() {
        bandwidthMonitorTask?.cancel()
        bandwidthMonitorTask = nil
    }
    
    /// 帯域幅に基づいて品質を更新
    private func updateQualityBasedOnBandwidth() async {
        // 接続台数が0の場合は前回の品質を維持（接続確立前は品質変更しない）
        guard connectedMonitorCount > 0 else {
            return
        }
        
        let stats = await webRTCService.getAllSessionStats()
        
        // 統計情報が取得できない場合（接続確立前など）は前回の品質を維持
        guard !stats.isEmpty else {
            return
        }
        
        // 全セッションの統計情報から帯域幅指標を集計
        let metrics = aggregateBandwidthMetrics(from: stats)
        
        // デバッグログ（開発時のみ）
        #if DEBUG
        print("BandwidthMetrics: availableBitrate=\(metrics.availableBitrate / 1_000_000)Mbps, packetLoss=\(metrics.averagePacketLossRate * 100)%, rtt=\(metrics.averageRtt)ms, frameRate=\(String(format: "%.1f", metrics.averageFrameRate))fps, sessions=\(metrics.sessionCount), monitorCount=\(connectedMonitorCount)")
        #endif
        
        // 品質判定
        let targetQuality = determineQuality(
            bandwidthMetrics: metrics,
            monitorCount: connectedMonitorCount
        )
        
        // 品質切り替えの頻度抑制: 連続して同じ判定が複数回出た場合のみ切り替え
        if targetQuality == consecutiveQualityDecision.quality {
            consecutiveQualityDecision.count += 1
        } else {
            consecutiveQualityDecision = (targetQuality, 1)
        }
        
        // 品質が変更された場合、かつ連続判定回数が閾値を超えた場合のみ更新
        if targetQuality != currentQuality && consecutiveQualityDecision.count >= qualityChangeThreshold {
            #if DEBUG
            print("Quality change: \(currentQuality) -> \(targetQuality) (consecutive: \(consecutiveQualityDecision.count))")
            #endif
            await applyQuality(targetQuality)
            currentQuality = targetQuality
            // 切り替え後はカウントをリセット
            consecutiveQualityDecision = (targetQuality, 0)
        }
        
        // 1080pを維持しつつ、フレームレートを24fps以上に保つ
        let is1080p = currentQuality == .p1080p
        
        if is1080p {
            // 1080pの場合
            if metrics.averageFrameRate < 24.0 {
                // フレームレートが24fps未満の場合、まずビットレートを調整してフレームレートを回復を試みる
                webRTCService.adjustBitrateForFrameRate(for1080p: true, currentFrameRate: metrics.averageFrameRate)
                
                // それでもフレームレートが低い場合はバランス型に切り替え（解像度を下げてフレームレートを回復）
                if metrics.averageFrameRate < 15.0 {
                    webRTCService.updateVideoEncodingBasedOnFrameRate(for1080p: true, currentFrameRate: metrics.averageFrameRate)
                    #if DEBUG
                    print("Frame rate too low (\(String(format: "%.1f", metrics.averageFrameRate))fps), switching to balanced degradation preference")
                    #endif
                } else {
                    // 20-24fpsの場合は解像度優先を維持（ビットレート調整のみ）
                    webRTCService.updateVideoEncodingForAllSessions(for1080p: true, preferResolution: true)
                    #if DEBUG
                    print("Frame rate low (\(String(format: "%.1f", metrics.averageFrameRate))fps), adjusting bitrate while maintaining resolution")
                    #endif
                }
            } else {
                // フレームレートが24fps以上の場合は解像度優先を維持
                webRTCService.updateVideoEncodingForAllSessions(for1080p: true, preferResolution: true)
            }
        } else {
            // 720pの場合も解像度優先を維持
            webRTCService.updateVideoEncodingForAllSessions(for1080p: false, preferResolution: true)
        }
    }
    
    /// 品質を適用
    private func applyQuality(_ quality: VideoQuality) async {
        let is1080p = quality == .p1080p
        let preset: AVCaptureSession.Preset = is1080p ? .hd1920x1080 : .hd1280x720
        let frameRate: Int32 = 30
        
        CameraCaptureService.shared.updateQuality(preset: preset, frameRate: frameRate)
        // 解像度を優先（デフォルト）
        webRTCService.updateVideoEncodingForAllSessions(for1080p: is1080p, preferResolution: true)
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
    
    private var lastReportedBatteryLevel: Int? = nil
    private let batteryChangeThreshold: Int = 5
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let currentLevel = self.currentBatteryLevel()
                
                // 前回の更新から5%以上の変化があった場合のみ更新
                let batteryChanged = self.lastReportedBatteryLevel.map { abs($0 - currentLevel) >= self.batteryChangeThreshold } ?? true
                
                if batteryChanged {
                    self.lastReportedBatteryLevel = currentLevel
                    await self.updateStatus(isOnline: true, batteryLevel: currentLevel)
                }
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
        // 帯域幅監視を停止
        stopBandwidthMonitoring()
        
        // WebRTC接続を終了
        webRTCService.closeAllSessions()
        
        // バックグラウンドオーディオを停止
        backgroundAudioService.stopForCameraMode()
        
        // カメラキャプチャを停止
        CameraCaptureService.shared.stopCapture()
        
        // ICE候補リスナーを停止
        for (_, listener) in iceCandidateListeners {
            listener.remove()
        }
        iceCandidateListeners.removeAll()
        
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
            case .connected:
                // 接続が確立した時に音声を再生
                playConnectionSound()
                
            case .disconnected, .failed, .closed:
                // 接続が切断された場合、モニター数を減らす
                guard let cameraId = cameraId else { return }
                
                // 切断時に音声を再生
                playDisconnectionSound()
                
                // ICE候補リスナーを停止
                iceCandidateListeners[sessionId]?.remove()
                iceCandidateListeners.removeValue(forKey: sessionId)
                
                // connectedMonitorsからセッションを削除
                connectedMonitors.removeAll { $0.id == sessionId }
                
                // connectedMonitors.countを使用して同期を保つ
                // 値が変わった場合のみFirestoreを更新（読み書きを最小限に）
                let newCount = connectedMonitors.count
                let oldCount = connectedMonitorCount
                if oldCount != newCount {
                    connectedMonitorCount = newCount
                    
                    // Firestoreへの更新は非同期で実行（UIの更新をブロックしない）
                    Task.detached { [cameraId, newCount] in
                        try? await CameraFirestoreService.shared.updateConnectedMonitorCount(cameraId: cameraId, count: newCount)
                    }
                }
                
                // processedSessionIdsからも確実に削除（再接続時に重複チェックでブロックされないように）
                processedSessionIds.remove(sessionId)
                
                // ICE候補リスナーも確実にクリーンアップ
                iceCandidateListeners[sessionId]?.remove()
                iceCandidateListeners.removeValue(forKey: sessionId)
                
                // 帯域幅監視が品質を自動調整するため、ここでは調整しない
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
            #if DEBUG
            print("Camera: ICE候補生成・送信 - \(candidate.sdp.prefix(100))")
            #endif
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
            guard let cameraId = cameraId else {
                return
            }
            
            do {
                try await signalingService.setAnswer(
                    cameraId: cameraId,
                    sessionId: sessionId,
                    answer: sdp.toDict()
                )
            } catch {
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
    
    // MARK: - Sound Effects
    
    /// 接続時の音声を再生（ピンポーン）
    private func playConnectionSound() {
        // カスタム音声ファイル「ピンポーン」を再生
        if let soundURL = Bundle.main.url(forResource: "connection_sound", withExtension: "caf") {
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            // 音声ファイルが見つからない場合はシステムサウンドを使用
            // 接続時: 着信音（上昇する音）
            AudioServicesPlaySystemSound(1005) // kSystemSoundID_NewMail
        }
    }
    
    /// 切断時の音声を再生（ポーン）
    private func playDisconnectionSound() {
        // カスタム音声ファイル「ポーン」を再生
        if let soundURL = Bundle.main.url(forResource: "disconnection_sound", withExtension: "caf") {
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            // 音声ファイルが見つからない場合はシステムサウンドを使用
            // 切断時: 通話終了音（下降する音）
            AudioServicesPlaySystemSound(1007) // kSystemSoundID_MailReceived
        }
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
