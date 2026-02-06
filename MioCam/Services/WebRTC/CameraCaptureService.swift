//
//  CameraCaptureService.swift
//  MioCam
//
//  カメラ映像キャプチャを管理するサービス
//

import Foundation
import AVFoundation
import UIKit

/// カメラキャプチャのデリゲートプロトコル
protocol CameraCaptureDelegate: AnyObject {
    /// 新しいビデオフレームがキャプチャされた時に呼ばれる
    func cameraCaptureService(_ service: CameraCaptureService, didCapture sampleBuffer: CMSampleBuffer)
}

/// カメラ映像キャプチャを管理するサービス
class CameraCaptureService: NSObject, @unchecked Sendable {
    static let shared = CameraCaptureService()
    
    // MARK: - Properties
    
    weak var delegate: CameraCaptureDelegate?
    
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    
    private let sessionQueue = DispatchQueue(label: "com.miocam.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.miocam.camera.videoOutput")
    
    /// カメラが実行中かどうか
    var isRunning: Bool {
        captureSession?.isRunning ?? false
    }
    
    /// 現在のカメラ位置（フロント/バック）
    var cameraPosition: AVCaptureDevice.Position {
        currentCameraPosition
    }
    
    // MARK: - Configuration
    
    /// 解像度プリセット（初期値720p）
    var sessionPreset: AVCaptureSession.Preset = .hd1280x720
    
    /// フレームレート（初期値30fps）
    var frameRate: Int32 = 30
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// カメラキャプチャを開始
    func startCapture(position: AVCaptureDevice.Position = .back) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraCaptureError.setupFailed)
                    return
                }
                
                do {
                    try self.setupCaptureSession(position: position)
                    self.captureSession?.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// カメラキャプチャを停止
    func stopCapture() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.videoOutput = nil
        }
    }
    
    /// カメラを切り替え（フロント/バック）
    func switchCamera() async throws {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        stopCapture()
        try await startCapture(position: newPosition)
    }
    
    /// 解像度とフレームレートを更新（接続台数に応じて動的に変更）
    func updateQuality(preset: AVCaptureSession.Preset, frameRate: Int32) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let session = self.captureSession,
                  let device = self.currentCameraDevice() else { return }
            
            session.beginConfiguration()
            
            // プリセット変更
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                self.sessionPreset = preset
            }
            
            // フレームレート変更
            do {
                try device.lockForConfiguration()
                let targetFrameRate = CMTime(value: 1, timescale: frameRate)
                device.activeVideoMinFrameDuration = targetFrameRate
                device.activeVideoMaxFrameDuration = targetFrameRate
                device.unlockForConfiguration()
                self.frameRate = frameRate
            } catch {
                print("フレームレート設定エラー: \(error)")
            }
            
            session.commitConfiguration()
        }
    }
    
    /// プレビューレイヤーを取得
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    // MARK: - Private Methods
    
    private func setupCaptureSession(position: AVCaptureDevice.Position) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // プリセット設定
        if session.canSetSessionPreset(sessionPreset) {
            session.sessionPreset = sessionPreset
        }
        
        // カメラデバイス取得
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraCaptureError.cameraNotFound
        }
        
        // 入力設定
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraCaptureError.inputSetupFailed
        }
        session.addInput(input)
        
        // ビデオ出力設定
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        output.alwaysDiscardsLateVideoFrames = true
        
        guard session.canAddOutput(output) else {
            throw CameraCaptureError.outputSetupFailed
        }
        session.addOutput(output)
        
        // フレームレート設定
        try camera.lockForConfiguration()
        let targetFrameRate = CMTime(value: 1, timescale: frameRate)
        camera.activeVideoMinFrameDuration = targetFrameRate
        camera.activeVideoMaxFrameDuration = targetFrameRate
        camera.unlockForConfiguration()
        
        session.commitConfiguration()
        
        self.captureSession = session
        self.videoOutput = output
        self.currentCameraPosition = position
    }
    
    private func currentCameraDevice() -> AVCaptureDevice? {
        guard let session = captureSession else { return nil }
        return session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first?.device
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraCaptureService(self, didCapture: sampleBuffer)
    }
}

// MARK: - Error

enum CameraCaptureError: LocalizedError {
    case cameraNotFound
    case inputSetupFailed
    case outputSetupFailed
    case setupFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .cameraNotFound:
            return "カメラが見つかりません"
        case .inputSetupFailed:
            return "カメラ入力の設定に失敗しました"
        case .outputSetupFailed:
            return "カメラ出力の設定に失敗しました"
        case .setupFailed:
            return "カメラのセットアップに失敗しました"
        case .permissionDenied:
            return "カメラへのアクセスが許可されていません"
        }
    }
}

// MARK: - Permission Helper

extension CameraCaptureService {
    /// カメラのアクセス許可状態を取得
    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    /// カメラのアクセス許可をリクエスト
    static func requestAuthorization() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
    
    /// カメラアクセスが許可されているかチェック
    static var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
}
