//
//  CameraManagerDelegate.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/04/03.
//

import Foundation
import AVFoundation

protocol CameraManagerDelegate: AnyObject {
    // 録画関連の通知
    func cameraManagerDidStartRecording(_ manager: CameraManager, at url: URL)
    func cameraManagerDidFinishRecording(_ manager: CameraManager, to url: URL)
    func cameraManagerDidFailRecording(_ manager: CameraManager, with error: Error)

    // カメラ状態変更通知
    func cameraManagerDidChangeAuthorizationStatus(_ manager: CameraManager, isAuthorized: Bool)
    func cameraManagerDidUpdateAvailableSettings(_ manager: CameraManager)
    func cameraManagerDidChangeZoomFactor(_ manager: CameraManager, to factor: CGFloat)
    
    // 設定更新の通知
    func cameraManagerDidUpdateSettings(_ manager: CameraManager, resolution: CameraResolution, frameRate: CameraFrameRate)
    
    // ビデオフレーム取得の通知（WebRTC連携用）
    func cameraManager(_ manager: CameraManager, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
}

// デフォルト実装を提供してオプショナルにする
extension CameraManagerDelegate {
    func cameraManagerDidStartRecording(_ manager: CameraManager, at url: URL) {}
    func cameraManagerDidFinishRecording(_ manager: CameraManager, to url: URL) {}
    func cameraManagerDidFailRecording(_ manager: CameraManager, with error: Error) {}
    func cameraManagerDidChangeAuthorizationStatus(_ manager: CameraManager, isAuthorized: Bool) {}
    func cameraManagerDidUpdateAvailableSettings(_ manager: CameraManager) {}
    func cameraManagerDidChangeZoomFactor(_ manager: CameraManager, to factor: CGFloat) {}
    func cameraManagerDidUpdateSettings(_ manager: CameraManager, resolution: CameraResolution, frameRate: CameraFrameRate) {}
    func cameraManager(_ manager: CameraManager, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {}
}
