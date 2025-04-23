//
//  BroadcastSelectionSheetView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/07.
//

import SwiftUI
import MultipeerConnectivity

struct BroadcastSelectionSheetView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("配信先を選択").font(.subheadline)) {
                    let connectedPeers = appCoordinator.multipeerManager.connectedPeers
                        .sorted { $0.displayName < $1.displayName }
                    
                    if connectedPeers.isEmpty {
                        Text("配信可能な接続済みデバイスが見つかりません")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(connectedPeers, id: \.self) { peer in
                            Button(action: {
                                appCoordinator.startStreamingAsPublisher(targetPeer: peer)
                                dismiss() // 選んだらシートを閉じる
                            }) {
                                Text("配信先: \(peer.displayName)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("映像配信")
            .navigationBarTitleDisplayMode(.inline)
            // iOS16以上であれば .toolbarColorScheme(.dark, for: .navigationBar) などで色指定可
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}
