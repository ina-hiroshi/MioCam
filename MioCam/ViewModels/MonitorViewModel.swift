//
//  MonitorViewModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import Combine
import FirebaseFirestore

/// モニター側の状態を管理するViewModel
@MainActor
class MonitorViewModel: ObservableObject {
    @Published var pairedCameras: [MonitorLinkModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let monitorLinkService = MonitorLinkService.shared
    private let signalingService = SignalingService.shared
    private var monitorLinkListener: ListenerRegistration?
    
    /// ペアリング済みカメラ一覧を取得
    func loadPairedCameras(monitorUserId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            pairedCameras = try await monitorLinkService.getPairedCameras(monitorUserId: monitorUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// ペアリング済みカメラ一覧をリアルタイム監視開始
    func startObservingPairedCameras(monitorUserId: String) {
        stopObservingPairedCameras()
        
        monitorLinkListener = monitorLinkService.observePairedCameras(monitorUserId: monitorUserId) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let cameras):
                    self?.pairedCameras = cameras
                    self?.isLoading = false
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }
    
    /// ペアリング済みカメラ一覧の監視を停止
    func stopObservingPairedCameras() {
        monitorLinkListener?.remove()
        monitorLinkListener = nil
    }
    
    /// QRコードからカメラ情報を取得してペアリング
    func pairWithCamera(cameraId: String, pairingCode: String, monitorUserId: String) async throws -> Bool {
        // カメラの存在確認とpairingCode検証
        let isValid = try await monitorLinkService.verifyCamera(cameraId: cameraId, pairingCode: pairingCode)
        
        if !isValid {
            throw NSError(domain: "MonitorViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "無効なペアリングコードです"])
        }
        
        // カメラ情報を取得
        guard let camera = try await CameraFirestoreService.shared.getCamera(cameraId: cameraId) else {
            throw NSError(domain: "MonitorViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "カメラが見つかりません"])
        }
        
        // ペアリング記録を作成
        try await monitorLinkService.createMonitorLink(
            monitorUserId: monitorUserId,
            cameraId: cameraId,
            cameraDeviceName: camera.deviceName
        )
        
        // ペアリング済みカメラ一覧を再読み込み
        await loadPairedCameras(monitorUserId: monitorUserId)
        
        return true
    }
    
    /// ペアリングを解除
    func unpairCamera(monitorUserId: String, cameraId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await monitorLinkService.deactivateMonitorLink(monitorUserId: monitorUserId, cameraId: cameraId)
            await loadPairedCameras(monitorUserId: monitorUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
