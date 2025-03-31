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
    
    var body: some View {
        ZStack {

            // カメラプレビュー
            CameraView()
            
            // UIコントロール
            ControlsView()
            
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CameraManager())
            .environmentObject(MultipeerManager())
    }
}
