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
    }

    deinit {
        // リソースの解放
        webRTCManager.disconnect()
    }

    // MARK: - 同期関連メソッド
    
    func requestStartRecording() {
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
        
        multipeerManager.sendMessage(message, toPeers: multipeerManager.connectedPeers)
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
    
    func startStreamingAsPublisher(targetPeer: MCPeerID? = nil) {
        print("AppCoordinator: 送信側として映像配信を開始 - 配信先: \(targetPeer?.displayName ?? "すべて")")
        
        webRTCManager.startCall(as: .sender, targetPeer: targetPeer)
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
        
        default:
            print("AppCoordinator: Received unhandled message type \(message.type)")
            break
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
    
    func webRTCManagerDidChangeConnectionState(_ manager: WebRTCManager, isConnected: Bool) {
        print("AppCoordinator: WebRTC connection state changed to \(isConnected)")

        // 受信ロールで接続中ならカメラOFF
        if manager.streamingRole == .receiver && isConnected {
            cameraManager.pauseCaptureSession()
        } else {
            cameraManager.resumeCaptureSession()
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
          
      let peerMessage = PeerMessage(
          type: messageType,
          sender: multipeerManager.myPeerID.displayName,
          payload: payloadString
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
}
