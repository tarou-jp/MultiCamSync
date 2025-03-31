//
//  SyncManager.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import Foundation
import Combine

class SyncManager: ObservableObject {
    private let cameraManager: CameraManager
    private let multipeerManager: MultipeerManager
    
    // カウントダウン用タイマーとしてのアクション時刻
    @Published var scheduledActionTime: TimeInterval?
    
    init(cameraManager: CameraManager, multipeerManager: MultipeerManager) {
        self.cameraManager = cameraManager
        self.multipeerManager = multipeerManager
        // 受信通知を購読する
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handlePeerMessageNotification(_:)),
                                               name: .didReceivePeerMessage,
                                               object: nil)
    }
    
    // UIからの録画開始要求
    func requestStartRecording() {
        let delay: TimeInterval = 5.0
        let startTime = Date().timeIntervalSince1970 + delay
        scheduledActionTime = startTime  // ここで時刻をセット
        
        let message = PeerMessage(type: .startRecording,
                                  sender: multipeerManager.myPeerID.displayName,
                                  payload: "\(startTime)")
        
        sendMessageToPeers(message: message)
        scheduleLocalRecording(startTime: startTime)
    }
    
    // UIからの録画停止要求
    func requestStopRecording() {
        let delay: TimeInterval = 5.0
        let stopTime = Date().timeIntervalSince1970 + delay
        scheduledActionTime = stopTime  // ここで時刻をセット
        
        let message = PeerMessage(type: .stopRecording,
                                  sender: multipeerManager.myPeerID.displayName,
                                  payload: "\(stopTime)")
        
        sendMessageToPeers(message: message)
        scheduleLocalStopRecording(stopTime: stopTime)
    }
    
    private func sendMessageToPeers(message: PeerMessage) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message) else {
            print("SyncManager: Failed to encode message")
            return
        }
        do {
            try multipeerManager.session.send(data,
                                              toPeers: multipeerManager.session.connectedPeers,
                                              with: .reliable)
        } catch {
            print("SyncManager: Message sending failed: \(error.localizedDescription)")
        }
    }
    
    // ローカルで録画開始をスケジュール
    private func scheduleLocalRecording(startTime: TimeInterval) {
        let delay = max(startTime - Date().timeIntervalSince1970, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if !self.cameraManager.isRecording {
                self.cameraManager.startRecording()
                print("SyncManager: Local recording started at \(startTime)")
            }
        }
    }
    
    // ローカルで録画停止をスケジュール
    private func scheduleLocalStopRecording(stopTime: TimeInterval) {
        let delay = max(stopTime - Date().timeIntervalSince1970, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.cameraManager.isRecording {
                self.cameraManager.stopRecording()
                print("SyncManager: Local recording stopped at \(stopTime)")
            }
        }
    }
    
    // NotificationCenter 経由の通知ハンドラ
    @objc private func handlePeerMessageNotification(_ notification: Notification) {
        guard let message = notification.object as? PeerMessage else { return }
        processReceivedMessage(message)
    }
    
    // 受信したメッセージに応じた処理
    func processReceivedMessage(_ message: PeerMessage) {
        switch message.type {
        case .startRecording:
            if let payload = message.payload, let startTime = TimeInterval(payload) {
                scheduledActionTime = startTime  // 受信した時刻をセット
                scheduleLocalRecording(startTime: startTime)
            }
        case .stopRecording:
            if let payload = message.payload, let stopTime = TimeInterval(payload) {
                scheduledActionTime = stopTime  // 受信した時刻をセット
                scheduleLocalStopRecording(stopTime: stopTime)
            }
        default:
            break
        }
    }
}
