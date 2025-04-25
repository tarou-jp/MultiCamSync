//
//  CameraManager.swift
//  MultiCamSync
//

import AVFoundation
import Combine
import UIKit

// MARK: - Types
enum CameraResolution: String, CaseIterable { case hd = "HD", _4k = "4K" }
enum CameraFrameRate : Int,   CaseIterable { case fps24 = 24, fps30 = 30, fps60 = 60, fps120 = 120 }

// MARK: - Manager
final class CameraManager: NSObject, ObservableObject {

    // Published
    @Published var isAuthorized = false
    @Published var isFrontCamera = false
    @Published var isRecording = false
    @Published var displayZoomFactor:  CGFloat = 1
    @Published var currentZoomFactor:  CGFloat = 1
    @Published var currentResolution:  CameraResolution = .hd
    @Published var currentFrameRate:    CameraFrameRate  = .fps30
    @Published var availableResolutions: [CameraResolution] = []
    @Published var availableFrameRates : [CameraFrameRate]  = []

    weak var delegate: CameraManagerDelegate?

    // Session
    let captureSession = AVCaptureSession()
    private let videoOut = AVCaptureMovieFileOutput()
    private let photoOut = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")

    // Devices
    private var wideDev:  AVCaptureDevice?
    private var ultraDev: AVCaptureDevice?
    private var currentDev: AVCaptureDevice?

    // Maps
    private var fpsByRes: [CameraResolution:Set<CameraFrameRate>] = [:]

    // MARK: Init
    override init() { super.init(); requestPermission() }

