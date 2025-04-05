//
//  FooterBar.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct FooterBarView: View {
    // 複数の manager を統合した AppCoordinator を環境オブジェクトとして利用
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var isShowingDeviceConnectionView = false

    var body: some View {
        HStack {
            // アルバムボタン（元々のRectangleをそのまま維持）
            Button(action: {
                // アルバムを開く処理
            }) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .cornerRadius(5)
            }
            
            Spacer()
            
            // 録画ボタン（録画中なら requestStopRecording、未録画なら requestStartRecording を実行）
            Button(action: {
                if appCoordinator.cameraManager.isRecording {
                    appCoordinator.requestStopRecording()
                } else {
                    appCoordinator.requestStartRecording()
                }
            }) {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .fill(appCoordinator.cameraManager.isRecording ? Color.red : Color.white)
                            .frame(width: 60, height: 60)
                    )
            }
            
            Spacer()
            
            // デバイス接続ボタン
            Button(action: {
                isShowingDeviceConnectionView = true
            }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, UIConstants.shared.bottomPadding)
        .sheet(isPresented: $isShowingDeviceConnectionView) {
            DeviceConnectionView()
        }
    }
}

struct FooterBarView_Previews: PreviewProvider {
    static var previews: some View {
        FooterBarView()
            .environmentObject(AppCoordinator(cameraManager: CameraManager(), multipeerManager: MultipeerManager()))
    }
}
