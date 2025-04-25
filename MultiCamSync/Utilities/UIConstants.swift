//
//  UIConstants.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/03/30.
//

import SwiftUI

class UIConstants {
    static let shared = UIConstants()
    
    let bottomPadding: CGFloat = 20 // 固定値
    var topPadding: CGFloat = 0 // 動的に計算される値
    var previewHeight: CGFloat = 0 // 動的に計算される値
    
    private init() {}
    
    func updateSizes(screenSize: CGSize) {
        DispatchQueue.main.async {
            self.previewHeight = screenSize.width * 16/9
            let totalPadding = screenSize.height - self.previewHeight
            self.topPadding = totalPadding - self.bottomPadding
        }
    }
}
