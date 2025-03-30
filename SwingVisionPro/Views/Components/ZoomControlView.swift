//
//  ZoomControlView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ZoomControlView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    // ズームオプション
    let zoomOptions = ["0.5x", "1.0x", "2x", "3x"]
    
    var body: some View {
        VStack {
            // ズームオプションボタン
            HStack(spacing: 15) {
                ForEach(zoomOptions, id: \.self) { zoom in
                    Button(action: {
                        withAnimation {
                            switch zoom {
                            case "0.5x": cameraManager.setZoom(factor: 0.5)
                            case "1.0x": cameraManager.setZoom(factor: 1.0)
                            case "2x": cameraManager.setZoom(factor: 2.0)
                            case "3x": cameraManager.setZoom(factor: 3.0)
                            default: cameraManager.setZoom(factor: 1.0)
                            }
                        }
                    }) {
                        Text(zoom)
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                zoom == getZoomText(cameraManager.currentZoomFactor)
                                    ? Color.white.opacity(0.3)
                                    : Color.black.opacity(0.5)
                            )
                            .cornerRadius(15)
                    }
                }
            }
            .padding(.vertical, 5)
            
            // ズームスライダー
            HStack {
                Button(action: {
                    let newZoom = max(0.5, cameraManager.currentZoomFactor - 0.1)
                    cameraManager.setZoom(factor: newZoom)
                }) {
                    Image(systemName: "minus")
                        .foregroundColor(.white)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(cameraManager.currentZoomFactor) },
                        set: { cameraManager.setZoom(factor: CGFloat($0)) }
                    ),
                    in: 0.5...3.0
                )
                .accentColor(.white)
                
                Button(action: {
                    let newZoom = min(3.0, cameraManager.currentZoomFactor + 0.1)
                    cameraManager.setZoom(factor: newZoom)
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal)
            .frame(width: 250)
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(20)
        .padding()
    }
    
    // ズームレベルをテキストに変換
    private func getZoomText(_ zoom: CGFloat) -> String {
        if zoom <= 0.5 { return "0.5x" }
        else if zoom <= 1.0 { return "1.0x" }
        else if zoom <= 2.0 { return "2x" }
        else { return "3x" }
    }
}
