//
//  AppCoordinator.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import MultipeerConnectivity
import WebRTC
import Combine
import SwiftUI

class AppCoordinator: NSObject, ObservableObject, CameraManagerDelegate, MultipeerManagerDelegate, WebRTCManagerDelegate {
    // MARK: - Published Properties

    @Published var cameraManager: CameraManager
    @Published var multipeerManager: MultipeerManager
    @Published var webRTCManager: WebRTCManager
    
    // 同期関連の状態と機能
    @Published var scheduledActionTime: TimeInterval?
    
    // 接続の状態を追跡
    @Published var connectionStatus: [MCPeerID: ConnectionStatus] = [:]

    // MARK: - 初期化

    init(cameraManager: CameraManager, multipeerManager: MultipeerManager) {
        self.cameraManager = cameraManager
        self.multipeerManager = multipeerManager

        // WebRTCManagerの初期化（CameraManager を渡さない）
        self.webRTCManager = WebRTCManager()

        super.init()

        // 各マネージャーのデリゲート設定
        cameraManager.delegate = self
        multipeerManager.delegate = self
        webRTCManager.delegate = self
        
        // 接続の健全性チェックを開始
        webRTCManager.startConnectionHealthCheck()
    }

    deinit {
        // リソースの解放
        webRTCManager.disconnect()
        webRTCManager.stopConnectionHealthCheck()
    }
    
    
    // MARK: - 同期関連メソッド
    
    func requestStartRecording() {
        if webRTCManager.isStreaming && webRTCManager.streamingRole == .receiver {
            print("AppCoordinator: Receiver mode — recording disabled")
            return
        }
        
        let delay: TimeInterval = 5.0
        let startTime = Date().timeIntervalSince1970 + delay
        scheduledActionTime = startTime
        
        let message = PeerMessage(
            type: .startRecording,
            sender: multipeerManager.myPeerID.displayName,
            payload: "\(startTime)"
        )
        
        sendMessageToPeers(message: message)
        scheduleLocalRecording(startTime: startTime)
    }
    
    func requestStopRecording() {
        if webRTCManager.isStreaming && webRTCManager.streamingRole == .receiver {
            print("AppCoordinator: Receiver mode — stop-recording disabled")
            return
        }
        
        let delay: TimeInterval = 5.0
        let stopTime = Date().timeIntervalSince1970 + delay
        scheduledActionTime = stopTime
        
        let message = PeerMessage(
            type: .stopRecording,
            sender: multipeerManager.myPeerID.displayName,
            payload: "\(stopTime)"
        )
        
        sendMessageToPeers(message: message)
        scheduleLocalStopRecording(stopTime: stopTime)
    }
    
    private func sendMessageToPeers(message: PeerMessage) {
        if multipeerManager.connectedPeers.isEmpty {
            print("AppCoordinator: No connected peers")
            return
        }
        
        // 確認応答が必要なメッセージタイプの場合
        if [PeerMessageType.webrtcOffer, .webrtcAnswer, .webrtcCandidate, .webrtcBye].contains(message.type) {
            for peer in multipeerManager.connectedPeers {
                multipeerManager.sendMessageWithAcknowledgment(message, to: peer) { success in
                    if !success {
                        print("AppCoordinator: Failed to send message to \(peer.displayName), will retry automatically")
                    }
                }
            }
        } else {
            // 通常のメッセージ
            multipeerManager.sendMessage(message, toPeers: multipeerManager.connectedPeers)
        }
    }
    
    private func scheduleLocalRecording(startTime: TimeInterval) {
        let delay = max(startTime - Date().timeIntervalSince1970, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if !self.cameraManager.isRecording {
                self.cameraManager.startRecording()
                print("AppCoordinator: Local recording started at \(startTime)")
            }
        }
    }
    
    private func scheduleLocalStopRecording(stopTime: TimeInterval) {
        let delay = max(stopTime - Date().timeIntervalSince1970, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.cameraManager.isRecording {
                self.cameraManager.stopRecording()
                print("AppCoordinator: Local recording stopped at \(stopTime)")
            }
        }
    }
    
    private func processSyncMessage(_ message: PeerMessage) {
        if webRTCManager.isStreaming && webRTCManager.streamingRole == .receiver {
            print("AppCoordinator: Receiver mode — sync message ignored (\(message.type))")
            return
        }
        
        switch message.type {
        case .startRecording:
            if let payload = message.payload, let startTime = TimeInterval(payload) {
                scheduledActionTime = startTime
                scheduleLocalRecording(startTime: startTime)
            }
        case .stopRecording:
            if let payload = message.payload, let stopTime = TimeInterval(payload) {
                scheduledActionTime = stopTime
                scheduleLocalStopRecording(stopTime: stopTime)
            }
        default:
            break
        }
    }
    
    func startStreamingAsPublisher(targetPeer: MCPeerID) {
        print("AppCoordinator: 送信側として映像配信を開始 - 配信先: \(targetPeer.displayName)")
        webRTCManager.startCall(as: .sender, targetPeers: [targetPeer])
    }
    
