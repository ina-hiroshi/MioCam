//
//  BackgroundAudioService.swift
//  MioCam
//
//  バックグラウンドでアプリを維持するための無音オーディオ再生サービス
//

import Foundation
import AVFoundation

/// バックグラウンド維持のための無音オーディオ再生サービス
class BackgroundAudioService {
    static let shared = BackgroundAudioService()
    
    // MARK: - Properties
    
    private var audioPlayer: AVAudioPlayer?
    private var isPlaying = false
    
    /// バックグラウンドオーディオが再生中かどうか
    var isActive: Bool {
        return isPlaying
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// バックグラウンドオーディオを開始
    func start() {
        guard !isPlaying else { return }
        
        do {
            // オーディオセッションを設定
            try configureAudioSession()
            
            // 無音オーディオを作成して再生
            try createAndPlaySilentAudio()
            
            isPlaying = true
            print("BackgroundAudioService: 開始")
        } catch {
            print("BackgroundAudioService: 開始エラー - \(error.localizedDescription)")
        }
    }
    
    /// バックグラウンドオーディオを停止
    func stop() {
        guard isPlaying else { return }
        
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        
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
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try audioSession.setActive(true)
        
        // 明示的にスピーカー出力を強制（WebRTCによる上書き対策）
        try audioSession.overrideOutputAudioPort(.speaker)
        
        // #region agent log
        let outputs = audioSession.currentRoute.outputs
        let outputNames = outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
        print("[MioCam-AudioDebug][HA][HB] configureAudioSession DONE - category=\(audioSession.category.rawValue), mode=\(audioSession.mode.rawValue), outputs=[\(outputNames)]")
        // #endregion
    }
    
    /// スピーカー出力を強制する（WebRTCがオーディオルートを変更した場合に呼び出す）
    func ensureSpeakerOutput() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.overrideOutputAudioPort(.speaker)
            
            // #region agent log
            let outputs = audioSession.currentRoute.outputs
            let outputNames = outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
            print("[MioCam-AudioDebug][FIX] ensureSpeakerOutput - outputs=[\(outputNames)]")
            // #endregion
        } catch {
            print("BackgroundAudioService: スピーカー出力強制エラー - \(error.localizedDescription)")
        }
    }
    
    private func createAndPlaySilentAudio() throws {
        // 無音のオーディオデータを生成（1秒間の無音）
        let sampleRate: Double = 44100.0
        let duration: Double = 1.0
        let numSamples = Int(sampleRate * duration)
        
        // WAVファイルヘッダー + 無音データを作成
        var wavData = Data()
        
        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + numSamples * 2)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        let fmtChunkSize: UInt32 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        let numChannels: UInt16 = 1 // Mono
        wavData.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sampleRateInt: UInt32 = UInt32(sampleRate)
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        let byteRate: UInt32 = UInt32(sampleRate) * 2
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign: UInt16 = 2
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        let bitsPerSample: UInt16 = 16
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        wavData.append(contentsOf: "data".utf8)
        let dataChunkSize: UInt32 = UInt32(numSamples * 2)
        wavData.append(contentsOf: withUnsafeBytes(of: dataChunkSize.littleEndian) { Array($0) })
        
        // 無音データ（0で埋める）
        wavData.append(contentsOf: [UInt8](repeating: 0, count: numSamples * 2))
        
        // AVAudioPlayerを作成
        audioPlayer = try AVAudioPlayer(data: wavData)
        audioPlayer?.numberOfLoops = -1 // 無限ループ
        audioPlayer?.volume = 0.0 // 音量0
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
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
