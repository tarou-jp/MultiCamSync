//
//  FooterBar.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct FooterBarView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        HStack {
            // アルバムボタン
            Button(action: {
                // アルバムを開く処理
            }) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .cornerRadius(5)
            }
            
            Spacer()
            
            // 録画ボタン - 直接cameraManagerを操作
            Button(action: {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                } else {
                    cameraManager.startRecording()
                }
            }) {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .fill(cameraManager.isRecording ? Color.red : Color.white)
                            .frame(width: 60, height: 60)
                    )
            }
            
            Spacer()
            
            // デバイス接続ボタン
            Button(action: {
                // デバイス接続処理
            }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, UIConstants.shared.bottomPadding) // 下部の固定余白分だけパディングを追加
    }
}
