//
//  WebRTCManager.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import WebRTC
import Combine
import AVFoundation
import MultipeerConnectivity

final class EmptyVideoCapturer: RTCVideoCapturer {
    static let shared = EmptyVideoCapturer()
    private override init() {
        super.init()
    }
}

class WebRTCManager: NSObject, ObservableObject {
    // MARK: - Public (Published) Properties

    @Published var isConnected = false
    @Published var isStreaming = false
    @Published var streamingRole: StreamingRole = .none
    @Published var remoteVideoTrack: RTCVideoTrack?
    
    // 映像配信先の端末のMCPeerIDを保持
    @Published var targetPeerForStreaming: MCPeerID?

    // デリゲート（既にプロジェクト内で定義済みの WebRTCManagerDelegate を想定）
    weak var delegate: WebRTCManagerDelegate?

    // MARK: - Private Properties

    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?

    // MARK: - Life Cycle

    override init() {
        super.init()
        initializeWebRTC()
    }

    deinit {
        cleanupResources()
    }

    // MARK: - Setup Methods

    private func initializeWebRTC() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    private func configureConnection() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        setupLocalTracks()
    }

    private func setupLocalTracks() {
        // 映像ソースと映像トラックを作成（送信側の場合のみ意味を持つ）
        localVideoSource = peerConnectionFactory.videoSource()
        let videoTrackId = "video-\(UUID().uuidString)"
        localVideoTrack = peerConnectionFactory.videoTrack(
            with: localVideoSource!,
            trackId: videoTrackId
        )

        // 音声ソースとトラックを作成
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory.audioSource(with: audioConstraints)
        let audioTrackId = "audio-\(UUID().uuidString)"
        localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: audioTrackId)

        // 送信側ロールであれば PeerConnection に追加
        DispatchQueue.main.async { [weak self] in
            guard
                let self = self,
                let pc = self.peerConnection
            else {
                return
            }
            if self.streamingRole == .sender {
                if let videoTrack = self.localVideoTrack {
                    pc.add(videoTrack, streamIds: ["stream"])
                }
                if let audioTrack = self.localAudioTrack {
                    pc.add(audioTrack, streamIds: ["stream"])
                }
            }
        }
    }

    // MARK: - Public Methods

    /// 通話（配信）開始メソッド
    func startCall(as role: StreamingRole, targetPeer: MCPeerID? = nil) {
        self.targetPeerForStreaming = targetPeer
        print("WebRTCManager: Call starting as \(role), target peer: \(targetPeer?.displayName ?? "none")")
        
        // UI状態更新をメインスレッドで先に行う
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.streamingRole = role
            self.isStreaming = true
        }
        
        // WebRTC初期化と接続設定を非同期で行う
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 既存の接続設定メソッドを使用
            self.configureConnection()
            
            // UI更新はメインスレッドで
            DispatchQueue.main.async {
                if role == .sender {
                    self.createOffer()
                }
            }
        }
    }

    /// カメラのフレームを渡す（送信側だけ意味を持つ）
    func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard
            isStreaming,
            streamingRole == .sender,
            let localVideoSource = localVideoSource
        else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampNs = Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000)
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timestampNs)

        localVideoSource.capturer(EmptyVideoCapturer.shared, didCapture: videoFrame)
    }

    /// WebRTCの切断
    func disconnect() {
        guard peerConnection != nil else {
            print("WebRTCManager: Disconnect called but peerConnection is already nil.")
            return
        }
        
        print("WebRTCManager: Starting disconnection process.")
        sendSignalingMessage(type: .bye)
        
        cleanupResources()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.isStreaming = false
            self.targetPeerForStreaming = nil
            self.streamingRole = .none
            print("WebRTCManager: Connection state reset.")
        }
    }

    // ★ 追加: デコード済みのシグナリングメッセージを処理するメソッド
    func processDecodedSignalingMessage(_ signalingMessage: WebRTCSignalingMessage, from peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // peerConnection が nil の場合に処理すべきでないメッセージをガード (これは残す)
            if self.peerConnection == nil && (signalingMessage.type == .answer || signalingMessage.type == .candidate) {
                 print("WebRTCManager: Ignoring signaling message (type: \(signalingMessage.type)) because peerConnection is nil.")
                 return
            }

            print("WebRTCManager: Processing decoded signaling message type \(signalingMessage.type) from \(peerID.displayName)")
            
            switch signalingMessage.type {
            case .offer:
                self.targetPeerForStreaming = peerID
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

    // MARK: - Private Methods (Offer/Answer)

    private func createOffer() {
        guard let pc = peerConnection else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        pc.offer(for: constraints) { [weak self] sdp, error in
            guard
                let self = self,
                let sdp = sdp,
                error == nil
            else {
                return
            }
            pc.setLocalDescription(sdp) { error in
                guard error == nil else { return }
                self.sendSignalingMessage(type: .offer, sdp: sdp.sdp, streamRole: self.streamingRole)
            }
        }
    }

    private func createAnswer() {
        guard let pc = peerConnection else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        pc.answer(for: constraints) { [weak self] sdp, error in
            guard
                let self = self,
                let sdp = sdp,
                error == nil
            else {
                return
            }
            pc.setLocalDescription(sdp) { error in
                guard error == nil else { return }
                self.sendSignalingMessage(type: .answer, sdp: sdp.sdp)
            }
        }
    }

    private func handleOffer(_ message: WebRTCSignalingMessage) {
        guard let sdp = message.sdp, let role = message.streamRole else {
            return
        }

        if peerConnection == nil {
            print("WebRTCManager: Received Offer. Configuring connection and setting state to Receiver.")
            DispatchQueue.main.async {
                self.streamingRole = .receiver
                self.isStreaming = true
            }
            configureConnection()
        }

        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection?.setRemoteDescription(remoteDescription) { [weak self] error in
            guard error == nil else { return }
            self?.createAnswer()
        }
    }

    private func handleAnswer(_ message: WebRTCSignalingMessage) {
        guard let sdp = message.sdp else { return }
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        peerConnection?.setRemoteDescription(remoteDescription, completionHandler: { _ in })
    }

    // MARK: - Private Methods (ICE Candidate)

    private func handleCandidate(_ message: WebRTCSignalingMessage) {
        guard let pc = peerConnection else { 
            print("WebRTCManager: Ignoring candidate because peerConnection is nil.")
            return
        }
        guard let c = message.candidate else { return }
        let iceCandidate = RTCIceCandidate(
            sdp: c.sdp,
            sdpMLineIndex: c.sdpMLineIndex,
            sdpMid: c.sdpMid
        )
        print("WebRTCManager: Adding received ICE candidate.")
        pc.add(iceCandidate) { error in
            if let error = error {
                print("WebRTCManager: Failed to add received ICE candidate: \(error.localizedDescription)")
            }
        }
    }

    private func handleBye() {
        print("WebRTCManager: Received Bye message.")
        disconnect()
    }

    // MARK: - Cleanup

    private func cleanupResources() {
        print("WebRTCManager: Cleaning up WebRTC resources.")
        DispatchQueue.main.async { [weak self] in
            self?.remoteVideoTrack = nil
        }
        
        guard let pc = peerConnection else {
            print("WebRTCManager: PeerConnection already nil during cleanup.")
            return
        }

        // Stop all transceivers (important for clean shutdown)
        print("WebRTCManager: Stopping transceivers.")
        for transceiver in pc.transceivers {
            transceiver.stopInternal()
        }

        // Remove tracks from the peer connection before closing
        // Although closing should handle this, explicit removal is safer.
        print("WebRTCManager: Removing senders.")
        for sender in pc.senders {
            pc.removeTrack(sender)
        }

        // Set delegate to nil before closing to prevent further callbacks
        print("WebRTCManager: Setting PeerConnection delegate to nil.")
        pc.delegate = nil
        
        // Close the connection
        print("WebRTCManager: Closing PeerConnection.")
        pc.close()
        print("WebRTCManager: PeerConnection closed.")
        
        // Nil out references
        peerConnection = nil
        localVideoTrack = nil
        localAudioTrack = nil
        localVideoSource = nil
        
        print("WebRTCManager: WebRTC resources cleaned up.")
    }

    // MARK: - Signaling Helper

    // シグナリングメッセージ送信（デリゲート経由）- 修正版
    private func sendSignalingMessage(type: WebRTCSignalingType, sdp: String? = nil, candidate: IceCandidateData? = nil, streamRole: StreamingRole? = nil) {
        let message = WebRTCSignalingMessage(type: type, sdp: sdp, candidate: candidate, streamRole: streamRole)
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        delegate?.webRTCManager(self, needsToSendSignalingMessage: data, targetPeer: targetPeerForStreaming)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateData = IceCandidateData(
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdp: candidate.sdp
        )
        sendSignalingMessage(type: .candidate, candidate: candidateData)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch newState {
            case .connected, .completed:
                self.isConnected = true
                self.delegate?.webRTCManagerDidChangeConnectionState(self, isConnected: true)
            case .disconnected, .failed, .closed:
                self.isConnected = false
                self.delegate?.webRTCManagerDidChangeConnectionState(self, isConnected: false)
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch newState {
            case .connected:
                self.isConnected = true
                self.delegate?.webRTCManagerDidChangeConnectionState(self, isConnected: true)
            case .disconnected, .failed, .closed:
                self.isConnected = false
                self.delegate?.webRTCManagerDidChangeConnectionState(self, isConnected: false)
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let videoTrack = receiver.track as? RTCVideoTrack {
            DispatchQueue.main.async { [weak self] in
                self?.remoteVideoTrack = videoTrack
                if let strongSelf = self {
                    strongSelf.delegate?.webRTCManagerDidReceiveRemoteVideoTrack(strongSelf, track: videoTrack)
                }
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
