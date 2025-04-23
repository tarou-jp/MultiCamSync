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
   case fps120 = 120
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
    
   private var supportedFPSByResolution: [CameraResolution:Set<CameraFrameRate>] = [:]
   
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

        // back／front 用のカメラを明示的に取得
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        // 広角カメラを優先
        let deviceTypesForPosition: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTripleCamera,
            .builtInDualWideCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypesForPosition,
            mediaType: .video,
            position: position
        )
        guard let camera = discovery.devices.first else {
            print("該当するカメラが見つかりません")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentCamera = camera
            }
        } catch {
            print("カメラ入力の追加に失敗: \(error.localizedDescription)")
        }

        // オーディオ入力はそのまま
        if let audio = AVCaptureDevice.default(for: .audio),
           let audioIn = try? AVCaptureDeviceInput(device: audio),
           captureSession.canAddInput(audioIn) {
            captureSession.addInput(audioIn)
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

        var resSet = Set<CameraResolution>()
        var fpsMap: [CameraResolution: Set<CameraFrameRate>] = [:]

        // フォーマット走査
        for format in camera.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let res: CameraResolution? = {
                if (dims.width == 3840 && dims.height == 2160)
                 || (dims.width == 2160 && dims.height == 3840) {
                    return ._4k
                }
                if (dims.width == 1920 && dims.height == 1080)
                 || (dims.width == 1080 && dims.height == 1920) {
                    return .hd
                }
                return nil
            }()
            guard let resolution = res else { continue }
            resSet.insert(resolution)

            // この解像度で使える fps を収集
            for range in format.videoSupportedFrameRateRanges {
                for fps in CameraFrameRate.allCases {
                    if range.minFrameRate <= Double(fps.rawValue)
                       && Double(fps.rawValue) <= range.maxFrameRate {
                        fpsMap[resolution, default: []].insert(fps)
                    }
                }
            }
        }

        // store map and resolutions
        DispatchQueue.main.async {
            self.availableResolutions = [.hd, ._4k].filter { resSet.contains($0) }
            self.supportedFPSByResolution = fpsMap

            // **ここを変更**：currentResolution 用の fps のみを表示
            let fpsSetForCurrent = fpsMap[self.currentResolution] ?? []
            self.availableFrameRates = fpsSetForCurrent
                .sorted { $0.rawValue < $1.rawValue }

            self.delegate?.cameraManagerDidUpdateAvailableSettings(self)
        }
    }

    // 解像度選択 UI から呼ぶ
    func resolutionDidChange(to newResolution: CameraResolution) {
        currentResolution = newResolution
        // 選び直した解像度用 fps リストを再セット
        let fpsSet = supportedFPSByResolution[newResolution] ?? []
        DispatchQueue.main.async {
            self.availableFrameRates = fpsSet.sorted { $0.rawValue < $1.rawValue }
            // currentFrameRate がリスト外なら先頭にリセット
            if !fpsSet.contains(self.currentFrameRate),
               let first = fpsSet.sorted(by: { $0.rawValue < $1.rawValue }).first {
                self.currentFrameRate = first
            }
        }
    }

   
    // 解像度とフレームレートを同時にセット
    func setResolution(_ resolution: CameraResolution, frameRate: CameraFrameRate) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let device = self.currentCamera else { return }
            let desiredFps = Double(frameRate.rawValue)
            let duration = CMTime(value: 1, timescale: CMTimeScale(desiredFps))

            // 1) セッション・デバイス両方の設定をまとめて行う
            self.captureSession.beginConfiguration()

            // セッションを inputPriority に
            self.captureSession.sessionPreset = .inputPriority

            // フォーマット選択
            if let targetFormat = device.formats.first(where: { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let matchesRes: Bool = {
                    switch resolution {
                    case .hd:  return dims.width == 1920 && dims.height == 1080
                    case ._4k: return dims.width == 3840 && dims.height == 2160
                    }
                }()
                let matchesFps = format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= desiredFps && desiredFps <= $0.maxFrameRate
                }
                return matchesRes && matchesFps
            }) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = targetFormat
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    device.unlockForConfiguration()
                } catch {
                    print("⚠️ フォーマット設定失敗: \(error)")
                }
            } else {
                // フォールバック
                if resolution == ._4k && frameRate == .fps30,
                   self.captureSession.canSetSessionPreset(.hd4K3840x2160) {
                    self.captureSession.sessionPreset = .hd4K3840x2160
                } else {
                    self.captureSession.sessionPreset = .hd1920x1080
                }
                print("⚠️ 対応フォーマット未検出: \(resolution) @ \(frameRate.rawValue)fps")
            }

            // セッション設定反映
            self.captureSession.commitConfiguration()

            // 2) セッションを再起動して設定を確実に有効化
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.captureSession.startRunning()

            // 3) デバッグ出力：アクティブフォーマットとフレーム期間を確認
            let activeDims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let minDur = device.activeVideoMinFrameDuration
            let maxDur = device.activeVideoMaxFrameDuration
            print("🔧 Active Format: \(activeDims.width)x\(activeDims.height), " +
                  "minFrameDuration=1/\(minDur.timescale) maxFrameDuration=1/\(maxDur.timescale)")

            // 4) UI 更新
            DispatchQueue.main.async {
                self.currentResolution = resolution
                self.currentFrameRate  = frameRate
                self.delegate?.cameraManagerDidUpdateSettings(self,
                                                              resolution: resolution,
                                                              frameRate: frameRate)
            }
        }
    }
   
   // 解像度をタップで切り替える例
    func switchResolution() {
        guard !availableResolutions.isEmpty else { return }
        // 次の解像度を計算
        if let idx = availableResolutions.firstIndex(of: currentResolution) {
            let next = availableResolutions[(idx + 1) % availableResolutions.count]
            // 1) 解像度を更新
            currentResolution = next
            // 2) その解像度に対応する fps のみを availableFrameRates にセット
            let fpsSet = supportedFPSByResolution[next] ?? []
            availableFrameRates = fpsSet.sorted { $0.rawValue < $1.rawValue }
            // 3) もし currentFrameRate が now unsupported ならリセット
            if !fpsSet.contains(currentFrameRate) {
                currentFrameRate = availableFrameRates.first ?? .fps30
            }
            // 4) カメラに反映
            setResolution(currentResolution, frameRate: currentFrameRate)
        }
    }

    /// フレームレートを切り替え、対応可能な fps のみをループしてから実際の設定へ
    func switchFrameRate() {
        guard !availableFrameRates.isEmpty else { return }
        if let idx = availableFrameRates.firstIndex(of: currentFrameRate) {
            let next = availableFrameRates[(idx + 1) % availableFrameRates.count]
            currentFrameRate = next
            setResolution(currentResolution, frameRate: next)
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
