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
    @Published private(set) var connectedPeers: [MCPeerID] = []
    
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
        advertiser.startAdvertisingPeer()
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
    
    // 下位互換性のためのメソッド
    func disconnectFromMaster() {
        disconnect()
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
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let decoder = JSONDecoder()
        if let message = try? decoder.decode(PeerMessage.self, from: data) {
            DispatchQueue.main.async {
                // ここでNotificationCenterを使ってSyncManagerに通知する例
                NotificationCenter.default.post(name: .didReceivePeerMessage, object: message)
                print("MultipeerManager: Received message \(message.type) from \(peerID.displayName)")
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
            // 自分自身のデバイスは除外する
            if peerID.displayName != self.myPeerID.displayName && !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.discoveredPeers.append(peerID)
            }
        }
        print("Found peer: \(peerID.displayName)")
    }
    
    // ピアが見つからなくなったとき
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
        print("Lost peer: \(peerID.displayName)")
    }
}

extension MCPeerID: @retroactive Identifiable {
    public var id: String { self.displayName }
}


extension NSNotification.Name {
    static let didReceivePeerMessage = NSNotification.Name("didReceivePeerMessage")
}
