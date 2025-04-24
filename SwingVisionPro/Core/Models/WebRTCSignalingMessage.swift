//
//  WebRTCSignalingMessage.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation

// シグナリングメッセージの種類
enum WebRTCSignalingType: String, Codable {
    case offer
    case answer
    case candidate
    case bye
}

// シグナリングメッセージの構造
struct WebRTCSignalingMessage: Codable {
    let type: WebRTCSignalingType
    let sdp: String?
    let candidate: IceCandidateData?
    let streamRole: StreamingRole?
    let messageID: String?
    
    init(type: WebRTCSignalingType, sdp: String? = nil, candidate: IceCandidateData? = nil, streamRole: StreamingRole? = nil, messageID: String? = nil) {
        self.type = type
        self.sdp = sdp
        self.candidate = candidate
        self.streamRole = streamRole
        self.messageID = messageID ?? UUID().uuidString
    }
}

// ICE候補情報
struct IceCandidateData: Codable {
    let sdpMid: String?
    let sdpMLineIndex: Int32
    let sdp: String
}

// ストリーミングの役割
enum StreamingRole: String, Codable {
    case none
    case sender
    case receiver
}
