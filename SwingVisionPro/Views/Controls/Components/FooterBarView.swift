//
//  FooterBarView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct FooterBarView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    
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
            
            // 録画ボタン
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
            
            // 右側のボタン: カメラ向き変更（ヘッダーから移動）
            Button(action: {
                appCoordinator.cameraManager.switchCamera()
            }) {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, UIConstants.shared.bottomPadding)
    }
}

struct FooterBarView_Previews: PreviewProvider {
    static var previews: some View {
        FooterBarView()
            .environmentObject(
                AppCoordinator(cameraManager: CameraManager(),
                               multipeerManager: MultipeerManager())
            )
    }
}
