//
//  CountdownBackdropView.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/31.
//

import SwiftUI

struct CountdownBackdropView: View {
    let targetTime: TimeInterval
    @State private var currentTime: TimeInterval = Date().timeIntervalSince1970
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Text("残り時間")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("\(Int(ceil(max(targetTime - currentTime, 0))))")
                    .font(.system(size: 100, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date().timeIntervalSince1970
        }
    }
}
