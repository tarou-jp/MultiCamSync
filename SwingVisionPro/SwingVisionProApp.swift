//
//  SwingVisionProApp.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

@main
struct SwingVisionProApp: App {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var multipeerManager: MultipeerManager
    @StateObject private var syncManager: SyncManager
    @StateObject private var webRTCManager: WebRTCManager

    init() {
        // UIConstants 初期化
        _ = UIConstants.shared

        // StateObject の初期化は init 内で行う
        let camManager = CameraManager()
        let peerManager = MultipeerManager()
        _cameraManager = StateObject(wrappedValue: camManager)
        _multipeerManager = StateObject(wrappedValue: peerManager)
        _syncManager = StateObject(wrappedValue: SyncManager(cameraManager: camManager, multipeerManager: peerManager))
        _webRTCManager = StateObject(wrappedValue: WebRTCManager(multipeerManager: peerManager, cameraManager: camManager))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
                .environmentObject(multipeerManager)
                .environmentObject(syncManager)
                .environmentObject(webRTCManager)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraManager())
        .environmentObject(MultipeerManager())
        .environmentObject(SyncManager(cameraManager: CameraManager(), multipeerManager: MultipeerManager()))
        .environmentObject(WebRTCManager(multipeerManager: MultipeerManager(), cameraManager: CameraManager()))
}
