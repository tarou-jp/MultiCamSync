//
//  WebRTCManager.swift
//  SwingVisionPro
//
//  Created on 2025/03/31.
//

import Foundation
import WebRTC
import MultipeerConnectivity
import Combine
import SwiftUI

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
}

// ICE候補情報
struct IceCandidateData: Codable {
    let sdpMid: String?
    let sdpMLineIndex: Int32
    let sdp: String
}

// ストリーミングの役割
enum StreamingRole: String, Codable {
    case sender
    case receiver
}

class WebRTCManager: NSObject, ObservableObject {
    // 状態管理
    @Published var isConnected = false
    @Published var isStreaming = false
    @Published var streamingRole: StreamingRole = .sender
    @Published var remoteVideoTrack: RTCVideoTrack?
    
    // マネージャー参照
    private let multipeerManager: MultipeerManager
    private let cameraManager: CameraManager
    
    // WebRTC関連
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    
    // キャンセル可能な購読
    private var cancellables = Set<AnyCancellable>()
    
    init(multipeerManager: MultipeerManager, cameraManager: CameraManager) {
        self.multipeerManager = multipeerManager
        self.cameraManager = cameraManager
        
        super.init()
        
        // WebRTCの初期化
        initializeWebRTC()
        
        // 接続状態の監視
        multipeerManager.$connectedPeers
            .sink { [weak self] peers in
                if peers.isEmpty {
                    // 接続先がなくなった場合、WebRTCを停止
                    self?.disconnect()
                }
            }
            .store(in: &cancellables)
        
        // メッセージの受信を監視
        NotificationCenter.default.publisher(for: .didReceivePeerMessage)
            .sink { [weak self] notification in
                if let message = notification.object as? PeerMessage {
                    self?.handlePeerMessage(message)
                }
            }
            .store(in: &cancellables)
    }
    
    // WebRTC初期化
    private func initializeWebRTC() {
        // グローバル初期化（アプリ起動時に一度だけ実行すれば良い）
        RTCInitializeSSL()
        
        // ファクトリー初期化
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }
    
    // ピア接続の設定
    private func configureConnection() {
        // 接続設定
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        // コンストレイント
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        // ピア接続の作成
        peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
        
        // ローカルメディアトラックのセットアップ
        setupLocalMediaTracks()
    }
    
    // ローカルメディアトラックのセットアップ
    private func setupLocalMediaTracks() {
        // ビデオソースの作成
        localVideoSource = peerConnectionFactory.videoSource()
        
        // カメラキャプチャラーの作成
        videoCapturer = RTCCameraVideoCapturer(delegate: localVideoSource!)
        
        // ローカルビデオトラックの作成
        let videoTrackId = "video" + UUID().uuidString
        localVideoTrack = peerConnectionFactory.videoTrack(with: localVideoSource!, trackId: videoTrackId)
        
        // ローカルオーディオトラックの作成
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory.audioSource(with: audioConstrains)
        let audioTrackId = "audio" + UUID().uuidString
        localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: audioTrackId)
        
