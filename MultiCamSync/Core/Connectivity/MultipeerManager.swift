//
//  MultipeerManager.swift
//  MultiCamSync
//

import Foundation
import MultipeerConnectivity
import SwiftUI

struct PendingInvitation: Identifiable {
    let id = UUID()
    let peerID: MCPeerID
    let invitationHandler: (Bool, MCSession?) -> Void
}

class MultipeerManager: NSObject, ObservableObject {
    weak var delegate: MultipeerManagerDelegate?
    private let serviceType = "multicamsync"

    let myPeerID: MCPeerID
    private(set) var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    @Published var discoveredPeers: [MCPeerID] = []
    @Published var pendingInvitation: PendingInvitation?
    @Published var connectedPeers: [MCPeerID] = []

    private var pendingAcknowledgments: [String: (Bool) -> Void] = [:]
    private var messageSendAttempts: [String: Int] = [:]
    private var messageSendTimers: [String: Timer] = [:]

    override init() {
        if let saved = MultipeerManager.getSavedPeerID() {
            myPeerID = saved
        } else {
            let name = UIDevice.current.name
            let suffix = String(format: "%04d", Int.random(in: 0...9999))
            myPeerID = MCPeerID(displayName: "\(name)-\(suffix)")
            MultipeerManager.savePeerID(myPeerID)
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

    private static func savePeerID(_ peerID: MCPeerID) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "savedPeerID")
        }
    }

    private static func getSavedPeerID() -> MCPeerID? {
        guard let data = UserDefaults.standard.data(forKey: "savedPeerID") else { return nil }
        return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? MCPeerID
    }

    func startAdvertising() {
        advertiser.startAdvertisingPeer()
    }

    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
    }

    func startBrowsing() {
        browser.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser.stopBrowsingForPeers()
    }

    func sendInvite(to peer: MCPeerID) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func acceptInvitation(_ invitation: PendingInvitation) {
        invitation.invitationHandler(true, session)
        pendingInvitation = nil
    }

    func rejectInvitation(_ invitation: PendingInvitation) {
        invitation.invitationHandler(false, nil)
        pendingInvitation = nil
    }

    func disconnect() {
        session.disconnect()
    }

    // MARK: - メッセージ送信

    func sendMessage(_ message: PeerMessage, toPeers peers: [MCPeerID] = []) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let targets = peers.isEmpty ? connectedPeers : peers
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    func sendMessageWithAcknowledgment(_ message: PeerMessage, to peer: MCPeerID, completion: @escaping (Bool) -> Void) {
        guard session.connectedPeers.contains(peer) else { completion(false); return }
        guard let id = message.messageID else { completion(false); return }
        pendingAcknowledgments[id] = completion

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if let callback = self?.pendingAcknowledgments.removeValue(forKey: id) {
                callback(false)
            }
        }

        if let data = try? JSONEncoder().encode(message) {
            try? session.send(data, toPeers: [peer], with: .reliable)
        }
    }

    func sendMessageWithRetry(_ message: PeerMessage, to peer: MCPeerID, maxRetries: Int = 3, completion: @escaping (Bool) -> Void) {
        guard let id = message.messageID else { completion(false); return }
        messageSendAttempts[id] = 0
        performSendWithRetry(message: message, to: peer, maxRetries: maxRetries, completion: completion)
    }

    private func performSendWithRetry(message: PeerMessage, to peer: MCPeerID, maxRetries: Int, completion: @escaping (Bool) -> Void) {
        guard let id = message.messageID else { completion(false); return }
        let attempts = messageSendAttempts[id] ?? 0
        if attempts >= maxRetries { completion(false); return }

        messageSendAttempts[id] = attempts + 1
        sendMessageWithAcknowledgment(message, to: peer) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.messageSendAttempts.removeValue(forKey: id)
                self.messageSendTimers[id]?.invalidate()
                self.messageSendTimers.removeValue(forKey: id)
                completion(true)
            } else {
                let delay = pow(2.0, Double(attempts)) * 0.5
                let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.performSendWithRetry(message: message, to: peer, maxRetries: maxRetries, completion: completion)
                }
                self.messageSendTimers[id]?.invalidate()
                self.messageSendTimers[id] = timer
            }
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) { self.connectedPeers.append(peerID) }
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
            default: break
            }
            self.delegate?.multipeerManager(self, didChangePeerConnectionState: peerID, state: state)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }

        // ACK への応答をここで処理
        if message.type == .acknowledgment, let id = message.messageID {
            if let callback = pendingAcknowledgments.removeValue(forKey: id) {
                callback(true)
            }
        }

        // ping に即応
        if message.type == .ping {
            let ack = PeerMessage(type: .acknowledgment, sender: myPeerID.displayName, messageID: message.messageID)
            sendMessage(ack, toPeers: [peerID])
        }

        // timeSync 応答
        if message.type == .timeSync, let id = message.messageID {
            let now = TimeManager.shared.getCorrectedTime() ?? Date().timeIntervalSince1970
            let resp = PeerMessage(type: .timeSync, sender: myPeerID.displayName, payload: "\(now)", messageID: id)
            sendMessage(resp, toPeers: [peerID])
        }

        DispatchQueue.main.async {
            self.delegate?.multipeerManager(self, didReceiveMessage: message, fromPeer: peerID)
            if message.type == .acknowledgment, let id = message.messageID {
                self.delegate?.multipeerManager(self, didReceiveAcknowledgment: id, fromPeer: peerID)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser / Browser Delegates
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("advertise error: \(error)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.pendingInvitation = PendingInvitation(peerID: peerID, invitationHandler: invitationHandler)
            self.delegate?.multipeerManager(self, didReceiveInvitationFromPeer: peerID, invitationHandler: invitationHandler)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("browse error: \(error)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if peerID != self.myPeerID && !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
                self.delegate?.multipeerManager(self, didFindPeer: peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
            self.delegate?.multipeerManager(self, didLosePeer: peerID)
        }
    }
}

extension MCPeerID: Identifiable { public var id: String { displayName } }
