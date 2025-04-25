//
//  AppCoordinator.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import MultipeerConnectivity
import Combine
import SwiftUI
import QuartzCore

class AppCoordinator: NSObject, ObservableObject, CameraManagerDelegate, MultipeerManagerDelegate {
    // MARK: - Published Properties

    @Published var cameraManager: CameraManager
    @Published var multipeerManager: MultipeerManager
    
    // 同期関連の状態と機能
    @Published var scheduledActionTime: TimeInterval?

    private var peerRoundTripTimes: [MCPeerID: TimeInterval] = [:]
    private var displayLinkContext: (displayLink: CADisplayLink, startTime: CFTimeInterval, duration: TimeInterval, completion: () -> Void)?
    
    // MARK: - 初期化

    init(cameraManager: CameraManager, multipeerManager: MultipeerManager) {
        self.cameraManager = cameraManager
        self.multipeerManager = multipeerManager

        super.init()

        // 各マネージャーのデリゲート設定
        cameraManager.delegate = self
        multipeerManager.delegate = self
        
        // アプリ起動時にNTP同期を実行
        TimeManager.shared.synchronize { success in
            if success {
                print("アプリ起動時のNTP同期に成功しました")
            } else {
                print("アプリ起動時のNTP同期に失敗しました")
            }
        }
    }
    
    // MARK: - 同期関連メソッド
    
    func requestStartRecording() {
        // ステップ1: NTP時計同期を確認
        if TimeManager.shared.needsSync() {
            TimeManager.shared.synchronize { [weak self] success in
                guard let self = self, success else { return }
                self.proceedWithStartRecording()
            }
        } else {
            proceedWithStartRecording()
        }
    }
    
    private func proceedWithStartRecording() {
        // ステップ2: ネットワーク遅延を測定
        measureNetworkLatencies { [weak self] in
            guard let self = self else { return }
            
            // ステップ3: 適応的な開始遅延を計算
            let adaptiveDelay = self.calculateAdaptiveDelay()
            print("計算された適応的遅延: \(adaptiveDelay)秒")
            
            // ステップ4: 正確な開始時刻を計算（NTP補正済み時刻を使用）
            guard let ntpTime = TimeManager.shared.getCorrectedTime() else {
                print("警告: NTP時刻が取得できないため、システム時計を使用します")
                let startTime = Date().timeIntervalSince1970 + adaptiveDelay
                self.scheduleSyncedRecording(startTime: startTime)
                return
            }
            
            let startTime = ntpTime + adaptiveDelay
            self.scheduledActionTime = startTime
            
            // ステップ5: 全デバイスに開始時刻を送信
            let message = PeerMessage(
                type: .startRecording,
                sender: self.multipeerManager.myPeerID.displayName,
                payload: "\(startTime)"
            )
            
            self.sendMessageToPeers(message: message)
            
            // ステップ6: 自分のデバイスも同じ時刻に録画開始をスケジュール
            self.scheduleSyncedRecording(startTime: startTime)
        }
    }
    
    private func scheduleSyncedRecording(startTime: TimeInterval) {
        // 現在のNTP補正済み時刻
        let currentTime = TimeManager.shared.getCorrectedTime() ?? Date().timeIntervalSince1970
        
        // 待機時間を計算
        var waitTime = startTime - currentTime
        waitTime = max(0, waitTime)
        
        print("録画開始まであと \(waitTime)秒")
        
        if waitTime > 0.5 {
            // 長い待機は通常のDispatchQueueで処理
            let coarseWaitTime = waitTime - 0.5
            
            DispatchQueue.main.asyncAfter(deadline: .now() + coarseWaitTime) { [weak self] in
                // 残りの短い待機時間は精密タイミングで
                self?.performPreciseWait(remainingTime: 0.5) {
                    self?.cameraManager.startRecording()
                }
            }
        } else {
            // 短い待機時間は直接精密タイミングで
            performPreciseWait(remainingTime: waitTime) { [weak self] in
                self?.cameraManager.startRecording()
            }
        }
    }
    
    func requestStopRecording() {
        // NTP時計同期を確認
        if TimeManager.shared.needsSync() {
            TimeManager.shared.synchronize { [weak self] success in
                guard let self = self, success else { return }
                self.proceedWithStopRecording()
            }
        } else {
            proceedWithStopRecording()
        }
    }
    
    private func proceedWithStopRecording() {
        // ネットワーク遅延を測定
        measureNetworkLatencies { [weak self] in
            guard let self = self else { return }
            
            // 適応的な停止遅延を計算
            let adaptiveDelay = self.calculateAdaptiveDelay()
            
            // 正確な停止時刻を計算（NTP補正済み時刻を使用）
            guard let ntpTime = TimeManager.shared.getCorrectedTime() else {
                print("警告: NTP時刻が取得できないため、システム時計を使用します")
                let stopTime = Date().timeIntervalSince1970 + adaptiveDelay
                self.scheduleSyncedStopRecording(stopTime: stopTime)
                return
            }
            
            let stopTime = ntpTime + adaptiveDelay
            self.scheduledActionTime = stopTime
            
            // 全デバイスに停止時刻を送信
            let message = PeerMessage(
                type: .stopRecording,
                sender: self.multipeerManager.myPeerID.displayName,
                payload: "\(stopTime)"
            )
            
            self.sendMessageToPeers(message: message)
            
            // 自分のデバイスも同じ時刻に録画停止をスケジュール
            self.scheduleSyncedStopRecording(stopTime: stopTime)
        }
    }
    
