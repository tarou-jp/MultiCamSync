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

enum ConnectionStatus {
    case idle
    case connecting
    case connected
    case reconnecting
    case failed
    case closed
}

class WebRTCManager: NSObject, ObservableObject {
    // MARK: - Public (Published) Properties

    @Published var isConnected = false
    @Published var isStreaming = false
    @Published var streamingRole: StreamingRole = .none
    @Published var remoteVideoTracks: [MCPeerID: RTCVideoTrack] = [:]
    private var peerConnections: [MCPeerID: RTCPeerConnection] = [:]
    
    // 映像配信先の端末のMCPeerIDを保持
    @Published var targetPeerForStreaming: MCPeerID?

    // デリゲート（既にプロジェクト内で定義済みの WebRTCManagerDelegate を想定）
    weak var delegate: WebRTCManagerDelegate?

    // MARK: - Private Properties

    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    
    // 接続ステータスを保持するディクショナリを追加
    private var connectionStatus: [MCPeerID: ConnectionStatus] = [:]

    // 接続タイムアウト用タイマー
    private var connectionTimers: [MCPeerID: Timer] = [:]
    
    // シグナリングメッセージ送信の再試行カウンター
    private var signalingSendAttempts: [String: Int] = [:]
    
    // 定期的な接続状態チェックを開始
    private var connectionHealthTimer: Timer?

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
    