        // 送信側のみトラックを追加
        if streamingRole == .sender {
            // トラックをピア接続に追加
            peerConnection?.add(localAudioTrack!, streamIds: ["stream"])
            peerConnection?.add(localVideoTrack!, streamIds: ["stream"])
            
            // カメラキャプチャを開始
            startCapture()
        }
    }
    
    // カメラキャプチャの開始
    private func startCapture() {
        guard let capturer = videoCapturer else { return }
        
        // 利用可能なカメラの検索
        let devices = RTCCameraVideoCapturer.captureDevices()
        
        // デフォルトはバックカメラを使用
        let position: AVCaptureDevice.Position = cameraManager.isFrontCamera ? .front : .back
        
        let device = devices.first { $0.position == position } ?? devices.first
        guard let camera = device else { return }
        
        // カメラのフォーマットとフレームレートを設定
        let formats = RTCCameraVideoCapturer.supportedFormats(for: camera)
        
        // 中程度の解像度を選択
        var selectedFormat: AVCaptureDevice.Format?
        var currentHighestFrameRate: Double = 0
        
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = dimensions.width
            let height = dimensions.height
            
            // 適切な解像度範囲を選択 (HD前後がよい)
            if width >= 640 && width <= 1280 {
                let frameRateRanges = format.videoSupportedFrameRateRanges
                for range in frameRateRanges {
                    if range.maxFrameRate > currentHighestFrameRate {
                        currentHighestFrameRate = range.maxFrameRate
                        selectedFormat = format
                    }
                }
            }
        }
        
        guard let format = selectedFormat else { return }
        
        // フレームレートを30fpsに設定
        let fps = min(currentHighestFrameRate, 30.0)
        
        // キャプチャ開始
        capturer.startCapture(with: camera, format: format, fps: Int(fps))
    }
    
    // 通話の開始（オファー作成側）
    func startCall(as role: StreamingRole) {
        self.streamingRole = role
        
        // ピア接続のセットアップ
        configureConnection()
        
        if role == .sender {
            // オファーの作成と送信
            createOffer()
        }
        
        isStreaming = true
    }
    
    // オファーの作成
    private func createOffer() {
        guard let peerConnection = peerConnection else { return }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        
        peerConnection.offer(for: constraints) { [weak self] (sdp, error) in
            guard let self = self, let sdp = sdp, error == nil else { return }
            
            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error)")
                    return
                }
                
                // オファーの送信
                self.sendSignalingMessage(type: .offer, sdp: sdp.sdp, streamRole: self.streamingRole)
            }
        }
    }
    
    // 切断処理
    func disconnect() {
        // キャプチャ停止
        videoCapturer?.stopCapture()
        
        // トラックのクリーンアップ
        localVideoTrack = nil
        localAudioTrack = nil
        localVideoSource = nil
        remoteVideoTrack = nil
        
        // Bye信号を送信
        sendSignalingMessage(type: .bye, sdp: nil, streamRole: nil)
        
        // ピア接続のクローズ
        peerConnection?.close()
        peerConnection = nil
        
        isConnected = false
        isStreaming = false
    }
    
    // シグナリングメッセージの送信
    private func sendSignalingMessage(type: WebRTCSignalingType, sdp: String? = nil, candidate: IceCandidateData? = nil, streamRole: StreamingRole? = nil) {
        // シグナリングメッセージの作成
        let message = WebRTCSignalingMessage(
            type: type,
            sdp: sdp,
            candidate: candidate,
            streamRole: streamRole
        )
        
        // JSON変換
        guard let data = try? JSONEncoder().encode(message),
              let base64String = String(data: data, encoding: .utf8) else { return }
        
        // MultipeerConnectivityでメッセージを送信
        let peerMessage = PeerMessage(
            type: .ping,  // 既存の型を流用
            sender: multipeerManager.myPeerID.displayName,
            payload: "webrtc:" + base64String
        )
        
        // 接続先に送信
        if let encodedMessage = try? JSONEncoder().encode(peerMessage) {
            for peer in multipeerManager.connectedPeers {
                try? multipeerManager.session.send(encodedMessage, toPeers: [peer], with: .reliable)
            }
        }
    }
    
    // PeerMessageの処理
    private func handlePeerMessage(_ message: PeerMessage) {
        guard let payload = message.payload,
              payload.hasPrefix("webrtc:") else { return }
        
        // webrtc:プレフィックスを取り除く
        let base64String = payload.dropFirst(7)
        
        // デコード
        guard let data = base64String.data(using: .utf8),
              let signalingMessage = try? JSONDecoder().decode(WebRTCSignalingMessage.self, from: data) else {
            return
        }
        
        // シグナリングメッセージの種類に応じた処理
        DispatchQueue.main.async {
            switch signalingMessage.type {
            case .offer:
                self.handleOffer(signalingMessage)
            case .answer:
                self.handleAnswer(signalingMessage)
            case .candidate:
                self.handleCandidate(signalingMessage)
            case .bye:
                self.handleBye()
            }
        }
    }
    
    // オファーの処理
    private func handleOffer(_ message: WebRTCSignalingMessage) {
        guard let sdp = message.sdp,
              let role = message.streamRole else { return }
        
        // 相手が送信側なら自分は受信側になる
        streamingRole = role == .sender ? .receiver : .sender
        
        // まだピア接続が作成されていない場合は作成
        if peerConnection == nil {
            configureConnection()
        }
        
        // SessionDescriptionの作成
        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        
        // RemoteDescriptionのセット
        peerConnection?.setRemoteDescription(remoteDescription) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("Failed to set remote description: \(error)")
                return
            }
            
            // アンサーの作成と送信
            self.createAnswer()
        }
    }
    
    // アンサーの処理
    private func handleAnswer(_ message: WebRTCSignalingMessage) {
        guard let sdp = message.sdp else { return }
        
        // SessionDescriptionの作成
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        
        // RemoteDescriptionのセット
        peerConnection?.setRemoteDescription(remoteDescription) { error in
            if let error = error {
                print("Failed to set remote description: \(error)")
            }
        }
    }
    
    // ICE候補の処理
    private func handleCandidate(_ message: WebRTCSignalingMessage) {
        guard let candidate = message.candidate else { return }
        
        // ICE候補の作成
        let iceCandidate = RTCIceCandidate(
            sdp: candidate.sdp,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        )
        
        // ICE候補の追加
        peerConnection?.add(iceCandidate)
    }
    
    // Byeの処理
    private func handleBye() {
        disconnect()
    }
    
    // アンサーの作成
    private func createAnswer() {
        guard let peerConnection = peerConnection else { return }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        
        peerConnection.answer(for: constraints) { [weak self] (sdp, error) in
            guard let self = self, let sdp = sdp, error == nil else { return }
            
            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error)")
                    return
                }
                
                // アンサーの送信
                self.sendSignalingMessage(type: .answer, sdp: sdp.sdp)
            }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    // ICE候補が見つかった
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // ICE候補情報を作成
        let candidateData = IceCandidateData(
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdp: candidate.sdp
        )
        
        // ICE候補を送信
        sendSignalingMessage(type: .candidate, candidate: candidateData)
    }
    
    // ICE接続状態が変化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE Connection State:", newState.rawValue)
        
        switch newState {
        case .connected, .completed:
            isConnected = true
        case .disconnected, .failed, .closed:
            isConnected = false
        default:
            break
        }
    }
    
    // ICE収集状態が変化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE Gathering State:", newState.rawValue)
    }
    
    // シグナリング状態が変化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling State:", stateChanged.rawValue)
    }
    
    // 接続状態が変化
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        print("Connection State:", newState.rawValue)
        
        switch newState {
        case .connected:
            isConnected = true
        case .disconnected, .failed, .closed:
            isConnected = false
        default:
            break
        }
    }
    
    // ストリームが追加された（非推奨なのでトラックでの処理を優先）
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // 現在は使用しない（onTrackを使用）
    }
    
    // ストリームが削除された（非推奨なのでトラックでの処理を優先）
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // 現在は使用しない（onTrackを使用）
    }
    
    // トラックが追加された
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        // ビデオトラックの場合
        if let videoTrack = receiver.track as? RTCVideoTrack {
            DispatchQueue.main.async {
                self.remoteVideoTrack = videoTrack
            }
        }
    }
    
    // データチャネルが追加された
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // 今回はデータチャネルは使用しない
    }
    
    // 必須の実装
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Negotiation needed")
    }
}
