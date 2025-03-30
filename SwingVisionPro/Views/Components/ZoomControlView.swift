//
//  ZoomControlView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ZoomControlView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    let zoomOptions: [(String, CGFloat)] = [
        ("0.5×", 0.5),
        ("1×", 1.0),
        ("2×", 2.0)
    ]
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<zoomOptions.count, id: \.self) { index in
                let zoomOption = zoomOptions[index]
                let isActive = isActiveZoom(zoomOption.1)
                
                Button(action: {
                    withAnimation {
                        cameraManager.setZoom(factor: zoomOption.1)
                    }
                }) {
                    if isActive {
                        Text(formatZoom(cameraManager.currentZoomFactor))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.yellow)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    } else {
                        Text(zoomOption.0)
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
    
    private func isActiveZoom(_ zoom: CGFloat) -> Bool {
        let currentZoom = cameraManager.currentZoomFactor
        
        if zoom == 0.5 && currentZoom < 0.5 {
            return true
        }
        else if zoom == 0.5 && currentZoom >= 0.5 && currentZoom < 1.0 {
            return true
        }
        else if zoom == 1.0 && currentZoom >= 1.0 && currentZoom < 2.0 {
            return true
        }
        else if zoom == 2.0 && currentZoom >= 2.0 {
            return true
        }
        
        return false
    }

    private func formatZoom(_ zoom: CGFloat) -> String {
        if abs(zoom - 1.0) < 0.05 {
            return "1×"
        } else if abs(zoom - 0.5) < 0.05 {
            return "0.5×"
        } else if abs(zoom - 2.0) < 0.05 {
            return "2×"
        } else {
            return String(format: "%.1f×", zoom)
        }
    }
}
