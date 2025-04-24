//
//  WebRTCStreamingView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/04.
//

import SwiftUI

struct WebRTCStreamingView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ZStack {
            contentView()
            closeButton()
        }
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    private func contentView() -> some View {
        let tracks = Array(appCoordinator.webRTCManager.remoteVideoTracks)
        if tracks.isEmpty {
            EmptyView()
        }
        else if tracks.count == 1 {
            // シングルビュー
            WebRTCVideoView(videoTrack: tracks[0].value)
        }
        else {
            // 複数ビュー
            if hSizeClass == .regular {
                // iPadなどは並べて表示
                HStack(spacing: 8) {
                    ForEach(tracks, id: \.0) { peer, track in
                        WebRTCVideoView(videoTrack: track)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                // iPhoneなどはページングタブで表示
                TabView {
                    ForEach(tracks, id: \.0) { peer, track in
                        WebRTCVideoView(videoTrack: track)
                            .tag(peer)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            }
        }
    }

    private func closeButton() -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    appCoordinator.webRTCManager.disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding()
            }
            Spacer()
        }
    }
}

struct WebRTCStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        // デモ用にダミーの RTCVideoTrack を挿入してください
        let coord = AppCoordinator(cameraManager: CameraManager(),
                                   multipeerManager: MultipeerManager())
        // coord.webRTCManager.remoteVideoTracks = […]
        return WebRTCStreamingView()
            .environmentObject(coord)
    }
}