    /// ストリーミングを停止する
    func stopStreaming() {
        webRTCManager.disconnect()
    }
    
    // 修正: disconnectAllPeers を disconnect にリネーム (またはそのまま残す)
    func disconnectAllPeers() {
        print("AppCoordinator: Disconnecting from all peers")
        // ストリーミング中ならWebRTCを切断
        if webRTCManager.isStreaming {
            webRTCManager.disconnect()
        }
        // Multipeer接続を解除
        multipeerManager.disconnect()
        
        // UI更新をトリガー
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 診断レポートを生成
    func generateConnectionDiagnostics() -> String {
        return webRTCManager.diagnoseConnectionStatus()
    }
}


// MARK: - CameraManagerDelegate
extension AppCoordinator /* : CameraManagerDelegate */ {
    func cameraManagerDidStartRecording(_ manager: CameraManager, at url: URL) {
        print("AppCoordinator: Camera recording started at \(url)")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidFinishRecording(_ manager: CameraManager, to url: URL) {
        print("AppCoordinator: Camera recording finished to \(url)")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidFailRecording(_ manager: CameraManager, with error: Error) {
        print("AppCoordinator: Camera recording failed: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidChangeAuthorizationStatus(_ manager: CameraManager, isAuthorized: Bool) {
        print("AppCoordinator: Camera authorization status changed: \(isAuthorized)")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidUpdateAvailableSettings(_ manager: CameraManager) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidChangeZoomFactor(_ manager: CameraManager, to factor: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidUpdateSettings(_ manager: CameraManager, resolution: CameraResolution, frameRate: CameraFrameRate) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // ビデオフレームをWebRTCManagerに転送
    func cameraManager(_ manager: CameraManager, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
        if webRTCManager.isStreaming && webRTCManager.streamingRole == .sender {
            webRTCManager.processCameraFrame(sampleBuffer)
        }
    }
}

// MARK: - MultipeerManagerDelegate
extension AppCoordinator /* : MultipeerManagerDelegate */ {
    func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID) {
        switch message.type {
        case .startRecording, .stopRecording:
            processSyncMessage(message)
        
        case .webrtcOffer, .webrtcAnswer, .webrtcCandidate, .webrtcBye:
            if let payload = message.payload,
               let data = Data(base64Encoded: payload) {
                 if let webrtcMsg = try? JSONDecoder().decode(WebRTCSignalingMessage.self, from: data) {
                     webRTCManager.processDecodedSignalingMessage(webrtcMsg, from: peerID)
                 } else {
                     print("AppCoordinator: Failed to decode WebRTCSignalingMessage from payload.")
                 }
            } else {
                 print("AppCoordinator: Failed to decode Base64 payload for WebRTC message.")
            }
            
        case .acknowledgment:
            print("AppCoordinator: Received acknowledgment from \(peerID.displayName)")
            // ここでは何もしない。MultipeerManager内部で処理される
            
        default:
            print("AppCoordinator: Received unhandled message type \(message.type)")
            break
        }
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 新しいメソッド：確認応答を受信したときの処理
    func multipeerManager(_ manager: MultipeerManager, didReceiveAcknowledgment messageID: String, fromPeer peerID: MCPeerID) {
        print("AppCoordinator: Received acknowledgment for message \(messageID) from \(peerID.displayName)")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 新しいメソッド：メッセージ送信に失敗したときの処理
    func multipeerManager(_ manager: MultipeerManager, didFailToSendMessage message: PeerMessage, toPeer peerID: MCPeerID, afterRetries retries: Int) {
        print("AppCoordinator: Failed to send message of type \(message.type) to \(peerID.displayName) after \(retries) retries")
        
        // WebRTC関連のメッセージであれば、接続状態を更新
        if [PeerMessageType.webrtcOffer, .webrtcAnswer, .webrtcCandidate, .webrtcBye].contains(message.type) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 接続問題を通知
                if self.webRTCManager.isStreaming {
                    print("AppCoordinator: WebRTC signaling failed, this may affect streaming quality")
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func multipeerManager(_ manager: MultipeerManager, didChangePeerConnectionState peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func multipeerManager(_ manager: MultipeerManager, didReceiveInvitationFromPeer peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func multipeerManager(_ manager: MultipeerManager, didFindPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func multipeerManager(_ manager: MultipeerManager, didLosePeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
}

// MARK: - WebRTCManagerDelegate
extension AppCoordinator /* : WebRTCManagerDelegate */ {
    
    // MARK: - WebRTCManagerDelegate
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool) {
        print("AppCoordinator: WebRTC connection state changed to \(isConnected) (role=\(manager.streamingRole))")

        switch manager.streamingRole {
        case .receiver:
            if isConnected {
                // 接続成功 → カメラ停止
                cameraManager.pauseCaptureSession()
            } else {
                // 切断・失敗時は、リモート映像トラックが完全になくなったタイミングで戻す
                if manager.remoteVideoTracks.isEmpty {
                    print("AppCoordinator: 完全切断判定。受信モード解除します。")
                    manager.streamingRole = .none
                    manager.isStreaming = false
                    cameraManager.resumeCaptureSession()
                } else {
                    print("AppCoordinator: 切断を検知したけどまだトラックが残ってるのでモード継続")
                }
            }

        case .sender:
            // 送信中はここでは制御せず stopStreaming() 呼び出しで扱う
            break

        default:
            break
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func webRTCManagerDidReceiveRemoteVideoTrack(_ manager: WebRTCManager, track: RTCVideoTrack?) {
        print("AppCoordinator: WebRTC remote video track set")
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessage message: Data, targetPeer: MCPeerID?) {
        guard let signalingMessage = try? JSONDecoder().decode(WebRTCSignalingMessage.self, from: message) else {
            print("AppCoordinator: Failed to decode WebRTCSignalingMessage for determining PeerMessage type.")
            return
        }
        
        let messageType: PeerMessageType
        switch signalingMessage.type {
        case .offer: messageType = .webrtcOffer
        case .answer: messageType = .webrtcAnswer
        case .candidate: messageType = .webrtcCandidate
        case .bye: messageType = .webrtcBye
        }
        
        let payloadString = message.base64EncodedString()
        
        // messageIDを取得（あれば）
        let peerMessage = PeerMessage(
            type: messageType,
            sender: multipeerManager.myPeerID.displayName,
            payload: payloadString,
            messageID: signalingMessage.messageID
        )
        
        if let targetPeer = targetPeer {
            print("AppCoordinator: Sending signaling message to specific peer: \(targetPeer.displayName)")
            multipeerManager.sendMessage(peerMessage, toPeers: [targetPeer])
        } else {
            print("AppCoordinator: Broadcasting signaling message to all peers")
            multipeerManager.sendMessage(peerMessage, toPeers: multipeerManager.connectedPeers)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 新しいメソッド：確認応答付きのシグナリングメッセージを送信
    func webRTCManager(_ manager: WebRTCManager, needsToSendSignalingMessageWithAck message: Data, targetPeer: MCPeerID?, completion: @escaping (Bool) -> Void) {
        guard let signalingMessage = try? JSONDecoder().decode(WebRTCSignalingMessage.self, from: message) else {
            print("AppCoordinator: Failed to decode WebRTCSignalingMessage.")
            completion(false)
            return
        }
        
        let messageType: PeerMessageType
        switch signalingMessage.type {
        case .offer: messageType = .webrtcOffer
        case .answer: messageType = .webrtcAnswer
        case .candidate: messageType = .webrtcCandidate
        case .bye: messageType = .webrtcBye
        }
        
        let payloadString = message.base64EncodedString()
        
        let peerMessage = PeerMessage(
            type: messageType,
            sender: multipeerManager.myPeerID.displayName,
            payload: payloadString,
            messageID: signalingMessage.messageID
        )
        
        if let targetPeer = targetPeer {
            print("AppCoordinator: Sending signaling message with ACK to: \(targetPeer.displayName)")
            multipeerManager.sendMessageWithAcknowledgment(peerMessage, to: targetPeer, completion: completion)
        } else {
            print("AppCoordinator: Broadcasting signaling message to all peers")
            // ブロードキャスト時は個別に送信して各ピアからのACKを処理
            let peers = multipeerManager.connectedPeers
            var successCount = 0
            var failCount = 0
            
            if peers.isEmpty {
                // 接続されたピアがない場合は失敗として扱う
                completion(false)
                return
            }
            
            for peer in peers {
                multipeerManager.sendMessageWithAcknowledgment(peerMessage, to: peer) { success in
                    if success {
                        successCount += 1
                    } else {
                        failCount += 1
                    }
                    
                    // すべてのピアへの送信を試みた後に結果を返す
                    if successCount + failCount == peers.count {
                        // 少なくとも1つのピアに成功したら成功とみなす
                        completion(successCount > 0)
                    }
                }
            }
        }
    }
    
    // 新しいメソッド：接続タイムアウトの処理
    func webRTCManager(_ manager: WebRTCManager, didFailWithTimeout peer: MCPeerID) {
        print("AppCoordinator: WebRTC connection timed out with peer \(peer.displayName)")
        
        // UIに通知
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // トースト通知などを表示
            self.objectWillChange.send()
        }
    }
    
    // 新しいメソッド：接続失敗の処理
    func webRTCManager(_ manager: WebRTCManager, connectionDidFail peer: MCPeerID, canRetry: Bool) {
        print("AppCoordinator: WebRTC connection failed with peer \(peer.displayName), canRetry: \(canRetry)")
        
        if canRetry {
            // 少し間をおいて自動再接続を試みる
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                
                if manager.streamingRole == .sender {
                    print("AppCoordinator: 送信側として再接続を試みます: \(peer.displayName)")
                    manager.startCall(as: .sender, targetPeers: [peer])
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    // 新しいメソッド：接続状態の更新
    func webRTCManager(_ manager: WebRTCManager, didUpdateConnectionStatus status: [MCPeerID: ConnectionStatus]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionStatus = status
            self.objectWillChange.send()
        }
    }
}
