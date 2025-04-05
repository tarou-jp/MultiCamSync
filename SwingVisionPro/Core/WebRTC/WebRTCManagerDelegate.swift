//
//  WebRTCManagerDelegate.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import WebRTC
import Combine
import AVFoundation
import MultipeerConnectivity

// WebRTCManagerデリゲートプロトコル
protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool)
    func webRTCManagerDidReceiveRemoteVideoTrack(_ manager: WebRTCManager, track: RTCVideoTrack?)
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessage message: Data, targetPeer: MCPeerID?)
}

// オプショナルメソッドを提供するデフォルト実装
extension WebRTCManagerDelegate {
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool) {}
    func webRTCManagerDidReceiveRemoteVideoTrack(_ manager: WebRTCManager, track: RTCVideoTrack?) {}
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessage message: Data, targetPeer: MCPeerID?) {}
}
