//
//  PeerMessage.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import Foundation

enum PeerMessageType: String, Codable {
    // 同期用
    case startRecording
    case stopRecording
    
    // WebRTCシグナリング用
    case webrtcOffer
    case webrtcAnswer
    case webrtcCandidate
    case webrtcBye
    
    // 確認応答用
    case acknowledgment  // 新しい確認応答タイプを追加
}

struct PeerMessage: Codable {
    let type: PeerMessageType
    let sender: String
    var payload: String?
    let timestamp: TimeInterval  // 追加: タイムスタンプ
    let messageID: String?       // 追加: メッセージ固有のID
    
    init(type: PeerMessageType, sender: String, payload: String? = nil, messageID: String? = nil) {
        self.type = type
        self.sender = sender
        self.payload = payload
        self.timestamp = Date().timeIntervalSince1970  // 現在のタイムスタンプ
        self.messageID = messageID ?? UUID().uuidString  // IDがなければ生成
    }
}
