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
}


struct PeerMessage: Codable {
    let type: PeerMessageType
    let sender: String
    var payload: String?
    
    init(type: PeerMessageType, sender: String, payload: String? = nil) {
        self.type = type
        self.sender = sender
        self.payload = payload
    }
}
