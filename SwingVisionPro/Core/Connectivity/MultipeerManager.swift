//
//  MultipeerManager.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import Foundation
import MultipeerConnectivity
import SwiftUI

// 保留中の接続リクエストを表す型
struct PendingInvitation: Identifiable {
   let id = UUID()
   let peerID: MCPeerID
   let invitationHandler: (Bool, MCSession?) -> Void
}

class MultipeerManager: NSObject, ObservableObject {
   // デリゲート
   weak var delegate: MultipeerManagerDelegate?
   
   // サービスの種類
   private let serviceType = "swingvision"
   
   // 自身のPeerID
   let myPeerID: MCPeerID
   
   // セッション、アドバタイザー、ブラウザ
   private(set) var session: MCSession!
   private var advertiser: MCNearbyServiceAdvertiser!
   private var browser: MCNearbyServiceBrowser!
   
    // 状態関連のプロパティ
    @Published var discoveredPeers: [MCPeerID] = []
    @Published var pendingInvitation: PendingInvitation?
    @Published var connectedPeers: [MCPeerID] = []

    // メッセージ確認応答用のコールバック保持
    private var pendingAcknowledgments: [String: (Bool) -> Void] = [:]

    // メッセージ送信の再試行回数とタイマー保持
    private var messageSendAttempts: [String: Int] = [:]
    private var messageSendTimers: [String: Timer] = [:]
   
   override init() {
       // 保存されたピアIDがあればそれを使い、なければ新しく作成する
       if let savedPeerID = MultipeerManager.getSavedPeerID() {
           self.myPeerID = savedPeerID
       } else {
           // デバイス名 + ランダムな4桁の数字で一意性を確保
           let deviceName = UIDevice.current.name
           let randomSuffix = String(format: "%04d", Int.random(in: 0...9999))
           let uniqueID = "\(deviceName)-\(randomSuffix)"
           
           self.myPeerID = MCPeerID(displayName: uniqueID)
           
           // 次回も同じIDを使えるように保存
           MultipeerManager.savePeerID(self.myPeerID)
       }
       
       super.init()
       
       session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
       session.delegate = self
       
       advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
       advertiser.delegate = self
       
       browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
       browser.delegate = self
       
       startAdvertising()
       startBrowsing()
   }
   
   // MARK: - PeerID 永続化
       
