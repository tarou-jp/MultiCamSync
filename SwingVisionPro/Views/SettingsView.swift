//
//  SettingsView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import SwiftUI
import MultipeerConnectivity

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var multipeerManager: MultipeerManager
    @EnvironmentObject var webRTCManager: WebRTCManager
    
    @State private var showDeviceSelection = false
    
    var body: some View {
        NavigationView {
            List {
                // 接続セクション
                Section(header: Text("接続")) {
                    // デバイス検索ボタン
                    Button(action: {
                        showDeviceSelection = true
                    }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("デバイスを検索")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 接続済みデバイス一覧
                    if !multipeerManager.connectedPeers.isEmpty {
                        ForEach(multipeerManager.connectedPeers) { peer in
                            HStack {
                                Text(peer.displayName)
                                Spacer()
                                
                                // ストリーミング状態を示すアイコン
                                if webRTCManager.isStreaming {
                                    Image(systemName: "video.fill")
                                        .foregroundColor(webRTCManager.isConnected ? .green : .orange)
                                }
                                
                                // 接続解除ボタン
                                Button(action: {
                                    if webRTCManager.isStreaming {
                                        webRTCManager.disconnect()
                                    }
                                    multipeerManager.session.disconnect()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    } else {
                        Text("接続されているデバイスはありません")
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
                
                // WebRTCストリーミングセクション
                Section(header: Text("WebRTCストリーミング")) {
                    if !multipeerManager.connectedPeers.isEmpty {
                        if webRTCManager.isStreaming {
                            Button(action: {
                                webRTCManager.disconnect()
                            }) {
                                HStack {
                                    Image(systemName: "stop.circle")
                                    Text("ストリーミングを停止")
                                    Spacer()
                                }
                                .foregroundColor(.red)
                            }
                            
                            HStack {
                                Text("状態")
                                Spacer()
                                Text(webRTCManager.isConnected ? "接続中" : "接続待機中")
                                    .foregroundColor(webRTCManager.isConnected ? .green : .orange)
                            }
                            
                            HStack {
                                Text("役割")
                                Spacer()
                                Text(webRTCManager.streamingRole == .sender ? "送信側" : "受信側")
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Button(action: {
                                webRTCManager.startCall(as: .sender)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.circle")
                                    Text("映像を配信する")
                                    Spacer()
                                }
                            }
                            
                            Button(action: {
                                webRTCManager.startCall(as: .receiver)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("映像を受信する")
                                    Spacer()
                                }
                            }
                        }
                    } else {
                        Text("ストリーミングにはデバイス接続が必要です")
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
                
                // アプリ情報セクション
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("デバイスID")
                        Spacer()
                        Text(multipeerManager.myPeerID.displayName)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("設定")
            .navigationBarItems(trailing: Button("閉じる") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(isPresented: $showDeviceSelection) {
                DeviceSelectionView(multipeerManager: multipeerManager)
            }
        }
    }
}

// デバイス選択ビュー
struct DeviceSelectionView: View {
    @ObservedObject var multipeerManager: MultipeerManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if multipeerManager.discoveredPeers.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Text("近くのデバイスを検索中...")
                        Spacer()
                    }
                } else {
                    List {
                        Section(header: Text("検出されたデバイス")) {
                            ForEach(multipeerManager.discoveredPeers) { peer in
                                Button(action: {
                                    multipeerManager.sendInvite(to: peer)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    HStack {
                                        Text(peer.displayName)
                                        Spacer()
                                        Image(systemName: "link")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        if !multipeerManager.connectedPeers.isEmpty {
                            Section(header: Text("接続済みデバイス")) {
                                ForEach(multipeerManager.connectedPeers) { peer in
                                    HStack {
                                        Text(peer.displayName)
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("デバイス検索")
            .navigationBarItems(trailing: Button("閉じる") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                // セッションが開始していない場合は開始
                multipeerManager.startBrowsing()
                multipeerManager.startAdvertising()
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(MultipeerManager())
            .environmentObject(WebRTCManager(multipeerManager: MultipeerManager(), cameraManager: CameraManager()))
    }
}
