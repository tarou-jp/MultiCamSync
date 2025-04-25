//
//  Comparable+Clamp.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/04/24.
//

import Foundation

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
