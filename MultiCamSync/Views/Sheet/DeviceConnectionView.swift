//
//  DeviceConnectionView.swift
//  MultiCamSync
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
        discoveredPeers
            .filter { !connectedPeers.contains($0) }
            .sorted { $0.displayName < $1.displayName }
    }
    
    var body: some View {
        NavigationView {
            List {
                // 周辺デバイス セクション
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
                
                // 接続済みデバイス セクション
                if !connectedPeers.isEmpty {
                    Section(header: Text("接続済みデバイス")) {
                        ForEach(connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone.circle.fill")
                                    .foregroundColor(.green)
                                    .padding(.trailing, 5)
                                
                                Text(peer.displayName)
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            
            // 表示時の処理
            .onAppear {
                updateLocalState()
                
                appCoordinator.multipeerManager.startBrowsing()
                appCoordinator.multipeerManager.startAdvertising()
                
                // 接続済みピアの監視
                appCoordinator.multipeerManager.$connectedPeers
                    .receive(on: RunLoop.main)
                    .sink { peers in
                        connectedPeers = peers
                    }
                    .store(in: &cancellables)
                
                // 発見されたピアの監視
                appCoordinator.multipeerManager.$discoveredPeers
                    .receive(on: RunLoop.main)
                    .sink { peers in
                        discoveredPeers = peers
                    }
                    .store(in: &cancellables)
                
                // 1秒ごとにローカルの状態を更新するタイマー
                Timer.publish(every: 1.0, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        updateLocalState()
                    }
                    .store(in: &cancellables)
            }
            // 非表示になったら購読キャンセル
            .onDisappear {
                cancellables.forEach { $0.cancel() }
                cancellables.removeAll()
            }
        }
    }
    
    private func updateLocalState() {
        connectedPeers = appCoordinator.multipeerManager.connectedPeers
        discoveredPeers = appCoordinator.multipeerManager.discoveredPeers
    }
}
