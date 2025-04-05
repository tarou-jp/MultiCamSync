//
//  WebRTCStreamingView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/04.

import SwiftUI

struct WebRTCStreamingView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    
    var body: some View {
        ZStack {
            if let videoTrack = appCoordinator.webRTCManager.remoteVideoTrack {
                WebRTCVideoView(videoTrack: videoTrack)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            appCoordinator.webRTCManager.disconnect()
                        }) {
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
            } else {
                EmptyView()
            }
        }
    }
}

struct WebRTCStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        WebRTCStreamingView()
            .environmentObject(AppCoordinator(cameraManager: CameraManager(),
                                             multipeerManager: MultipeerManager()))
    }
}
