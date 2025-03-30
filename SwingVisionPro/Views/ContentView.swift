//
//  ContentView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraView()
            
            // UIコントロール
            ControlsView()
        }
    }
}
