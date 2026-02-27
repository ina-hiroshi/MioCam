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
    var refreshToken: Int = 0
    
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
        context.coordinator.lastRefreshToken = refreshToken
        
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // contentModeが変更された場合のみ更新（不要なレイアウトパスを防止）
        if uiView.videoContentMode != contentMode {
            uiView.videoContentMode = contentMode
        }
        
        let trackChanged = (videoTrack !== context.coordinator.currentTrack)
        let refreshTokenChanged = (refreshToken != context.coordinator.lastRefreshToken)
        context.coordinator.lastRefreshToken = refreshToken
        
        // トラックの変更、または refreshToken の変更（再アタッチ要求）の場合に更新
        if let track = videoTrack {
            if trackChanged || refreshTokenChanged {
                // 前回のトラックからレンダラーを削除
                if let previousTrack = context.coordinator.currentTrack {
                    previousTrack.remove(uiView)
                }
                // 新しいトラックを追加（同じトラックでも再アタッチ）
                track.add(uiView)
                context.coordinator.currentTrack = track
            }
        } else if context.coordinator.currentTrack != nil {
            // トラックがnilになった場合は前回のトラックからレンダラーを削除
            context.coordinator.currentTrack?.remove(uiView)
            context.coordinator.currentTrack = nil
        }
    }
    
    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }
    
    class Coordinator {
        var currentTrack: RTCVideoTrack?
        var lastRefreshToken: Int = 0
    }
}

#Preview {
    VideoView(videoTrack: nil)
        .frame(height: 300)
        .background(Color.black)
}