   // PeerIDを保存
   private static func savePeerID(_ peerID: MCPeerID) {
       do {
           let peerIDData = try NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: false)
           UserDefaults.standard.set(peerIDData, forKey: "savedPeerID")
       } catch {
           print("Failed to save peer ID: \(error)")
       }
   }
   
   // 保存されたPeerIDを取得
   private static func getSavedPeerID() -> MCPeerID? {
       guard let peerIDData = UserDefaults.standard.data(forKey: "savedPeerID") else {
           return nil
       }
       
       do {
           if let peerID = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(peerIDData) as? MCPeerID {
               return peerID
           }
       } catch {
           print("Failed to retrieve peer ID: \(error)")
       }
       
       return nil
   }
   
   // 広告開始
   func startAdvertising() {
       advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
       advertiser.delegate = self
       advertiser.startAdvertisingPeer()
       print("MultipeerManager: Started advertising")
   }
   
   // 広告停止
   func stopAdvertising() {
       advertiser.stopAdvertisingPeer()
   }
   
   // ブラウジング開始
   func startBrowsing() {
       browser.startBrowsingForPeers()
   }
   
   // ブラウジング停止
   func stopBrowsing() {
       browser.stopBrowsingForPeers()
   }
   
   // 招待を送る時の処理
   func sendInvite(to peer: MCPeerID) {
       browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
   }

   // 招待を受け入れる時の処理
   func acceptInvitation(_ invitation: PendingInvitation) {
       invitation.invitationHandler(true, session)
       pendingInvitation = nil
   }
   
   // 接続拒否
   func rejectInvitation(_ invitation: PendingInvitation) {
       invitation.invitationHandler(false, nil)
       pendingInvitation = nil
   }
   
   // 接続切断
   func disconnect() {
       session.disconnect()
   }
   
   // 追加: 特定のピアとの接続を切断する
   func disconnect(from peer: MCPeerID) {
       session.disconnect()
   }
   
   // 下位互換性のためのメソッド
   func disconnectFromMaster() {
       disconnect()
   }
   
    // メッセージ送信関数の追加
       func sendMessage(_ message: PeerMessage, toPeers peers: [MCPeerID] = []) {
           let encoder = JSONEncoder()
           guard let data = try? encoder.encode(message) else {
               print("MultipeerManager: Failed to encode message")
               return
           }
           
           // 特定のピアが指定されていなければ、接続中の全ピアに送信
           let targetPeers = peers.isEmpty ? connectedPeers : peers
           
           guard !targetPeers.isEmpty else {
               print("MultipeerManager: No peers to send message to")
               return
           }
           
           do {
               try session.send(data, toPeers: targetPeers, with: .reliable)
           } catch {
               print("MultipeerManager: Failed to send message: \(error.localizedDescription)")
           }
       }
    
    // 確認応答付きメッセージ送信
       func sendMessageWithAcknowledgment(_ message: PeerMessage, to peer: MCPeerID, completion: @escaping (Bool) -> Void) {
           guard session.connectedPeers.contains(peer) else {
               print("MultipeerManager: 指定されたピアは接続されていません: \(peer.displayName)")
               completion(false)
               return
           }
           
           // メッセージIDに基づくコールバック保存
           if let messageID = message.messageID {
               pendingAcknowledgments[messageID] = completion
               
               // タイムアウト処理
               DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                   guard let self = self else { return }
                   if let callback = self.pendingAcknowledgments.removeValue(forKey: messageID) {
                       print("MultipeerManager: メッセージ確認応答がタイムアウト: \(messageID)")
                       callback(false)
                   }
               }
           }
           
           guard let data = try? JSONEncoder().encode(message) else {
               print("MultipeerManager: メッセージのエンコードに失敗しました")
               completion(false)
               return
           }
           
           do {
               try session.send(data, toPeers: [peer], with: .reliable)
               
               // 確認応答が不要な場合（messageIDがない）は即座に成功を返す
               if message.messageID == nil {
                   completion(true)
               }
           } catch {
               print("MultipeerManager: メッセージの送信に失敗しました: \(error.localizedDescription)")
               if let messageID = message.messageID {
                   pendingAcknowledgments.removeValue(forKey: messageID)
               }
               completion(false)
           }
       }
       
       // 再試行付きメッセージ送信
       func sendMessageWithRetry(_ message: PeerMessage, to peer: MCPeerID, maxRetries: Int = 3, completion: @escaping (Bool) -> Void) {
           guard let messageID = message.messageID else {
               print("MultipeerManager: 再試行付き送信にはmessageIDが必要です")
               completion(false)
               return
           }
           
           // 初期試行回数を設定
           messageSendAttempts[messageID] = 0
           performSendWithRetry(message: message, to: peer, maxRetries: maxRetries, completion: completion)
       }
       
       private func performSendWithRetry(message: PeerMessage, to peer: MCPeerID, maxRetries: Int, completion: @escaping (Bool) -> Void) {
           guard let messageID = message.messageID,
                 let attempts = messageSendAttempts[messageID] else {
               completion(false)
               return
           }
           
           // 最大再試行回数を超えた場合
           if attempts >= maxRetries {
               print("MultipeerManager: メッセージの最大再試行回数に達しました: \(messageID)")
               messageSendAttempts.removeValue(forKey: messageID)
               messageSendTimers[messageID]?.invalidate()
               messageSendTimers.removeValue(forKey: messageID)
               completion(false)
               return
           }
           
           // 再試行回数をインクリメント
           messageSendAttempts[messageID] = attempts + 1
           
           // 確認応答付きで送信
           sendMessageWithAcknowledgment(message, to: peer) { [weak self] success in
               guard let self = self else { return }
               
               if success {
                   // 成功したらクリーンアップして完了
                   self.messageSendAttempts.removeValue(forKey: messageID)
                   self.messageSendTimers[messageID]?.invalidate()
                   self.messageSendTimers.removeValue(forKey: messageID)
                   completion(true)
               } else if attempts < maxRetries {
                   // 失敗したら指数バックオフで再試行
                   let delay = pow(2.0, Double(attempts)) * 0.5 // 0.5秒、1秒、2秒...
                   
                   // 既存のタイマーをキャンセル
                   self.messageSendTimers[messageID]?.invalidate()
                   
                   // 新しいタイマーを設定
                   let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                       guard let self = self else { return }
                       self.performSendWithRetry(message: message, to: peer, maxRetries: maxRetries, completion: completion)
                   }
                   self.messageSendTimers[messageID] = timer
               } else {
                   // 最大再試行回数に達した
                   completion(false)
               }
           }
       }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
   func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
       DispatchQueue.main.async {
           let stateText = state == .connected ? "接続" : state == .connecting ? "接続中" : "切断"
           print("DEBUG: \(self.myPeerID.displayName) の接続状態変化: \(peerID.displayName) と \(stateText)")
           
           switch state {
           case .connected:
               // 接続成立時
               if !self.connectedPeers.contains(peerID) {
                   self.connectedPeers.append(peerID)
               }
               
           case .notConnected:
               // 接続解除時
               self.connectedPeers.removeAll { $0 == peerID }
               
           default:
               break
           }
           
           print("DEBUG: 接続済みピア: \(self.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
           
           // デリゲートに通知
           self.delegate?.multipeerManager(self, didChangePeerConnectionState: peerID, state: state)
       }
   }
   
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
       let decoder = JSONDecoder()
       if let message = try? decoder.decode(PeerMessage.self, from: data) {
           DispatchQueue.main.async {
               // 確認応答メッセージの場合
               if message.type == .acknowledgment, let messageID = message.messageID {
                   if let callback = self.pendingAcknowledgments.removeValue(forKey: messageID) {
                       callback(true)
                       print("MultipeerManager: 確認応答を受信: \(messageID)")
                       return
                   }
               }
               
               // 通常のメッセージ処理
               self.delegate?.multipeerManager(self, didReceiveMessage: message, fromPeer: peerID)
               
               // 従来の通知方法も維持（下位互換性のため）
               NotificationCenter.default.post(name: .didReceivePeerMessage, object: message)
               
               print("MultipeerManager: Received message \(message.type) from \(peerID.displayName)")
               
               // 確認応答メッセージIDがある場合は確認応答を返信
               if let messageID = message.messageID, message.type != .acknowledgment {
                   let ackMessage = PeerMessage(
                       type: .acknowledgment,
                       sender: self.myPeerID.displayName,
                       messageID: messageID
                   )
                   
                   if let data = try? JSONEncoder().encode(ackMessage) {
                       do {
                           try session.send(data, toPeers: [peerID], with: .reliable)
                           print("MultipeerManager: 確認応答を送信: \(messageID)")
                       } catch {
                           print("MultipeerManager: 確認応答の送信に失敗: \(error.localizedDescription)")
                       }
                   }
               }
           }
       } else {
           print("MultipeerManager: Failed to decode message from \(peerID.displayName)")
       }
   }

   // 以下は必須ですが、今回は未使用のため空実装
   func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { }
   func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
   func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
   func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
       print("Failed to start advertising: \(error.localizedDescription)")
   }
   
   // 接続リクエストを受信したとき
   func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                   withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
       print("Received invitation from \(peerID.displayName)")
       DispatchQueue.main.async {
           // デリゲートに通知（デリゲートが処理しない場合は従来の方法で処理）
           self.delegate?.multipeerManager(self, didReceiveInvitationFromPeer: peerID, invitationHandler: invitationHandler)
           
           // 自動承認せず、UIでユーザーに選択させるため、pendingInvitation に保存
           self.pendingInvitation = PendingInvitation(peerID: peerID, invitationHandler: invitationHandler)
       }
   }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
   func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
       print("Failed to start browsing: \(error.localizedDescription)")
   }
   
   // ピアを発見したとき
   func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
       DispatchQueue.main.async {
           // 自分自身のデバイスは除外、かつリストにまだ含まれていない
           if peerID.displayName != self.myPeerID.displayName && !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
               self.discoveredPeers.append(peerID)
               self.delegate?.multipeerManager(self, didFindPeer: peerID)
                print("MultipeerManager: Found peer \(peerID.displayName)")
           }
       }
   }
   
   // ピアが見つからなくなったとき
   func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
       DispatchQueue.main.async {
           // 修正: discoveredPeers 配列から削除
           if let index = self.discoveredPeers.firstIndex(of: peerID) {
               self.discoveredPeers.remove(at: index)
               print("MultipeerManager: Lost peer \(peerID.displayName)")
               self.delegate?.multipeerManager(self, didLosePeer: peerID)
           }
       }
   }
}

extension MCPeerID: Identifiable {
    public var id: String { self.displayName }
}

extension NSNotification.Name {
   static let didReceivePeerMessage = NSNotification.Name("didReceivePeerMessage")
}
