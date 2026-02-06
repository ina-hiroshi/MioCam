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
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let videoView = RTCMTLVideoView()
        videoView.videoContentMode = contentMode
        videoView.backgroundColor = .black
        
        if let track = videoTrack {
            track.add(videoView)
        }
        
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.videoContentMode = contentMode
        
        // トラックの変更があれば更新
        if let track = videoTrack {
            track.add(uiView)
        }
    }
    
    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        // クリーンアップ
    }
}

#Preview {
    VideoView(videoTrack: nil)
        .frame(height: 300)
        .background(Color.black)
}
