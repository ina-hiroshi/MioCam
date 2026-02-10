//
//  VideoView.swift
//  MioCam
//
//  WebRTC映像を表示するビュー
//

import SwiftUI
import WebRTC

/// WebRTC映像を表示するUIViewRepresentable
struct VideoView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?
    var contentMode: UIView.ContentMode = .scaleAspectFill
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let videoView = RTCMTLVideoView()
        videoView.videoContentMode = contentMode
        videoView.backgroundColor = .black
        
        if let track = videoTrack {
            track.add(videoView)
            context.coordinator.currentTrack = track
        }
        
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // contentModeが変更された場合のみ更新（不要なレイアウトパスを防止）
        if uiView.videoContentMode != contentMode {
            uiView.videoContentMode = contentMode
        }
        
        // トラックの変更がある場合のみ更新（重複追加を防止）
        // 注意: RTCVideoTrackのレンダラーは一度だけ追加する必要がある
        // updateUIViewは頻繁に呼ばれるため、トラックが変更された場合のみ追加
        if let track = videoTrack, context.coordinator.currentTrack !== track {
            // 前回のトラックからレンダラーを削除（可能な場合）
            if let previousTrack = context.coordinator.currentTrack {
                previousTrack.remove(uiView)
            }
            // 新しいトラックにレンダラーを追加
            track.add(uiView)
            context.coordinator.currentTrack = track
        } else if videoTrack == nil && context.coordinator.currentTrack != nil {
            // トラックがnilになった場合は前回のトラックからレンダラーを削除
            context.coordinator.currentTrack?.remove(uiView)
            context.coordinator.currentTrack = nil
        }
    }
    
    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        // クリーンアップ: レンダラーを削除
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }
    
    class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}

#Preview {
    VideoView(videoTrack: nil)
        .frame(height: 300)
        .background(Color.black)
}
