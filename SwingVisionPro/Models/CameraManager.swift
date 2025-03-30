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

class CameraManager: NSObject, ObservableObject {
    // カメラの状態を発行
    @Published var isAuthorized = false
    @Published var isFrontCamera = false
    @Published var isFlashEnabled = false
    @Published var isRecording = false
    @Published var currentZoomFactor: CGFloat = 1.0
    
    // カメラセッション
    let captureSession = AVCaptureSession()
    var videoOutput = AVCaptureMovieFileOutput()
    var photoOutput = AVCapturePhotoOutput()
    
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
        case .notDetermined:
            // まだ許可を求めていない
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCaptureSession()
                    }
                }
            }
        case .denied, .restricted:
            // 拒否または制限されている
            self.isAuthorized = false
        @unknown default:
            self.isAuthorized = false
        }
    }
    
    // キャプチャセッションのセットアップ
    func setupCaptureSession() {
        // メインスレッドでの操作を避ける
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // 解像度設定
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 入力の設定
            self.setupInputs()
            
            // 出力の設定
            self.setupOutputs()
            
            self.captureSession.commitConfiguration()
            
            // セッション開始
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    // カメラ入力のセットアップ
    private func setupInputs() {
        // 既存の入力を削除
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        
        // カメラデバイスの選択
        let deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        
        guard let camera = AVCaptureDevice.default(deviceType, for: .video, position: position) else {
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
        // 既存の出力を削除
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
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
    
    // カメラの切り替え
    func switchCamera() {
        isFrontCamera.toggle()
        setupCaptureSession()
    }
    
    // ズーム設定
    func setZoom(factor: CGFloat) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let camera = self.currentCamera else { return }
            
            do {
                try camera.lockForConfiguration()
                
                // ズーム範囲内かチェック
                let minZoom: CGFloat = 1.0
                let maxZoom: CGFloat = camera.activeFormat.videoMaxZoomFactor
                let clampedFactor = min(max(factor, minZoom), maxZoom)
                
                camera.videoZoomFactor = clampedFactor
                camera.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.currentZoomFactor = clampedFactor
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
}

// AVCaptureFileOutputRecordingDelegate の実装
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            // 録画開始通知
            print("録画開始: \(fileURL.path)")
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("録画エラー: \(error.localizedDescription)")
                return
            }
            
            // 録画完了通知
            print("録画完了: \(outputFileURL.path)")
            
            // ここでアルバムに保存などの処理を行う
            UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        }
    }
}
