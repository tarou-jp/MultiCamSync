//
//  CameraManager.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import Foundation
import AVFoundation
import Combine
import UIKit

enum CameraResolution: String, CaseIterable, Equatable {
   case hd = "HD"
   case _4k = "4K"
}

enum CameraFrameRate: Int, CaseIterable, Equatable {
   case fps24 = 24
   case fps30 = 30
   case fps60 = 60
}

class CameraManager: NSObject, ObservableObject {
   // デリゲート
   weak var delegate: CameraManagerDelegate?
   
   // カメラの状態を発行
   @Published var isAuthorized = false
   @Published var isFrontCamera = false
   @Published var isFlashEnabled = false
   @Published var isRecording = false
   
   @Published var currentZoomFactor: CGFloat = 1.0
   
   @Published var currentResolution: CameraResolution = .hd
   @Published var currentFrameRate: CameraFrameRate = .fps30
   @Published var availableResolutions: [CameraResolution] = []
   @Published var availableFrameRates: [CameraFrameRate] = []
   
   // カメラセッション
   let captureSession = AVCaptureSession()
   var videoOutput = AVCaptureMovieFileOutput()
   var photoOutput = AVCapturePhotoOutput()
   
   // ビデオデータ出力（WebRTCとの共有用）
   private var videoDataOutput: AVCaptureVideoDataOutput?
   private let videoDataOutputQueue = DispatchQueue(label: "videoDataOutputQueue", qos: .userInteractive)
   
   // 現在のデバイス
   var currentCamera: AVCaptureDevice?
   
   // 初期化
   override init() {
       super.init()
       checkPermission()
   }
   
