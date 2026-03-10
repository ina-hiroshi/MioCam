//
//  BackgroundAudioService.swift
//  MioCam
//
//  バックグラウンドでWebRTCマイク音声キャプチャを維持するためのオーディオセッション設定サービス
//

import Foundation
import AVFoundation

/// WebRTCマイクキャプチャのためのオーディオセッション設定サービス
class BackgroundAudioService {
    static let shared = BackgroundAudioService()
    
    // MARK: - Properties
    
    private var isSessionActive = false
    
    /// オーディオセッションがアクティブかどうか
    var isActive: Bool {
        return isSessionActive
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// オーディオセッションを開始（WebRTCマイクキャプチャ用）
    func start() {
        guard !isSessionActive else { return }
        
        do {
            try configureAudioSession()
            isSessionActive = true
            print("BackgroundAudioService: 開始")
        } catch {
            print("BackgroundAudioService: 開始エラー - \(error.localizedDescription)")
        }
    }
    
    /// オーディオセッションを停止
    func stop() {
        guard isSessionActive else { return }
        
        isSessionActive = false
        
        // オーディオセッションを非アクティブに
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("BackgroundAudioService: セッション停止エラー - \(error.localizedDescription)")
        }
        
        print("BackgroundAudioService: 停止")
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // .playAndRecordカテゴリでマイク入力とスピーカー出力を有効化
        // .videoChatモードはスピーカー出力がデフォルトで、映像監視アプリに適切
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try audioSession.setActive(true)
        
        // 明示的にスピーカー出力を強制（WebRTCによる上書き対策）
        try audioSession.overrideOutputAudioPort(.speaker)
    }
    
    /// スピーカー出力を強制する（WebRTCがオーディオルートを変更した場合に呼び出す）
    func ensureSpeakerOutput() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            print("BackgroundAudioService: スピーカー出力強制エラー - \(error.localizedDescription)")
        }
    }
}

// MARK: - App Lifecycle Integration

extension BackgroundAudioService {
    /// カメラモード開始時に呼び出す
    func startForCameraMode() {
        start()
    }
    
    /// カメラモード終了時に呼び出す
    func stopForCameraMode() {
        stop()
    }
    
    /// モニターモード開始時に呼び出す（音声セッション設定のみ）
    func startForMonitorMode() {
        do {
            try configureAudioSession()
            print("BackgroundAudioService: Monitor mode audio session configured")
        } catch {
            print("BackgroundAudioService: Monitor mode audio session configuration error - \(error.localizedDescription)")
        }
    }
    
    /// モニターモード終了時に呼び出す
    func stopForMonitorMode() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("BackgroundAudioService: Monitor mode audio session deactivated")
        } catch {
            print("BackgroundAudioService: Monitor mode audio session deactivation error - \(error.localizedDescription)")
        }
    }
}
