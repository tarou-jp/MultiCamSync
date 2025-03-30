//
//  CameraView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @State private var lastPinchScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 黒背景を全画面に
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 直接計算
                let previewHeight = geometry.size.width * 16/9
                let bottomPadding: CGFloat = 20
                let totalPadding = max(0, geometry.size.height - previewHeight)
                let topPadding = max(0, totalPadding - bottomPadding)
                
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: topPadding)
                    
                    CameraPreviewView(
                        session: cameraManager.captureSession,
                        onPinch: { scale in
                            handlePinch(scale: scale)
                        }
                    )
                    .frame(width: geometry.size.width, height: previewHeight)
                    
                    Spacer()
                        .frame(height: bottomPadding)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        UIConstants.shared.previewHeight = previewHeight
                        UIConstants.shared.topPadding = topPadding
                    }
                }
                .onChange(of: geometry.size) { _, newSize in
                    // サイズ変更時も値を更新
                    let newPreviewHeight = newSize.width * 16/9
                    let newTotalPadding = max(0, newSize.height - newPreviewHeight)
                    let newTopPadding = max(0, newTotalPadding - bottomPadding)
                    
                    UIConstants.shared.previewHeight = newPreviewHeight
                    UIConstants.shared.topPadding = newTopPadding
                }
                
                // カメラ権限がない場合の表示
                if !cameraManager.isAuthorized {
                    VStack {
                        Text("カメラへのアクセスが許可されていません")
                            .foregroundColor(.white)
                            .padding()
                        
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
        }
    }
    
    private func handlePinch(scale: CGFloat) {
        if scale == 1.0 {
            lastPinchScale = 1.0
            return
        }
        
        let pinchFactor = scale / lastPinchScale
        lastPinchScale = scale
        
        let newZoomFactor = cameraManager.currentZoomFactor * pinchFactor
        
        cameraManager.setZoom(factor: newZoomFactor)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPinch: ((CGFloat) -> Void)?
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.setupPreviewLayer(with: session)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onPinch = onPinch
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPinch: onPinch)
    }
    
    class Coordinator: NSObject {
        var onPinch: ((CGFloat) -> Void)?
        
        init(onPinch: ((CGFloat) -> Void)? = nil) {
            self.onPinch = onPinch
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed || gesture.state == .ended {
                onPinch?(gesture.scale)
            }
        }
    }
    
    class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        override var layer: AVCaptureVideoPreviewLayer {
            return super.layer as! AVCaptureVideoPreviewLayer
        }
        
        func setupPreviewLayer(with session: AVCaptureSession) {
            layer.session = session
            layer.videoGravity = .resizeAspect
            
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }
    }
}
