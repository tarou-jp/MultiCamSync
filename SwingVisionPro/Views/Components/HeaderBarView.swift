//
//  HeaderBar.swift.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct HeaderBarView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var webRTCManager: WebRTCManager
    @State private var showSettings = false
    
    var body: some View {
        HStack {
            // 解像度の表示と切り替えボタン
            Button(action: {
                // タップするごとに switchResolution() で切り替え
                cameraManager.switchResolution()
            }) {
                Text(cameraManager.currentResolution.rawValue)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
            }
            
            // FPSの表示と切り替えボタン
            Button(action: {
                cameraManager.switchFrameRate()
            }) {
                Text("\(cameraManager.currentFrameRate.rawValue)fps")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
            }
            
            // ストリーミング状態表示（配信中のみ表示）
            if webRTCManager.isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(webRTCManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(webRTCManager.streamingRole == .sender ? "配信中" : "受信中")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
            }
            
            Spacer()
            
            // カメラ切り替え
            Button(action: {
                cameraManager.switchCamera()
            }) {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            // 設定ボタン
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
        .frame(height: 0) // ignoreSafeAreaをつけているようなもん。ライフハックだよね~。消しじゃダメです。
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

struct HeaderBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            HeaderBarView()
        }
        .environmentObject(CameraManager())
        .environmentObject(WebRTCManager(multipeerManager: MultipeerManager(), cameraManager: CameraManager()))
    }
}
