//
//  AppCoordinator.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import MultipeerConnectivity
import WebRTC
import Combine
import SwiftUI

class AppCoordinator: NSObject, ObservableObject, CameraManagerDelegate, MultipeerManagerDelegate {
    // MARK: - Published Properties

    @Published var cameraManager: CameraManager
    @Published var multipeerManager: MultipeerManager
    
    // 同期関連の状態と機能
    @Published var scheduledActionTime: TimeInterval?

    // MARK: - 初期化

    init(cameraManager: CameraManager, multipeerManager: MultipeerManager) {
        self.cameraManager = cameraManager
        self.multipeerManager = multipeerManager

        super.init()

        // 各マネージャーのデリゲート設定
        cameraManager.delegate = self
        multipeerManager.delegate = self
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
    
    // 修正: disconnectAllPeers を disconnect にリネーム (またはそのまま残す)
    func disconnectAllPeers() {
        print("AppCoordinator: Disconnecting from all peers")
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
}

// MARK: - MultipeerManagerDelegate
extension AppCoordinator /* : MultipeerManagerDelegate */ {
    func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID) {
        switch message.type {
        case .startRecording, .stopRecording:
            processSyncMessage(message)
            
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