    private func scheduleSyncedStopRecording(stopTime: TimeInterval) {
        // 録画開始と同様の高精度スケジューリングを実装
        let currentTime = TimeManager.shared.getCorrectedTime() ?? Date().timeIntervalSince1970
        
        var waitTime = stopTime - currentTime
        waitTime = max(0, waitTime)
        
        print("録画停止まであと \(waitTime)秒")
        
        if waitTime > 0.5 {
            let coarseWaitTime = waitTime - 0.5
            
            DispatchQueue.main.asyncAfter(deadline: .now() + coarseWaitTime) { [weak self] in
                self?.performPreciseWait(remainingTime: 0.5) {
                    self?.cameraManager.stopRecording()
                }
            }
        } else {
            performPreciseWait(remainingTime: waitTime) { [weak self] in
                self?.cameraManager.stopRecording()
            }
        }
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
    
    // MARK: -  Kronos使った誤差軽減のためのメソッドたち
    
    // RTT測定メソッド
    private func measureNetworkLatencies(completion: @escaping () -> Void) {
        let peers = multipeerManager.connectedPeers
        if peers.isEmpty {
            completion()
            return
        }
        
        let group = DispatchGroup()
        
        for peer in peers {
            group.enter()
            measureRoundTripTime(to: peer) { success in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion()
        }
    }

    private func measureRoundTripTime(to peer: MCPeerID, completion: @escaping (Bool) -> Void) {
        let startTime = Date().timeIntervalSince1970
        let pingMessage = PeerMessage(
            type: .ping,
            sender: multipeerManager.myPeerID.displayName,
            payload: "\(startTime)",
            messageID: UUID().uuidString
        )
        
        multipeerManager.sendMessageWithAcknowledgment(pingMessage, to: peer) { [weak self] success in
            if success {
                let endTime = Date().timeIntervalSince1970
                let rtt = endTime - startTime
                self?.peerRoundTripTimes[peer] = rtt
                print("ピア \(peer.displayName) とのRTT: \(rtt * 1000)ミリ秒")
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    // 適応的な遅延計算
    private func calculateAdaptiveDelay() -> TimeInterval {
        let minDelay: TimeInterval = 1.0  // 最小遅延時間
        
        if peerRoundTripTimes.isEmpty {
            return minDelay + 2.0  // データがない場合は安全側に
        }
        
        let rtts = Array(peerRoundTripTimes.values)
        let maxRTT = rtts.max() ?? 0
        let avgRTT = rtts.reduce(0, +) / Double(rtts.count)
        
        // 適応的な遅延を計算
        // 基本遅延 + 最大RTTの2倍（往復の保証） + 余裕
        let adaptiveDelay = minDelay + (maxRTT * 2.0) + (avgRTT * 0.5)
        
        // 上限を設定（あまりに長い待ち時間は実用的でない）
        return min(adaptiveDelay, 8.0)
    }
    
    // 高精度な待機処理
    private func performPreciseWait(remainingTime: TimeInterval, completion: @escaping () -> Void) {
        let startWait = CACurrentMediaTime()
        
        // より精密なCADisplayLinkを使用
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        displayLink.add(to: .main, forMode: .common)
        
        // displayLink用のコールバック関数に必要なコンテキスト
        self.displayLinkContext = (displayLink, startWait, remainingTime, completion)
    }

    // CADisplayLink用のコールバック
    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        guard let context = displayLinkContext else { return }
        
        let elapsed = CACurrentMediaTime() - context.startTime
        
        if elapsed >= context.duration {
            // 指定時間経過、タイマー停止とコールバック実行
            link.invalidate()
            displayLinkContext = nil
            context.completion()
        }
    }

}


// MARK: - CameraManagerDelegate
extension AppCoordinator /* : CameraManagerDelegate */ {
    func cameraManagerDidStartRecording(_ manager: CameraManager, at url: URL) {
        print("Recording started")
        scheduledActionTime = nil      // ★ ここを追加
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    func cameraManagerDidFinishRecording(_ manager: CameraManager, to url: URL) {
        print("AppCoordinator: Camera recording finished to \(url)")
        scheduledActionTime = nil
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
        
        case .ping:
            // すでにMultipeerManagerで確認応答を送信済み
            print("AppCoordinator: Received ping from \(peerID.displayName)")
            
        case .timeSync:
            print("AppCoordinator: Received time sync request from \(peerID.displayName)")
            // 時計同期リクエスト処理（必要に応じて実装）
            
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