    private func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: isAuthorized = true; setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { self?.finishAuth(ok) }
            }
        default: finishAuth(false)
        }
    }
    private func finishAuth(_ ok: Bool) {
        isAuthorized = ok
        delegate?.cameraManagerDidChangeAuthorizationStatus(self, isAuthorized: ok)
        if ok { setupSession() }
    }

    // MARK: Session

    private func setupSession() {
        sessionQueue.async { [self] in
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .inputPriority
            configureInputs()
            if captureSession.canAddOutput(videoOut)  { captureSession.addOutput(videoOut)  }
            if captureSession.canAddOutput(photoOut) { captureSession.addOutput(photoOut) }
            captureSession.commitConfiguration()
            captureSession.startRunning()

            // UI 更新だけメインに返す
            DispatchQueue.main.async { self.updateResFpsLists() }
        }
    }

    private func configureInputs() {
        captureSession.inputs.forEach { captureSession.removeInput($0) }

        let pos: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        let ds = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video, position: pos)

        ds.devices.forEach {
            if $0.deviceType == .builtInWideAngleCamera { wideDev = $0 }
            if $0.deviceType == .builtInUltraWideCamera { ultraDev = $0 }
        }

        // front カメラ側に超広角は無いので wide 固定
        if isFrontCamera, let w = wideDev { addDevice(w) }
        else if let w = wideDev { addDevice(w) }

        // audio
        if let mic = AVCaptureDevice.default(for: .audio),
           let micIn = try? AVCaptureDeviceInput(device: mic),
           captureSession.canAddInput(micIn) { captureSession.addInput(micIn) }
    }

    private func addDevice(_ dev: AVCaptureDevice) {
        if let old = captureSession.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) }) {
            captureSession.removeInput(old)
        }
        if let inp = try? AVCaptureDeviceInput(device: dev),
           captureSession.canAddInput(inp) { captureSession.addInput(inp) }
        currentDev = dev
    }

    // MARK: Zoom
    func setZoom(factor requested: CGFloat) {
        guard let w = wideDev else { return }

        // front カメラは 1× 未満禁止
        let minDisp = isFrontCamera ? 1.0 : 0.5
        var disp = max(minDisp, requested)

        // back のみ 0.5× レンズ切替
        if !isFrontCamera, let u = ultraDev {
            if disp < 1.0, currentDev !== u { switchDevice(to: u) }
            if disp >= 1.0, currentDev !== w { switchDevice(to: w) }
        }

        guard let cam = currentDev else { return }

        let maxDisp = min(10.0, cam.maxZoomUI)
        disp = min(disp, maxDisp)

        let mul   = cam.zoomMultiplier
        let act   = cam.deviceType == .builtInUltraWideCamera
                  ? (1 + (disp - 0.5) / 0.5) / mul
                  : disp / mul
        let safe  = min(act, cam.activeFormat.videoMaxZoomFactor)

        try? cam.lockForConfiguration(); cam.videoZoomFactor = safe; cam.unlockForConfiguration()

        let final = cam.deviceType == .builtInUltraWideCamera
                  ? 0.5 + (safe * mul - 1) * 0.5
                  : safe * mul

        displayZoomFactor = final
        currentZoomFactor = safe * mul
        delegate?.cameraManagerDidChangeZoomFactor(self, to: final)
    }

    private func switchDevice(to dev: AVCaptureDevice) {
        captureSession.beginConfiguration()
        addDevice(dev)
        captureSession.commitConfiguration()
    }

    // MARK: Resolution / FPS
    func switchResolution() {
        currentResolution = currentResolution == .hd ? ._4k : .hd
        apply(res: currentResolution, fps: currentFrameRate)
    }

    func switchFrameRate() {
        guard let list = fpsByRes[currentResolution]?.sorted(by: { $0.rawValue < $1.rawValue }),
              let idx  = list.firstIndex(of: currentFrameRate) else { return }
        apply(res: currentResolution, fps: list[(idx + 1) % list.count])
    }

    func switchCamera() {
        isFrontCamera.toggle()
        captureSession.beginConfiguration()
        configureInputs()
        captureSession.commitConfiguration()
        updateResFpsLists()
    }

    private func apply(res: CameraResolution, fps: CameraFrameRate) {
        guard let cam = currentDev else { return }
        let fpsD = Double(fps.rawValue)
        let dur  = CMTime(value: 1, timescale: CMTimeScale(fpsD))

        captureSession.beginConfiguration()
        if let fmt = cam.formats.first(where: { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let rOK = (res == .hd && d.width == 1920 && d.height == 1080) ||
                      (res == ._4k && d.width == 3840 && d.height == 2160)
            let fOK = f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fpsD && fpsD <= $0.maxFrameRate }
            return rOK && fOK
        }) {
            try? cam.lockForConfiguration()
            cam.activeFormat = fmt
            cam.activeVideoMinFrameDuration = dur
            cam.activeVideoMaxFrameDuration = dur
            cam.unlockForConfiguration()
        }
        captureSession.commitConfiguration()

        currentResolution = res
        currentFrameRate  = fps
        delegate?.cameraManagerDidUpdateSettings(self, resolution: res, frameRate: fps)
        updateResFpsLists()
    }

    private func updateResFpsLists() {
        guard let cam = currentDev else { return }
        var map: [CameraResolution:Set<CameraFrameRate>] = [:]
        cam.formats.forEach { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let r: CameraResolution? = {
                switch (d.width, d.height) {
                case (3840,2160),(2160,3840): return ._4k
                case (1920,1080),(1080,1920): return .hd
                default: return nil
                }
            }()
            guard let res = r else { return }
            f.videoSupportedFrameRateRanges.forEach { rng in
                CameraFrameRate.allCases.forEach { fr in
                    if rng.minFrameRate <= Double(fr.rawValue),
                       Double(fr.rawValue) <= rng.maxFrameRate {
                        map[res, default: []].insert(fr)
                    }
                }
            }
        }
        fpsByRes = map
        availableResolutions = [.hd, ._4k].filter { map[$0] != nil }
        availableFrameRates  = (map[currentResolution] ?? []).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: Recording
    func startRecording() {
        let url = FileManager.default.temporaryDirectory
                     .appendingPathComponent("\(Date().timeIntervalSince1970).mov")
        try? FileManager.default.removeItem(at: url)

        isRecording = true
        videoOut.startRecording(to: url, recordingDelegate: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            if self.isRecording, self.videoOut.recordedDuration == .zero {
                print("⚠️ didStartRecording が来ない → 失敗リカバリ")
                self.isRecording = false
            }
        }
    }

    func stopRecording() {
        if videoOut.isRecording { videoOut.stopRecording() }
    }
}

// MARK: Helpers
private extension AVCaptureDevice {
    var zoomMultiplier: CGFloat {
        if #available(iOS 18.0, *) { return displayVideoZoomFactorMultiplier } else { return 1 }
    }
    var maxZoomUI: CGFloat {
        if #available(iOS 15.0, *), deviceType != .builtInUltraWideCamera {
            return maxAvailableVideoZoomFactor
        }
        return activeFormat.videoMaxZoomFactor
    }
}

// MARK: Delegates
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            print("録画開始: \(fileURL.path)")
            self.delegate?.cameraManagerDidStartRecording(self, at: fileURL)
        }
    }
    
    func fileOutput(_: AVCaptureFileOutput,
                         didFinishRecordingTo url: URL,
                         from _: [AVCaptureConnection],
                         error: Error?) {
        isRecording = false
        
        DispatchQueue.main.async {
            if let e = error {
                print("録画エラー: \(e.localizedDescription)")
                self.delegate?.cameraManagerDidFailRecording(self, with: e)
                return
            }

            print("録画完了: \(url.path)")
            self.delegate?.cameraManagerDidFinishRecording(self, to: url)

            // ★ 元コードと同じくカメラロールへ保存
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
        }
    }
}
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput,
                       didOutput s: CMSampleBuffer,
                       from _: AVCaptureConnection) {
        delegate?.cameraManager(self, didOutputSampleBuffer: s)
    }
}
