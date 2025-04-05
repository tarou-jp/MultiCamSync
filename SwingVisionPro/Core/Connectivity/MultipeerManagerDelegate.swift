//
//  MultipeerManagerDelegate.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import MultipeerConnectivity

protocol MultipeerManagerDelegate: AnyObject {
   // 接続状態の変更通知
   func multipeerManager(_ manager: MultipeerManager, didChangePeerConnectionState peerID: MCPeerID, state: MCSessionState)
   
   // メッセージ受信通知
   func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID)
   
   // 接続リクエスト通知
   func multipeerManager(_ manager: MultipeerManager, didReceiveInvitationFromPeer peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void)
   
   // ピア検出通知
   func multipeerManager(_ manager: MultipeerManager, didFindPeer peerID: MCPeerID)
   func multipeerManager(_ manager: MultipeerManager, didLosePeer peerID: MCPeerID)
}

// デフォルト実装を提供してオプショナルにする
extension MultipeerManagerDelegate {
   func multipeerManager(_ manager: MultipeerManager, didChangePeerConnectionState peerID: MCPeerID, state: MCSessionState) {}
   func multipeerManager(_ manager: MultipeerManager, didReceiveMessage message: PeerMessage, fromPeer peerID: MCPeerID) {}
   func multipeerManager(_ manager: MultipeerManager, didReceiveInvitationFromPeer peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {}
   func multipeerManager(_ manager: MultipeerManager, didFindPeer peerID: MCPeerID) {}
   func multipeerManager(_ manager: MultipeerManager, didLosePeer peerID: MCPeerID) {}
}
