//
//  DeviceConnectionView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import SwiftUI
import MultipeerConnectivity

struct DeviceConnectionView: View {
    @EnvironmentObject private var multipeerManager: MultipeerManager
    
    var body: some View {
        NavigationView {
            VStack {
                if multipeerManager.discoveredPeers.isEmpty {
                    Text("周辺のデバイスが見つかりません")
                        .padding()
                } else {
                    List {
                        Section(header: Text("周辺デバイス")) {
                            ForEach(multipeerManager.discoveredPeers.filter { discovered in
                                !multipeerManager.connectedPeers.contains { connected in
                                    discovered.displayName == connected.displayName
                                }
                            }, id: \.displayName) { peer in
                                HStack {
                                    Text(peer.displayName)
                                    Spacer()
                                    Button(action: {
                                        multipeerManager.sendInvite(to: peer)
                                    }) {
                                        Text("接続")
                                            .foregroundColor(.blue)
                                            .padding(.horizontal)
                                            .padding(.vertical, 5)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                        }
                        
                        // 接続済みのデバイスセクション
                        if !multipeerManager.connectedPeers.isEmpty {
                            Section(header: Text("接続済みデバイス")) {
                                ForEach(multipeerManager.connectedPeers, id: \.displayName) { peer in
                                    HStack {
                                        Text(peer.displayName)
                                        Spacer()
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    // 接続があれば、すべて切断するボタンを表示
                    if !multipeerManager.connectedPeers.isEmpty {
                        Button(action: {
                            multipeerManager.disconnect()
                        }) {
                            Text("すべての接続を解除")
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                }
                
                Spacer()
                
                // 状態表示エリア
                VStack(alignment: .leading, spacing: 10) {
                    Text("現在の状態:")
                        .font(.headline)
                    
                    Text("デバイスID: \(multipeerManager.myPeerID.displayName)")
                    
                    Text("接続数: \(multipeerManager.connectedPeers.count)")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
            .navigationTitle("デバイス接続")
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

struct DeviceConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceConnectionView()
            .environmentObject(MultipeerManager())
    }
}
