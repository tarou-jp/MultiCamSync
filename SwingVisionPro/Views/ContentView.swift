//
//  ContentView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var multipeerManager: MultipeerManager
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var webRTCManager: WebRTCManager
    
    var body: some View {
        ZStack {
            // 受信側モードでWebRTCストリーミング中かつビデオトラックが存在する場合
            if webRTCManager.isStreaming && webRTCManager.streamingRole == .receiver,
               let videoTrack = webRTCManager.remoteVideoTrack {
                WebRTCVideoView(videoTrack: videoTrack)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        print("ContentView - WebRTCVideoView appeared with track")
                    }
            } else {
                // 通常のカメラプレビュー
                CameraView()
                    .onAppear {
                        print("ContentView - CameraView appeared")
                    }
            }
            
            // UIコントロール
            ControlsView()
            
            // WebRTC受信モード中のオーバーレイ
            if webRTCManager.isStreaming && webRTCManager.streamingRole == .receiver {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            webRTCManager.disconnect()
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
            }
            
            // WebRTC接続状態デバッグ情報
            VStack {
                if webRTCManager.isStreaming {
                    HStack {
                        Capsule()
                            .fill(webRTCManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(webRTCManager.isConnected ? "WebRTC接続中" : "WebRTC接続待機中")
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        Text(webRTCManager.streamingRole == .sender ? "（送信）" : "（受信）")
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        // ビデオトラック情報
                        if webRTCManager.streamingRole == .receiver {
                            Text(webRTCManager.remoteVideoTrack != nil ? "トラック有" : "トラック無")
                                .font(.caption)
                                .foregroundColor(webRTCManager.remoteVideoTrack != nil ? .green : .red)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(15)
                    .padding()
                }
                
                Spacer()
            }
            
            // 予定されたアクション時刻が設定され、まだその時刻に達していなければバックドロップを表示
            if let actionTime = syncManager.scheduledActionTime,
               Date().timeIntervalSince1970 < actionTime {
                CountdownBackdropView(targetTime: actionTime)
                    .transition(.opacity)
            }
        }
        .alert(item: $multipeerManager.pendingInvitation) { invitation in
            // 接続がすでにある場合は切り替え確認
            if !multipeerManager.connectedPeers.isEmpty {
                return Alert(
                    title: Text("接続切替確認"),
                    message: Text("すでに他のデバイスと接続されています。\n\(invitation.peerID.displayName) との接続に切り替えますか？"),
                    primaryButton: .default(Text("切り替える"), action: {
                        // WebRTC接続を切断
                        if webRTCManager.isStreaming {
                            webRTCManager.disconnect()
                        }
                        
                        multipeerManager.disconnect()
                        // 少し待ってから新しい接続を受け入れる
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            multipeerManager.acceptInvitation(invitation)
                        }
                    }),
                    secondaryButton: .cancel({
                        multipeerManager.rejectInvitation(invitation)
                    })
                )
            } else {
                // 接続がない場合は単純に接続確認
                return Alert(
                    title: Text("接続リクエスト"),
                    message: Text("\(invitation.peerID.displayName) から接続要求があります。接続しますか？"),
                    primaryButton: .default(Text("接続する"), action: {
                        multipeerManager.acceptInvitation(invitation)
                    }),
                    secondaryButton: .cancel({
                        multipeerManager.rejectInvitation(invitation)
                    })
                )
            }
        }
        .onDisappear {
            // ビューが消える時にストリーミングを停止
            if webRTCManager.isStreaming {
                webRTCManager.disconnect()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CameraManager())
            .environmentObject(MultipeerManager())
            .environmentObject(SyncManager(cameraManager: CameraManager(), multipeerManager: MultipeerManager()))
            .environmentObject(WebRTCManager(multipeerManager: MultipeerManager(), cameraManager: CameraManager()))
    }
}
