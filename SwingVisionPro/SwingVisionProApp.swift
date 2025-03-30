//
//  SwingVisionProApp.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

@main
struct SwingVisionProApp: App {
    @StateObject private var cameraManager = CameraManager()
    
    init() {
        _ = UIConstants.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
        }
    }
}

#Preview {
    ContentView()
}
