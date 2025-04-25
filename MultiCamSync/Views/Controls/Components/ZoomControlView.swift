//
//  ZoomControlView.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ZoomControlView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    
    // ズーム候補のタプル配列 - 0.5xを含める
    let zoomOptions: [(String, CGFloat)] = [
        ("0.5×", 0.5),
        ("1×", 1.0),
        ("2×", 2.0)
    ]
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(zoomOptions.enumerated()), id: \.offset) { (index, zoomOption) in
                let (label, factor) = zoomOption
                let isActive = isActiveZoom(factor)
                
                Button(action: {
                    withAnimation {
                        appCoordinator.cameraManager.setZoom(factor: factor)
                    }
                }) {
                    if isActive {
                        // 現在のズーム値と同じ/近い場合
                        Text(formatZoom(appCoordinator.cameraManager.currentZoomFactor))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.yellow)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    } else {
                        // 他のズーム値
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
        .padding(.bottom, 30)
    }
    
    /// 現在のズーム値が、引数で指定したズーム値のレンジにあるかどうかを判定
    private func isActiveZoom(_ zoom: CGFloat) -> Bool {
        let displayZoom = appCoordinator.cameraManager.displayZoomFactor
        
        // ズーム範囲の判定ロジック
        if zoom == 0.5 && displayZoom >= 0.5 && displayZoom < 1.0 {
            return true
        } else if zoom == 1.0 && displayZoom >= 1.0 && displayZoom < 2.0 {
            return true
        } else if zoom == 2.0 && displayZoom >= 2.0 {
            return true
        }
        
        return false
    }
    
    // ズーム値を文字列表示用にフォーマット
    private func formatZoom(_ zoom: CGFloat) -> String {
        // 注意: ここでは表示用ズーム値を使用する
        let displayZoom = appCoordinator.cameraManager.displayZoomFactor
        
        // 標準プリセットに近い値の場合はそのまま表示
        if abs(displayZoom - 1.0) < 0.05 {
            return "1×"
        } else if abs(displayZoom - 0.5) < 0.05 {
            return "0.5×"
        } else if abs(displayZoom - 2.0) < 0.05 {
            return "2×"
        } else if displayZoom >= 10.0 {
            return String(format: "%.0f×", displayZoom)
        } else if displayZoom >= 2.0 {
            return String(format: "%.1f×", displayZoom)
        } else {
            return String(format: "%.1f×", displayZoom)
        }
    }
}

struct ZoomControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZoomControlView()
            .environmentObject(
                AppCoordinator(
                    cameraManager: CameraManager(),
                    multipeerManager: MultipeerManager()
                )
            )
    }
}
