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
                    
                    CameraPreviewView(session: cameraManager.captureSession)
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
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.setupPreviewLayer(with: session)
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // ビューのサイズが変わったときに自動的に更新される
    }
    
    class PreviewUIView: UIView {
        private var previewLayer: AVCaptureVideoPreviewLayer?
        
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
