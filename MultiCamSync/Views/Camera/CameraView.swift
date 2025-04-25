//
//  CameraView.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    // 単一の環境オブジェクトとして AppCoordinator を利用
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var lastPinchScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 黒背景を全画面に
                Color.black.edgesIgnoringSafeArea(.all)
                
                // プレビューの高さを計算（16:9の比率）
                let previewHeight = geometry.size.width * 16/9
                let bottomPadding: CGFloat = 20
                let totalPadding = max(0, geometry.size.height - previewHeight)
                let topPadding = max(0, totalPadding - bottomPadding)
                
                VStack(spacing: 0) {
                    Spacer().frame(height: topPadding)
                    
                    CameraPreviewView(
                        session: appCoordinator.cameraManager.captureSession,
                        onPinch: { scale, state in
                            handlePinch(scale: scale, state: state)
                        }
                    )
                    .frame(width: geometry.size.width, height: previewHeight)
                    
                    Spacer().frame(height: bottomPadding)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        UIConstants.shared.previewHeight = previewHeight
                        UIConstants.shared.topPadding = topPadding
                    }
                }
                .onChange(of: geometry.size) { _, newSize in
                    let newPreviewHeight = newSize.width * 16/9
                    let newTotalPadding = max(0, newSize.height - newPreviewHeight)
                    let newTopPadding = max(0, newTotalPadding - bottomPadding)
                    
                    UIConstants.shared.previewHeight = newPreviewHeight
                    UIConstants.shared.topPadding = newTopPadding
                }
                
                // カメラ権限がない場合の表示
                if !appCoordinator.cameraManager.isAuthorized {
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
    
    private func handlePinch(scale: CGFloat, state: UIGestureRecognizer.State) {
        if state == .began {
            lastPinchScale = 1.0
            return
        }
        guard state == .changed else { return }

        let factor   = scale / lastPinchScale
        lastPinchScale = scale
        
        let raw      = appCoordinator.cameraManager.displayZoomFactor * factor
        let clamped  = raw.clamped(to: 0.5 ... 10.0)
        appCoordinator.cameraManager.setZoom(factor: clamped)
    }

}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func configure(with session: AVCaptureSession) {
        previewLayer.session       = session
        previewLayer.videoGravity  = .resizeAspect
        // セッションが止まっていたら起動
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }
    }
}

/// SwiftUI ラッパー
struct CameraPreviewView: UIViewRepresentable {
    typealias UIViewType = CameraPreviewUIView

    let session: AVCaptureSession
    var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?

    // UIView 作成
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.configure(with: session)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)
        return view
    }

    // UIView 更新
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.onPinch = onPinch
    }

    // Coordinator
    func makeCoordinator() -> Coordinator { Coordinator(onPinch: onPinch) }

    class Coordinator: NSObject {
        var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?
        init(onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?) {
            self.onPinch = onPinch
        }
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            onPinch?(g.scale, g.state)
        }
    }
}
