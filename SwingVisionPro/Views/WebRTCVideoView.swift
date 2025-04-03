//
//  WebRTCVideoView.swift
//  SwingVisionPro
//
//  Created on 2025/03/31.
//

import SwiftUI
import WebRTC

// UIViewRepresentableを使ってRTCVideoViewをSwiftUIで利用できるようにする
struct WebRTCVideoView: UIViewRepresentable {
    var videoTrack: RTCVideoTrack?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        print("WebRTCVideoView - makeUIView")
        let videoView = RTCMTLVideoView(frame: .zero)
        videoView.videoContentMode = .scaleAspectFit
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        print("WebRTCVideoView - updateUIView, videoTrack: \(videoTrack != nil)")
        
        // videoViewをコーディネータに設定
        context.coordinator.videoView = uiView
        
        // トラックを更新
        if let newTrack = videoTrack {
            if context.coordinator.currentTrack !== newTrack {
                print("WebRTCVideoView - New track received, ID: \(newTrack.trackId)")
                
                // 古いトラックがあれば削除
                if let oldTrack = context.coordinator.currentTrack {
                    print("WebRTCVideoView - Removing old track")
                    oldTrack.remove(uiView)
                }
                
                // 新しいトラックを設定
                context.coordinator.currentTrack = newTrack
                newTrack.add(uiView)
                print("WebRTCVideoView - Added new track to view")
            }
        } else {
            // トラックがnilの場合は現在のトラックを削除
            if let oldTrack = context.coordinator.currentTrack {
                print("WebRTCVideoView - Removing track as videoTrack is nil")
                oldTrack.remove(uiView)
                context.coordinator.currentTrack = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var videoView: RTCMTLVideoView?
        var currentTrack: RTCVideoTrack?
    }
}
