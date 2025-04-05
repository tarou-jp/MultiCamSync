//
//  DeviceConnectionView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import SwiftUI
import MultipeerConnectivity
import Combine

struct DeviceConnectionView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @Environment(\.presentationMode) var presentationMode
    
    // 監視用のプロパティとタイマー
    @State private var connectedPeers: [MCPeerID] = []
    @State private var discoveredPeers: [MCPeerID] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    private var connectablePeers: [MCPeerID] {
        discoveredPeers.filter {
            !connectedPeers.contains($0)
        }.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationView {
            List {
                // デバイス接続セクション
                Section(header: Text("周辺のデバイス")) {
                    if connectablePeers.isEmpty {
                        HStack {
                            Text("周辺に接続可能なデバイスが見つかりません")
                                .foregroundColor(.gray)
                                .italic()
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        ForEach(connectablePeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                    .padding(.trailing, 5)
                                
                                Text(peer.displayName)
                                
                                Spacer()
                                
                                Button(action: {
                                    appCoordinator.multipeerManager.sendInvite(to: peer)
                                }) {
                                    Text("接続")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                // 接続済みデバイスセクション
                if !connectedPeers.isEmpty {
                    Section(header: Text("接続済みデバイス")) {
                        ForEach(connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone.circle.fill")
                                    .foregroundColor(.green)
                                    .padding(.trailing, 5)
                                
                                Text(peer.displayName)
                                
                                Spacer()
                                
                                // ストリーミング状態を示すアイコン（最小限の表示）
                                if appCoordinator.webRTCManager.isStreaming {
                                    Image(systemName: "video.fill")
                                        .foregroundColor(appCoordinator.webRTCManager.isConnected ? .green : .orange)
                                        .padding(.trailing, 5)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        
                        // 「すべての接続を解除」ボタン
                        Button(action: {
                            appCoordinator.disconnectAllPeers()
                        }) {
                            HStack {
                                Spacer()
                                Text("すべての接続を解除")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 5)
                    }
                }
                
                // アプリ情報セクション
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("デバイスID")
                        Spacer()
                        Text(appCoordinator.multipeerManager.myPeerID.displayName)
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("接続状態")
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(connectedPeers.isEmpty ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            Text(connectedPeers.isEmpty ? "未接続" : "接続中")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("デバイス接続")
            .navigationBarItems(
                trailing: Button("閉じる") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(PlainButtonStyle())
            )
            .onAppear {
                // 初期値を設定
                updateLocalState()
                
                // マルチピア検索と広告を開始
                appCoordinator.multipeerManager.startBrowsing()
                appCoordinator.multipeerManager.startAdvertising()
                
                // connectedPeersの変更を監視
                appCoordinator.multipeerManager.$connectedPeers
                    .receive(on: RunLoop.main)
                    .sink { peers in
                        connectedPeers = peers
                        print("接続済みピア更新: \(peers.map { $0.displayName }.joined(separator: ", "))")
                    }
                    .store(in: &cancellables)
                
                // discoveredPeersの変更を監視
                appCoordinator.multipeerManager.$discoveredPeers
                    .receive(on: RunLoop.main)
                    .sink { peers in
                        discoveredPeers = peers
                        print("発見されたピア更新: \(peers.map { $0.displayName }.joined(separator: ", "))")
                    }
                    .store(in: &cancellables)
                
                // WebRTCManagerの状態変更も監視
                appCoordinator.webRTCManager.objectWillChange
                    .receive(on: RunLoop.main)
                    .sink { _ in
                        print("WebRTCManager状態更新")
                        // 強制的に再描画
                        updateLocalState()
                    }
                    .store(in: &cancellables)
                
                // 1秒ごとの更新タイマー
                Timer.publish(every: 1.0, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        updateLocalState()
                    }
                    .store(in: &cancellables)
            }
            .onDisappear {
                // 購読をキャンセル
                cancellables.forEach { $0.cancel() }
                cancellables.removeAll()
            }
        }
    }
    
    // ローカルの状態変数を更新
    private func updateLocalState() {
        connectedPeers = appCoordinator.multipeerManager.connectedPeers
        discoveredPeers = appCoordinator.multipeerManager.discoveredPeers
    }
}

struct DeviceConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceConnectionView()
            .environmentObject(AppCoordinator(cameraManager: CameraManager(),
                                              multipeerManager: MultipeerManager()))
    }
}
