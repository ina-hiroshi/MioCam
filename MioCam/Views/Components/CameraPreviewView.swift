//
//  CameraPreviewView.swift
//  MioCam
//
//  カメラプレビューを表示するSwiftUIビュー
//

import SwiftUI
import AVFoundation

/// カメラプレビューを表示するUIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    let captureService: CameraCaptureService
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.captureService = captureService
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updatePreviewLayer()
    }
}

/// カメラプレビュー用のUIView
class CameraPreviewUIView: UIView {
    var captureService: CameraCaptureService? {
        didSet {
            updatePreviewLayer()
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func updatePreviewLayer() {
        // 既存のレイヤーを削除
        previewLayer?.removeFromSuperlayer()
        
        // 新しいプレビューレイヤーを作成
        guard let layer = captureService?.makePreviewLayer() else { return }
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
}

// MARK: - Preview

#Preview {
    CameraPreviewView(captureService: CameraCaptureService.shared)
        .ignoresSafeArea()
}