    private func configureConnection(for peer: MCPeerID) -> RTCPeerConnection {
        let config = RTCConfiguration()
        
        // 複数のSTUNサーバーを設定
        config.iceServers = [
            RTCIceServer(urlStrings: [
                "stun:stun.l.google.com:19302",
                "stun:stun1.l.google.com:19302",
                "stun:stun2.l.google.com:19302",
                "stun:stun3.l.google.com:19302",
                "stun:stun4.l.google.com:19302"
            ]),
            // 無料のTURNサーバーの例（実際の運用では独自のTURNサーバーを推奨）
            RTCIceServer(
                urlStrings: ["turn:openrelay.metered.ca:443"],
                username: "openrelayproject",
                credential: "openrelayproject"
            )
        ]
        
        // ICE収集プロセスの改善
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.tcpCandidatePolicy = .enabled
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.iceTransportPolicy = .all
        
        // 接続の最適化
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true",
                "googICERestartEnabled": "true"  // ICE再起動を有効化
            ]
        )

        guard let pc = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            fatalError("RTCPeerConnection の生成に失敗しました: \(peer.displayName)")
        }

        peerConnections[peer] = pc
        connectionStatus[peer] = .idle
        setupLocalTracks(on: pc)
        return pc
    }
    
    func startConnectionHealthCheck() {
        // 既存のタイマーをキャンセル
        connectionHealthTimer?.invalidate()
        
        // 新しいタイマーを設定（10秒ごと）
        connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 接続状態を確認
            for (peer, pc) in self.peerConnections {
                let iceState = pc.iceConnectionState
                let connState = pc.connectionState
                
                // 問題のある状態を検出
                if (iceState == .disconnected || iceState == .failed) &&
                   (connState != .connected) {
                    print("WebRTCManager: ピア \(peer.displayName) の接続に問題があります。再接続を検討してください。")
                    
                    // 長時間の問題状態は自動リセット
                    if let status = self.connectionStatus[peer],
                       status == .reconnecting || status == .failed {
                        print("WebRTCManager: ピア \(peer.displayName) との接続を自動リセットします")
                        self.resetConnection(for: peer)
                    }
                }
            }
        }
    }

    func stopConnectionHealthCheck() {
        connectionHealthTimer?.invalidate()
        connectionHealthTimer = nil
    }

    // WebRTCの接続状態を診断するメソッド
    func diagnoseConnectionStatus() -> String {
        var report = "WebRTC接続診断レポート:\n"
        
        // 全体の状態
        report += "ストリーミング状態: \(isStreaming ? "有効" : "無効")\n"
        report += "ストリーミングロール: \(streamingRole)\n"
        report += "接続数: \(peerConnections.count)\n"
        report += "リモートビデオトラック数: \(remoteVideoTracks.count)\n\n"
        
        // 各ピア接続の詳細
        report += "== 接続詳細 ==\n"
        for (peer, pc) in peerConnections {
            let status = connectionStatus[peer] ?? .idle
            report += "ピア: \(peer.displayName)\n"
            report += "- 接続状態: \(pc.connectionState.rawValue)\n"
            report += "- ICE接続状態: \(pc.iceConnectionState.rawValue)\n"
            report += "- シグナル状態: \(pc.signalingState.rawValue)\n"
            report += "- 管理状態: \(status)\n"
            
            // ICE候補の数（送信者と受信者）
            let senderCount = pc.senders.count
            let receiverCount = pc.receivers.count
            report += "- 送信トラック数: \(senderCount)\n"
            report += "- 受信トラック数: \(receiverCount)\n\n"
        }
        
        print(report)
        return report
    }

    private func sendSignalingMessageWithRetry(
        type: WebRTCSignalingType,
        sdp: String? = nil,
        candidate: IceCandidateData? = nil,
        streamRole: StreamingRole? = nil,
        to peer: MCPeerID,
        maxRetries: Int = 3
    ) {
        let messageID = UUID().uuidString
        let key = "\(messageID)-\(peer.displayName)-\(type.rawValue)"
        signalingSendAttempts[key] = 0
        
        performSendWithRetry(messageID: messageID, type: type, sdp: sdp, candidate: candidate, streamRole: streamRole, to: peer, maxRetries: maxRetries)
    }

    private func performSendWithRetry(
        messageID: String,
        type: WebRTCSignalingType,
        sdp: String? = nil,
        candidate: IceCandidateData? = nil,
        streamRole: StreamingRole? = nil,
        to peer: MCPeerID,
        maxRetries: Int
    ) {
        let key = "\(messageID)-\(peer.displayName)-\(type.rawValue)"
        
        // 現在の試行回数を取得・更新
        guard let attempts = signalingSendAttempts[key], attempts < maxRetries else {
            print("WebRTCManager: シグナリングメッセージの最大再試行回数に達しました: \(type) to \(peer.displayName)")
            signalingSendAttempts.removeValue(forKey: key)
            return
        }
        
        signalingSendAttempts[key] = attempts + 1
        
        // 通常のシグナリングメッセージを構築
        let msg = WebRTCSignalingMessage(
            type: type,
            sdp: sdp,
            candidate: candidate,
            streamRole: streamRole,
            messageID: messageID
        )
        
        // メッセージを送信
        guard let data = try? JSONEncoder().encode(msg) else { return }
        
        // 新しいデリゲートメソッドを使用して、ACKを要求
        delegate?.webRTCManager(self, needsToSendSignalingMessageWithAck: data, targetPeer: peer) { [weak self] success in
            guard let self = self else { return }
            
            if !success && attempts < maxRetries {
                // 失敗した場合、指数バックオフで再試行
                let delay = pow(2.0, Double(attempts)) * 0.5
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.performSendWithRetry(
                        messageID: messageID,
                        type: type,
                        sdp: sdp,
                        candidate: candidate,
                        streamRole: streamRole,
                        to: peer,
                        maxRetries: maxRetries
                    )
                }
            } else if success {
                // 成功したら再試行カウンターをクリア
                self.signalingSendAttempts.removeValue(forKey: key)
            }
        }
    }
    
    private func setupLocalTracks(on pc: RTCPeerConnection) {
        // 映像ソースと映像トラックを作成
        let videoSource = peerConnectionFactory.videoSource()
        let videoTrackId = "video-\(UUID().uuidString)"
        let videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: videoTrackId)

        // 音声ソースとトラックを作成
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory.audioSource(with: audioConstraints)
        let audioTrackId = "audio-\(UUID().uuidString)"
        let audioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: audioTrackId)

        // 送信側ロールであれば PeerConnection に追加
        DispatchQueue.main.async {
            if self.streamingRole == .sender {
                pc.add(videoTrack, streamIds: ["stream"])
                pc.add(audioTrack, streamIds: ["stream"])
            }
        }

        // 再利用用に保存
        localVideoSource = videoSource
        localVideoTrack = videoTrack
        localAudioTrack = audioTrack
    }
    
    // MARK: - Public Methods

    /// 通話（配信）開始メソッド（複数ピア対応）
    func startCall(as role: StreamingRole, targetPeers: [MCPeerID]) {
        // UI更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.streamingRole = role
            self.isStreaming = true
        }

        // 各ピアに対して PeerConnection 設定と Offer を生成
        for peer in targetPeers {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let pc = self.configureConnection(for: peer)
                if role == .sender {
                    self.createOffer(on: pc, to: peer)
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
        for (peer, pc) in peerConnections {
            sendSignalingMessage(type: .bye, to: peer)
            pc.close()
        }
        peerConnections.removeAll()
        DispatchQueue.main.async {
            self.remoteVideoTracks.removeAll()
            self.isConnected = false
            self.isStreaming = false
            self.streamingRole = .none
        }
    }

    // ★ 追加: デコード済みのシグナリングメッセージを処理するメソッド
    /// 複数ピア対応版のシグナリングメッセージ処理
    func processDecodedSignalingMessage(
        _ msg: WebRTCSignalingMessage,
        from peerID: MCPeerID
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch msg.type {
            case .offer:
                // ① 自分が今「送信中(sender)」なら、まずすべて切断
                if self.streamingRole == .sender {
                    self.disconnect()
                }

                // ② この peer 用に PeerConnection を取得 or 新規作成
                let pc = self.peerConnections[peerID] ?? self.configureConnection(for: peerID)

                // ③ 受信モード (receiver) に切り替え
                self.streamingRole = .receiver
                self.isStreaming   = true

                // ④ SDP を設定して Answer を返す
                if let sdp = msg.sdp {
                    let desc = RTCSessionDescription(type: .offer, sdp: sdp)
                    pc.setRemoteDescription(desc) { error in
                        if let e = error {
                            print("setRemoteDescription(offer) error:", e)
                            return
                        }
                        self.createAnswer(on: pc, to: peerID)
                    }
                }

            case .answer:
                // Answer は既存の PeerConnection がなければ無視
                guard
                    let pc = self.peerConnections[peerID],
                    let sdp = msg.sdp
                else { return }

                let desc = RTCSessionDescription(type: .answer, sdp: sdp)
                pc.setRemoteDescription(desc) { error in
                    if let e = error {
                        print("setRemoteDescription(answer) error:", e)
                    }
                }

            case .candidate:
                // ICE Candidate も同様に既存 PC が必要
                guard
                    let pc = self.peerConnections[peerID],
                    let c  = msg.candidate
                else { return }

                let ice = RTCIceCandidate(
                    sdp:             c.sdp,
                    sdpMLineIndex:   c.sdpMLineIndex,
                    sdpMid:          c.sdpMid
                )
                pc.add(ice) { error in
                    if let e = error {
                        print("addIceCandidate error:", e)
                    }
                }

            case .bye:
                // 相手からの切断通知は、その peer だけ閉じて辞書から削除
                if let pc = self.peerConnections[peerID] {
                    pc.close()
                    self.peerConnections.removeValue(forKey: peerID)
                    self.remoteVideoTracks.removeValue(forKey: peerID)
                }
                // さらに「自分も受信モードを終了」して通常モードに戻す
                self.disconnect()
            }
        }
    }

    // MARK: - Private Methods (Offer/Answer)

    private func createOffer(on pc: RTCPeerConnection, to peer: MCPeerID) {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { error in
                guard error == nil else { return }
                self.sendSignalingMessage(
                    type: .offer,
                    sdp: sdp.sdp,
                    streamRole: self.streamingRole,
                    to: peer
                )
            }
        }
    }

    private func createAnswer(on pc: RTCPeerConnection, to peer: MCPeerID) {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
            optionalConstraints: nil
        )
        pc.answer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { error in
                guard error == nil else { return }
                self.sendSignalingMessage(
                    type: .answer,
                    sdp: sdp.sdp,
                    to: peer
                )
            }
        }
    }

    // MARK: - Cleanup

    private func cleanupResources() {
        print("WebRTCManager: Cleaning up WebRTC resources.")
        
        // すべてのリモートトラックをクリア
        DispatchQueue.main.async {
            self.remoteVideoTracks.removeAll()
        }
        
        // ピアごとの PeerConnection をクリーンアップ
        for (peer, pc) in peerConnections {
            print("WebRTCManager: Cleaning up connection for peer \(peer.displayName).")
            
            // トランシーバー停止
            for transceiver in pc.transceivers {
                transceiver.stopInternal()
            }
            // 送信トラック削除
            for sender in pc.senders {
                pc.removeTrack(sender)
            }
            // デリゲート解除とクローズ
            pc.delegate = nil
            pc.close()
        }
        
        // 辞書を空に
        peerConnections.removeAll()
        
        print("WebRTCManager: All WebRTC resources cleaned up.")
    }

    // MARK: - Signaling Helper

    // シグナリングメッセージ送信（デリゲート経由）- 修正版
    private func sendSignalingMessage(
        type: WebRTCSignalingType,
        sdp: String? = nil,
        candidate: IceCandidateData? = nil,
        streamRole: StreamingRole? = nil,
        to peer: MCPeerID
    ) {
        let msg = WebRTCSignalingMessage(type: type, sdp: sdp, candidate: candidate, streamRole: streamRole)
        guard let data = try? JSONEncoder().encode(msg) else { return }
        delegate?.webRTCManager(self, needsToSendSignalingMessage: data, targetPeer: peer)
    }

}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCManager: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        // 対応するピアを特定
        guard let peer = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            print("WebRTCManager: ピア接続の状態変更があったが、該当ピアが見つかりません")
            return
        }
        
        let isConnected = (newState == .connected)
        print("WebRTCManager: ピア \(peer.displayName) の接続状態が変更: \(newState)")
        
        switch newState {
        case .connected:
            connectionStatus[peer] = .connected
            // 接続タイマーを停止
            connectionTimers[peer]?.invalidate()
            connectionTimers.removeValue(forKey: peer)
            
        case .connecting:
            connectionStatus[peer] = .connecting
            // 接続タイムアウトを設定（20秒）
            startConnectionTimeout(for: peer)
            
        case .disconnected:
            connectionStatus[peer] = .reconnecting
            // 再接続を試みる
            print("WebRTCManager: ピア \(peer.displayName) との接続が切断されました。再接続を試みます")
            // 15秒間再接続を試みる
            startReconnectionTimer(for: peer)
            
        case .failed:
            connectionStatus[peer] = .failed
            print("WebRTCManager: ピア \(peer.displayName) との接続が失敗しました")
            // この特定の接続をリセット
            resetConnection(for: peer)
            
        case .closed:
            connectionStatus[peer] = .closed
            // 完全にクリーンアップ
            cleanupConnection(for: peer)
            
        default:
            break
        }
        
        // デリゲートに通知
        DispatchQueue.main.async {
            self.isConnected = isConnected
            self.delegate?.webRTCManagerDidChangeConnectionState(self, isConnected: isConnected)
        }
    }
    
    private func startConnectionTimeout(for peer: MCPeerID) {
        // 既存のタイマーをキャンセル
        connectionTimers[peer]?.invalidate()
        
        // 新しいタイマーを設定
        let timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if let status = self.connectionStatus[peer], status == .connecting {
                print("WebRTCManager: ピア \(peer.displayName) との接続がタイムアウトしました")
                self.handleConnectionTimeout(for: peer)
            }
        }
        
        connectionTimers[peer] = timer
    }

    // 接続タイムアウト処理
    private func handleConnectionTimeout(for peer: MCPeerID) {
        // 接続をリセット
        resetConnection(for: peer)
        
        // 開発者にデバッグ情報を提供
        print("WebRTCManager: 接続タイムアウト - ICE候補の収集が不十分な可能性があります")
        
        // デリゲートに通知
        DispatchQueue.main.async {
            self.delegate?.webRTCManager(self, didFailWithTimeout: peer)
        }
    }

    // 再接続タイマー
    private func startReconnectionTimer(for peer: MCPeerID) {
        // 既存のタイマーをキャンセル
        connectionTimers[peer]?.invalidate()
        
        // 新しいタイマーを設定
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if let status = self.connectionStatus[peer], status == .reconnecting {
                print("WebRTCManager: ピア \(peer.displayName) との再接続がタイムアウトしました")
                // 完全に切断
                self.resetConnection(for: peer)
            }
        }
        
        connectionTimers[peer] = timer
    }

    // 特定の接続をリセット
    private func resetConnection(for peer: MCPeerID) {
        guard let pc = peerConnections[peer] else { return }
        
        // 既存の接続をクローズ
        pc.close()
        
        // 状態をクリーンアップ
        peerConnections.removeValue(forKey: peer)
        remoteVideoTracks.removeValue(forKey: peer)
        connectionStatus.removeValue(forKey: peer)
        
        // タイマーをクリア
        connectionTimers[peer]?.invalidate()
        connectionTimers.removeValue(forKey: peer)
        
        // すべての接続が終了した場合、状態をリセット
        if peerConnections.isEmpty {
            DispatchQueue.main.async {
                self.streamingRole = .none
                self.isStreaming = false
            }
        }
    }

    // 特定の接続をクリーンアップ
    private func cleanupConnection(for peer: MCPeerID) {
        resetConnection(for: peer)
        
        // シグナリングで「Bye」を送信
        sendSignalingMessage(type: .bye, to: peer)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove candidates: [RTCIceCandidate]) {
    }

    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .disconnected || newState == .failed || newState == .closed {
            // どの peer が切れたか？
            if let peer = peerConnections.first(where: { $0.value === pc })?.key {
                // こいつの接続リストから削除
                peerConnections.removeValue(forKey: peer)
                remoteVideoTracks.removeValue(forKey: peer)
            }
            // 全部切れたら通常モードへ
            if peerConnections.isEmpty {
                DispatchQueue.main.async {
                    self.streamingRole = .none
                    self.isStreaming = false
                }
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let peer = peerConnections.first(where: { $0.value === peerConnection })?.key
        else { return }

        let candidateData = IceCandidateData(
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdp: candidate.sdp
        )
        sendSignalingMessage(
            type: .candidate,
            candidate: candidateData,
            to: peer
        )
    }


    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceGatheringState) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange stateChanged: RTCSignalingState) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd stream: RTCMediaStream) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove stream: RTCMediaStream) {
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd receiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        guard let videoTrack = receiver.track as? RTCVideoTrack,
              let peer = peerConnections.first(where: { $0.value === peerConnection })?.key
        else { return }

        DispatchQueue.main.async {
            self.remoteVideoTracks[peer] = videoTrack
            self.delegate?.webRTCManagerDidReceiveRemoteVideoTrack(self,
                                                                   track: videoTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didOpen dataChannel: RTCDataChannel) {
    }
}
