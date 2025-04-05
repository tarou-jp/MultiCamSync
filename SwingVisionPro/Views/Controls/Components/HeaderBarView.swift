//
//  HeaderBar.swift.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI
import MultipeerConnectivity

struct HeaderBarView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var showBroadcastActionSheet = false
    
    var body: some View {
        HStack {
            // 左側のグループ（解像度・FPS）
            HStack(spacing: 8) {
                // 解像度の表示と切り替えボタン
                Button(action: {
                    appCoordinator.cameraManager.switchResolution()
                }) {
                    Text(appCoordinator.cameraManager.currentResolution.rawValue)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
                
                // FPSの表示と切り替えボタン
                Button(action: {
                    appCoordinator.cameraManager.switchFrameRate()
                }) {
                    Text("\(appCoordinator.cameraManager.currentFrameRate.rawValue)fps")
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
                
                // ストリーミング状態表示（配信中／受信中の場合のみ）
                if appCoordinator.webRTCManager.isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appCoordinator.webRTCManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(appCoordinator.webRTCManager.streamingRole == .sender ? "配信中" : "受信中")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                }
            }
            
            Spacer()
            
            // 中央のカメラ切り替えボタン
            Button(action: {
                appCoordinator.cameraManager.switchCamera()
            }) {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // 右側のボタングループ
            HStack(spacing: 12) {
                // 配信モードボタン - このボタンを押すとアクションシートが表示される
                Button(action: {
                    // すでに配信中なら停止、それ以外ならアクションシート表示
                    if appCoordinator.webRTCManager.isStreaming && appCoordinator.webRTCManager.streamingRole == .sender {
                        appCoordinator.stopStreaming()
                    } else {
                        showBroadcastActionSheet = true
                    }
                }) {
                    Image(systemName: appCoordinator.webRTCManager.isStreaming && appCoordinator.webRTCManager.streamingRole == .sender ? "arrow.up.right.video.fill" : "arrow.up.right.video")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
        // 配信先選択アクションシート
        .actionSheet(isPresented: $showBroadcastActionSheet) {
            // 修正: 接続済みのピア (connectedPeers) を使用
            let connectedPeers = appCoordinator.multipeerManager.connectedPeers
                .sorted { $0.displayName < $1.displayName } // 表示順を安定させる

            var buttons: [ActionSheet.Button] = [
                .cancel(Text("キャンセル"))
            ]

            // 修正: 接続済みのピアがいない場合
            if connectedPeers.isEmpty {
                return ActionSheet(
                    title: Text("映像配信"),
                    // 修正: メッセージ
                    message: Text("配信可能な接続済みデバイスが見つかりません。"),
                    buttons: buttons
                )
            }

            // 修正: 接続済みのピア (connectedPeers) を使ってボタンを追加
            for peer in connectedPeers {
                buttons.insert(.default(Text("配信先: \(peer.displayName)")) {
                    // 選択したピアへの配信開始処理
                    appCoordinator.startStreamingAsPublisher(targetPeer: peer)
                }, at: 0)
            }

            return ActionSheet(
                title: Text("映像配信先の選択"),
                message: Text("映像を配信する相手を1人選択してください"),
                buttons: buttons
            )
        }
    }
}

struct HeaderBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            HeaderBarView()
                .environmentObject(AppCoordinator(
                    cameraManager: CameraManager(),
                    multipeerManager: MultipeerManager()
                ))
        }
    }
}
