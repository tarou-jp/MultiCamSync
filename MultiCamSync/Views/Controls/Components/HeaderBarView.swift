//
//  HeaderBar.swift.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI
import MultipeerConnectivity

struct HeaderBarView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    
    @State private var showDeviceConnectionSheet = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Button(action: {
                    appCoordinator.cameraManager.switchResolution()
                }) {
                    Text(appCoordinator.cameraManager.currentResolution.rawValue)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
                
                Button(action: {
                    appCoordinator.cameraManager.switchFrameRate()
                }) {
                    Text("\(appCoordinator.cameraManager.currentFrameRate.rawValue)fps")
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                
                Button(action: {
                    showDeviceConnectionSheet = true
                }) {
                    Image(systemName: "network")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
        .frame(height: 0)
        
        // MARK: デバイス接続シート
        .sheet(isPresented: $showDeviceConnectionSheet) {
            DeviceConnectionView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
