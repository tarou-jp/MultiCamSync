//
//  MultiCamSyncApp.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

@main
struct MultiCamSyncApp: App {
    @StateObject private var appCoordinator: AppCoordinator

    init() {
        _ = UIConstants.shared
        
        let cameraManager = CameraManager()
        let multipeerManager = MultipeerManager()
        _appCoordinator = StateObject(wrappedValue: AppCoordinator(cameraManager: cameraManager, multipeerManager: multipeerManager))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appCoordinator)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppCoordinator(cameraManager: CameraManager(), multipeerManager: MultipeerManager()))
}