   // カメラ権限チェック
   func checkPermission() {
       switch AVCaptureDevice.authorizationStatus(for: .video) {
       case .authorized:
           // すでに許可されている
           self.isAuthorized = true
           self.setupCaptureSession()
           self.delegate?.cameraManagerDidChangeAuthorizationStatus(self, isAuthorized: true)
       case .notDetermined:
           // まだ許可を求めていない
           AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
               DispatchQueue.main.async {
                   guard let self = self else { return }
                   self.isAuthorized = granted
                   if granted {
                       self.setupCaptureSession()
                   }
                   self.delegate?.cameraManagerDidChangeAuthorizationStatus(self, isAuthorized: granted)
               }
           }
       case .denied, .restricted:
           // 拒否または制限されている
           self.isAuthorized = false
           self.delegate?.cameraManagerDidChangeAuthorizationStatus(self, isAuthorized: false)
       @unknown default:
           self.isAuthorized = false
           self.delegate?.cameraManagerDidChangeAuthorizationStatus(self, isAuthorized: false)
       }
   }
   
   // キャプチャセッションのセットアップ
   func setupCaptureSession() {
       DispatchQueue.global(qos: .userInitiated).async { [weak self] in
           guard let self = self else { return }
           
           self.captureSession.beginConfiguration()
           // 解像度は後で setResolution() で設定するので、ひとまず .high とかにしておく
           if self.captureSession.canSetSessionPreset(.high) {
               self.captureSession.sessionPreset = .high
           }
           
           self.setupInputs()
           self.setupOutputs()
           self.setupVideoDataOutput() // 新たに追加したビデオデータ出力の設定
           self.captureSession.commitConfiguration()
           
           // セッション開始
           if !self.captureSession.isRunning {
               self.captureSession.startRunning()
           }
           
           // デバイスのサポート状況に応じて利用可能な解像度・fps を計算
           self.updateAvailableResAndFps()
           
           // ひとまずデフォルトを適用
           // （端末が対応していなければ fallback する処理を入れることも検討）
           DispatchQueue.main.async {
               self.setResolution(.hd, frameRate: .fps30)
           }
           
       }
   }
   
   // カメラ入力のセットアップ
   private func setupInputs() {
       // 既存の入力を削除
       for input in captureSession.inputs {
           captureSession.removeInput(input)
       }
       
       // マルチカメラがあれば優先して取得する
       let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
       let discoverySession = AVCaptureDevice.DiscoverySession(
           deviceTypes: deviceTypes,
           mediaType: .video,
           position: isFrontCamera ? .front : .back
       )
       
       guard let camera = discoverySession.devices.first else {
           print("該当するカメラが見つかりません")
           return
       }
       
       // 入力の追加
       do {
           let input = try AVCaptureDeviceInput(device: camera)
           if captureSession.canAddInput(input) {
               captureSession.addInput(input)
               currentCamera = camera
           }
       } catch {
           print("カメラ入力の追加に失敗: \(error.localizedDescription)")
       }
       
       // オーディオ入力の追加
       if let audioDevice = AVCaptureDevice.default(for: .audio),
          let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
          captureSession.canAddInput(audioInput) {
           captureSession.addInput(audioInput)
       }
   }
   
   // 出力のセットアップ
   private func setupOutputs() {
       // ビデオ出力と写真出力のみを削除（ビデオデータ出力は別途処理）
       for output in captureSession.outputs {
           if output === videoOutput || output === photoOutput {
               captureSession.removeOutput(output)
           }
       }
       
       // ビデオ出力の追加
       if captureSession.canAddOutput(videoOutput) {
           captureSession.addOutput(videoOutput)
       }
       
       // 写真出力の追加
       if captureSession.canAddOutput(photoOutput) {
           captureSession.addOutput(photoOutput)
       }
   }
   
   // ビデオデータ出力の設定（WebRTCとの共有用）
   private func setupVideoDataOutput() {
       // 既存のビデオデータ出力があれば削除
       if let existingOutput = videoDataOutput {
           captureSession.removeOutput(existingOutput)
       }
       
       // 新しいビデオデータ出力を作成
       let dataOutput = AVCaptureVideoDataOutput()
       dataOutput.videoSettings = [
           kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
       ]
       dataOutput.alwaysDiscardsLateVideoFrames = true
       dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
       
       if captureSession.canAddOutput(dataOutput) {
           captureSession.addOutput(dataOutput)
           
           // ビデオの向きを設定
           if let connection = dataOutput.connection(with: .video) {
               connection.videoOrientation = .portrait
               
               // 前面カメラの場合は水平反転
               if isFrontCamera {
                   connection.isVideoMirrored = true
               }
           }
           
           videoDataOutput = dataOutput
           print("CameraManager: ビデオデータ出力が設定されました")
       } else {
           print("CameraManager: ビデオデータ出力の追加に失敗しました")
       }
   }
    
    func pauseCaptureSession() {
        guard captureSession.isRunning else { return }
        
        print("CameraManager: カメラセッションを一時停止します")
        captureSession.stopRunning()
    }
    
    /// カメラセッションを再開する
    func resumeCaptureSession() {
        guard !captureSession.isRunning else { return }
        
        print("CameraManager: カメラセッションを再開します")
        captureSession.startRunning()
    }
   
   // デバイスが対応している解像度・fps をチェック
   private func updateAvailableResAndFps() {
       guard let camera = currentCamera else { return }
       
       // 解像度
       var possibleResolutions: [CameraResolution] = []
       
       // HD (1920x1080) が使えるか
       if captureSession.canSetSessionPreset(.hd1920x1080) {
           possibleResolutions.append(.hd)
       }
       
       // 4K (3840x2160) が使えるか
       if #available(iOS 11.0, *) {
           if captureSession.canSetSessionPreset(.hd4K3840x2160) {
               possibleResolutions.append(._4k)
           }
       }
       
       // fps
       // カメラの activeFormat がサポートするフレームレート範囲を取得
       let ranges = camera.activeFormat.videoSupportedFrameRateRanges
       
       var possibleFrameRates: Set<CameraFrameRate> = []
       for fps in CameraFrameRate.allCases {
           // 例: fps=24 のとき、range.minFrameRate <= 24 <= range.maxFrameRate ならOK
           if ranges.contains(where: {
               $0.minFrameRate <= Double(fps.rawValue) && Double(fps.rawValue) <= $0.maxFrameRate
           }) {
               possibleFrameRates.insert(fps)
           }
       }
       
       DispatchQueue.main.async {
           self.availableResolutions = possibleResolutions
           self.availableFrameRates = Array(possibleFrameRates).sorted {
               $0.rawValue < $1.rawValue
           }
           self.delegate?.cameraManagerDidUpdateAvailableSettings(self)
       }
   }
   
   // 解像度とフレームレートを同時にセット
   func setResolution(_ resolution: CameraResolution, frameRate: CameraFrameRate) {
       DispatchQueue.global(qos: .userInitiated).async {
           self.captureSession.beginConfiguration()
           
           // セッションプリセットを解像度に応じて設定
           switch resolution {
           case .hd:
               if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                   self.captureSession.sessionPreset = .hd1920x1080
               }
           case ._4k:
               if #available(iOS 11.0, *) {
                   if self.captureSession.canSetSessionPreset(.hd4K3840x2160) {
                       self.captureSession.sessionPreset = .hd4K3840x2160
                   }
               }
           }
           
           // フレームレート設定
           if let device = self.currentCamera {
               do {
                   try device.lockForConfiguration()
                   let desiredFps = frameRate.rawValue
                   device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFps))
                   device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(desiredFps))
                   device.unlockForConfiguration()
               } catch {
                   print("フレームレート設定失敗: \(error)")
               }
           }
           
           self.captureSession.commitConfiguration()
           
           DispatchQueue.main.async {
               self.currentResolution = resolution
               self.currentFrameRate = frameRate
               self.delegate?.cameraManagerDidUpdateSettings(self, resolution: resolution, frameRate: frameRate)
           }
       }
   }
   
   // 解像度をタップで切り替える例
   func switchResolution() {
       guard !availableResolutions.isEmpty else { return }
       if let idx = availableResolutions.firstIndex(of: currentResolution) {
           let nextIdx = (idx + 1) % availableResolutions.count
           let nextResolution = availableResolutions[nextIdx]
           setResolution(nextResolution, frameRate: currentFrameRate)
       }
   }
   
   // fps をタップで切り替える例
   func switchFrameRate() {
       guard !availableFrameRates.isEmpty else { return }
       if let idx = availableFrameRates.firstIndex(of: currentFrameRate) {
           let nextIdx = (idx + 1) % availableFrameRates.count
           let nextFps = availableFrameRates[nextIdx]
           setResolution(currentResolution, frameRate: nextFps)
       }
   }
   
   // カメラの切り替え
   func switchCamera() {
       isFrontCamera.toggle()
       setupCaptureSession()
   }
   
   // ズーム設定
   func setZoom(factor displayedZoom: CGFloat) {
       DispatchQueue.global(qos: .userInitiated).async { [weak self] in
           guard let self = self, let camera = self.currentCamera else { return }
           do {
               try camera.lockForConfiguration()
               
               let multiplier: CGFloat
               if #available(iOS 18.0, *) {
                   multiplier = camera.displayVideoZoomFactorMultiplier
               } else {
                   multiplier = 1.0
               }
               
               let desiredActualZoom = displayedZoom / multiplier
               
               let minActualZoom: CGFloat = 1.0
               let maxDesiredActualZoom = 10.0 / multiplier
               let maxActualZoom = min(camera.activeFormat.videoMaxZoomFactor, maxDesiredActualZoom)
               let clampedActualZoom = min(max(desiredActualZoom, minActualZoom), maxActualZoom)
               
               camera.videoZoomFactor = clampedActualZoom
               camera.unlockForConfiguration()
               
               DispatchQueue.main.async {
                   // UIに表示する値は、実際のズーム値に multiplier を掛け直す
                   let newZoomFactor = clampedActualZoom * multiplier
                   self.currentZoomFactor = newZoomFactor
                   self.delegate?.cameraManagerDidChangeZoomFactor(self, to: newZoomFactor)
               }
           } catch {
               print("ズーム設定エラー: \(error.localizedDescription)")
           }
       }
   }
   
   // 録画開始
   func startRecording() {
       // 録画開始のモック
       print("録画開始")
       
       let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
       let filename = "swingvision_\(Date().timeIntervalSince1970).mov"
       let fileURL = documentsPath.appendingPathComponent(filename)
       
       // 既存のファイルを削除
       if FileManager.default.fileExists(atPath: fileURL.path) {
           try? FileManager.default.removeItem(at: fileURL)
       }
       
       // 録画開始
       videoOutput.startRecording(to: fileURL, recordingDelegate: self)
       
       isRecording = true
   }
   
   // 録画停止
   func stopRecording() {
       // 録画停止
       if videoOutput.isRecording {
           videoOutput.stopRecording()
       }
       
       isRecording = false
   }
   
   // セッションをリセット（問題が発生した場合）
   func resetSession() {
       DispatchQueue.global(qos: .userInitiated).async { [weak self] in
           guard let self = self else { return }
           
           // セッションが実行中なら停止
           if self.captureSession.isRunning {
               self.captureSession.stopRunning()
           }
           
           // セッションを再設定
           self.setupCaptureSession()
       }
   }
   
   // キャプチャセッションが実行中かを確認し、必要に応じて再開
   func ensureCaptureSessionRunning() {
       if !captureSession.isRunning {
           DispatchQueue.global(qos: .userInitiated).async { [weak self] in
               self?.captureSession.startRunning()
               print("CameraManager: キャプチャセッションを再開しました")
           }
       }
   }
}

// AVCaptureFileOutputRecordingDelegate の実装
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
   func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
       DispatchQueue.main.async {
           // 録画開始通知
           print("録画開始: \(fileURL.path)")
           self.delegate?.cameraManagerDidStartRecording(self, at: fileURL)
       }
   }
   
   func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
       DispatchQueue.main.async {
           if let error = error {
               print("録画エラー: \(error.localizedDescription)")
               self.delegate?.cameraManagerDidFailRecording(self, with: error)
               return
           }
           
           // 録画完了通知
           print("録画完了: \(outputFileURL.path)")
           self.delegate?.cameraManagerDidFinishRecording(self, to: outputFileURL)
           
           // ここでアルバムに保存などの処理を行う
           UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
       }
   }
}

// AVCaptureVideoDataOutputSampleBufferDelegate の実装
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 取得したビデオフレームをデリゲートに通知
        delegate?.cameraManager(self, didOutputSampleBuffer: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // フレームがドロップされた場合（パフォーマンス問題など）
        print("CameraManager: フレームがドロップされました")
    }
}
