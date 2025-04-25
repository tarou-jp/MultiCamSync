//
//  ContentView.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var cancellable: AnyCancellable?
    @State private var showInvitationAlert = false
    @State private var currentInvitation: PendingInvitation? = nil
    
    var body: some View {
        ZStack {
            CameraView()
            ControlsView()
            
            if let actionTime = appCoordinator.scheduledActionTime,
               Date().timeIntervalSince1970 < actionTime {
                CountdownBackdropView(targetTime: actionTime)
                    .transition(.opacity)
            }
        }
        .onAppear {
            print("ContentView appeared")
            cancellable = appCoordinator.multipeerManager.$pendingInvitation
                .receive(on: RunLoop.main)
                .sink { invitation in
                    if let invitation = invitation {
                        print("DEBUG: pendingInvitation受信: \(invitation.peerID.displayName)")
                        self.currentInvitation = invitation
                        self.showInvitationAlert = true
                    }
                }
        }
        .onDisappear {
            cancellable?.cancel()
        }
        .alert(isPresented: $showInvitationAlert) {
            if let invitation = currentInvitation {
                if !appCoordinator.multipeerManager.connectedPeers.isEmpty {
                    return Alert(
                        title: Text("接続切替確認"),
                        message: Text("すでに他のデバイスと接続されています。\n\(invitation.peerID.displayName) との接続に切り替えますか？"),
                        primaryButton: .default(Text("切り替える"), action: {
                            appCoordinator.multipeerManager.disconnect()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                appCoordinator.multipeerManager.acceptInvitation(invitation)
                                showInvitationAlert = false
                                currentInvitation = nil
                            }
                        }),
                        secondaryButton: .cancel({
                            appCoordinator.multipeerManager.rejectInvitation(invitation)
                            showInvitationAlert = false
                            currentInvitation = nil
                        })
                    )
                } else {
                    return Alert(
                        title: Text("接続リクエスト"),
                        message: Text("\(invitation.peerID.displayName) から接続要求があります。接続しますか？"),
                        primaryButton: .default(Text("接続する"), action: {
                            appCoordinator.multipeerManager.acceptInvitation(invitation)
                            showInvitationAlert = false
                            currentInvitation = nil
                        }),
                        secondaryButton: .cancel({
                            appCoordinator.multipeerManager.rejectInvitation(invitation)
                            showInvitationAlert = false
                            currentInvitation = nil
                        })
                    )
                }
            } else {
                return Alert(
                    title: Text("エラー"),
                    message: Text("不明なエラーが発生しました"),
                    dismissButton: .default(Text("OK"), action: {
                        showInvitationAlert = false
                    })
                )
            }
        }
    }
}
