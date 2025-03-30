//
//  HeaderBar.swift.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct HeaderBarView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("1920×1080")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                
                Text("60fps")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                
                Spacer()
                
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
                    // 設定画面を開く処理（モック）
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
        }
        .frame(height: 0)
    }
}
