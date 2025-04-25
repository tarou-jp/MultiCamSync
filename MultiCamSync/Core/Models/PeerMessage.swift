//
//  PeerMessage.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import Foundation

enum PeerMessageType: String, Codable {
    case startRecording
    case stopRecording
    case acknowledgment
    
    case ping
    case timeSync
}

struct PeerMessage: Codable {
    let type: PeerMessageType
    let sender: String
    var payload: String?
    let timestamp: TimeInterval
    let messageID: String?
    
    init(type: PeerMessageType, sender: String, payload: String? = nil, messageID: String? = nil) {
        self.type = type
        self.sender = sender
        self.payload = payload
        self.timestamp = Date().timeIntervalSince1970
        self.messageID = messageID ?? UUID().uuidString
    }
}
