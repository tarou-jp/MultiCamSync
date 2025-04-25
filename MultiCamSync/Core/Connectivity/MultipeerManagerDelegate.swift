//
//  MultipeerManagerDelegate.swift
//  MultiCamSync
//

import Foundation
import MultipeerConnectivity

protocol MultipeerManagerDelegate: AnyObject {
   // 既存のメソッド
   func multipeerManager(_ manager: MultipeerManager, didChangePeerConnectionState peerID: MCPeerID, state: MCSessionState)
   func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID)
   func multipeerManager(_ manager: MultipeerManager, didReceiveInvitationFromPeer peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void)
   func multipeerManager(_ manager: MultipeerManager, didFindPeer peerID: MCPeerID)
   func multipeerManager(_ manager: MultipeerManager, didLosePeer peerID: MCPeerID)
   
   // 新しいメソッド: 確認応答関連
   func multipeerManager(_ manager: MultipeerManager, didReceiveAcknowledgment messageID: String, fromPeer peerID: MCPeerID)
   func multipeerManager(_ manager: MultipeerManager, didFailToSendMessage message: PeerMessage, toPeer peerID: MCPeerID, afterRetries retries: Int)
}

// デフォルト実装を提供してオプショナルにする
extension MultipeerManagerDelegate {
   func multipeerManager(_ manager: MultipeerManager, didChangePeerConnectionState peerID: MCPeerID, state: MCSessionState) {}
   func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID) {}
   func multipeerManager(_ manager: MultipeerManager, didReceiveInvitationFromPeer peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {}
   func multipeerManager(_ manager: MultipeerManager, didFindPeer peerID: MCPeerID) {}
   func multipeerManager(_ manager: MultipeerManager, didLosePeer peerID: MCPeerID) {}
   
   // 新しいメソッドのデフォルト実装
   func multipeerManager(_ manager: MultipeerManager, didReceiveAcknowledgment messageID: String, fromPeer peerID: MCPeerID) {}
   func multipeerManager(_ manager: MultipeerManager, didFailToSendMessage message: PeerMessage, toPeer peerID: MCPeerID, afterRetries retries: Int) {}
}
