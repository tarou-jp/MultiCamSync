//
//  ControlsView.swift
//  SwingVisionPro
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

struct ControlsView: View {
    
    var body: some View {
        VStack {
            // ヘッダー部分
            HeaderBarView()
            
            Spacer()
            
            // ズームコントロール
            ZoomControlView()
            
            // フッター部分
            FooterBarView()
        }
        .padding(.vertical, 20)
    }
}
