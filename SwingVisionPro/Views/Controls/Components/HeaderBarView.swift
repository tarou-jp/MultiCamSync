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
    
    // どのシートを表示しているかを管理するためのフラグ
    @State private var showBroadcastSheet = false
    @State private var showDeviceConnectionSheet = false
    
    var body: some View {
        HStack {
            // 左側（解像度・FPS・ストリーミング状態）
            HStack(spacing: 8) {
                // 解像度切り替え
                Button(action: {
                    appCoordinator.cameraManager.switchResolution()
                }) {
                    Text(appCoordinator.cameraManager.currentResolution.rawValue)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
                
                // FPS切り替え
                Button(action: {
                    appCoordinator.cameraManager.switchFrameRate()
                }) {
                    Text("\(appCoordinator.cameraManager.currentFrameRate.rawValue)fps")
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
                
                // ストリーミング状態表示（配信/受信）
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
            
            // 右側のボタングループ
            HStack(spacing: 12) {
                // 配信ボタン
                Button(action: {
                    // すでに配信中なら停止、それ以外ならシートを表示
                    if appCoordinator.webRTCManager.isStreaming && appCoordinator.webRTCManager.streamingRole == .sender {
                        appCoordinator.stopStreaming()
                    } else {
                        showBroadcastSheet = true
                    }
                }) {
                    Image(systemName: appCoordinator.webRTCManager.isStreaming && appCoordinator.webRTCManager.streamingRole == .sender
                          ? "dot.radiowaves.up.forward"
                          : "dot.radiowaves.up.forward")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                // デバイス接続ボタン
                Button(action: {
                    showDeviceConnectionSheet = true
                }) {
                    Image(systemName: "network")
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
        
        // MARK: 配信先選択シート
        .sheet(isPresented: $showBroadcastSheet) {
            BroadcastSelectionSheetView(appCoordinator: appCoordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        
        // MARK: デバイス接続シート
        .sheet(isPresented: $showDeviceConnectionSheet) {
            DeviceConnectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

