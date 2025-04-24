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

// WebRTCManagerDelegate.swift に追加
protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool)
    func webRTCManagerDidReceiveRemoteVideoTrack(_ manager: WebRTCManager, track: RTCVideoTrack?)
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessage message: Data, targetPeer: MCPeerID?)
    
    // 新しいメソッド
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessageWithAck message: Data, targetPeer: MCPeerID?, completion: @escaping (Bool) -> Void)
    func webRTCManager(_ manager: WebRTCManager, didFailWithTimeout peer: MCPeerID)
    func webRTCManager(_ manager: WebRTCManager, connectionDidFail peer: MCPeerID, canRetry: Bool)
    func webRTCManager(_ manager: WebRTCManager, didUpdateConnectionStatus status: [MCPeerID: ConnectionStatus])
}

// オプショナルメソッドのデフォルト実装
extension WebRTCManagerDelegate {
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool) {}
    func webRTCManagerDidReceiveRemoteVideoTrack(_ manager: WebRTCManager, track: RTCVideoTrack?) {}
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessage message: Data, targetPeer: MCPeerID?) {}
    
    // 新しいメソッドのデフォルト実装
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessageWithAck message: Data, targetPeer: MCPeerID?, completion: @escaping (Bool) -> Void) {
        // デフォルトではACKなしでメッセージを送信し、成功を返す
        self.webRTCManager(manager, needsToSendSignalingMessage: message, targetPeer: targetPeer)
        completion(true)
    }
    func webRTCManager(_ manager: WebRTCManager, didFailWithTimeout peer: MCPeerID) {}
    func webRTCManager(_ manager: WebRTCManager, connectionDidFail peer: MCPeerID, canRetry: Bool) {}
    func webRTCManager(_ manager: WebRTCManager, didUpdateConnectionStatus status: [MCPeerID: ConnectionStatus]) {}
}
