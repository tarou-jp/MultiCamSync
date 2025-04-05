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
        print("WebRTCVideoView - updateUIView, videoTrack is set: \(videoTrack != nil)")

        // 常に videoView をコーディネータに設定しておく（インスタンスが変わる可能性は低いが念のため）
        context.coordinator.videoView = uiView

        // 現在のトラックと渡されたトラックを比較
        let currentTrack = context.coordinator.currentTrack
        let newTrack = videoTrack

        // ① 新しいトラックが存在し、かつ現在のトラックと異なる場合
        if let newTrack = newTrack, newTrack !== currentTrack {
            print("WebRTCVideoView - New track instance received (ID: \(newTrack.trackId)). Updating renderer.")
            // 古いトラックがあればビューから削除
            if let currentTrack = currentTrack {
                print("WebRTCVideoView - Removing old track (ID: \(currentTrack.trackId)) from renderer.")
                currentTrack.remove(uiView)
            }
            // 新しいトラックをビューに追加
            print("WebRTCVideoView - Adding new track (ID: \(newTrack.trackId)) to renderer.")
            newTrack.add(uiView)
            context.coordinator.currentTrack = newTrack // コーディネータのトラックを更新
        }
        // ② 新しいトラックが存在せず (nil)、かつ現在トラックが存在する場合 (トラックが削除された)
        else if newTrack == nil, let currentTrack = currentTrack {
            print("WebRTCVideoView - Track removed (was ID: \(currentTrack.trackId)). Removing from renderer.")
            currentTrack.remove(uiView)
            context.coordinator.currentTrack = nil
        }
        // ③ 新しいトラックが存在し、現在のトラックと同じインスタンスの場合 (再描画など)
        //    念のため、現在のトラックがビューに追加されているか確認する (通常は不要かもしれない)
        else if let newTrack = newTrack, newTrack === currentTrack {
             // ここで特に何かする必要はないはず。すでに addRenderer されている。
             // 必要であれば、状態確認ログを追加
             print("WebRTCVideoView - updateUIView called with the same track (ID: \(newTrack.trackId)). No renderer changes needed.")
        }
         // ④ 新しいトラックも現在のトラックも nil の場合
        //    何もしない
        else if newTrack == nil && currentTrack == nil {
            print("WebRTCVideoView - updateUIView called with no track. No renderer changes needed.")
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
