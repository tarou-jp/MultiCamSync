//
//  PeerMessage.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import Foundation

enum PeerMessageType: String, Codable {
    case connectionRequest
    case connectionAccept
    case connectionReject
    case ping
    case pong
    case disconnect
    case startRecording
    case stopRecording
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
