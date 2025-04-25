//
//  TimeManager.swift
//  MultiCamSync
//
//  Created by 糸久秀喜 on 2025/04/25.
//

import Foundation
import Kronos

class TimeManager {
    static let shared = TimeManager()
    
    // 最後の同期時刻を記録
    private(set) var lastSyncTime: Date?
    private(set) var isSynced = false
    
    private init() {
        // アプリ起動時に自動同期
        synchronize { _ in }
    }
    
    // 時計を同期する
    func synchronize(completion: @escaping (Bool) -> Void) {
        Clock.sync { date, offset in
            // 最初の応答を受信したとき
            self.lastSyncTime = Date()
            self.isSynced = true
            print("NTP初期同期完了: 日時 = \(date), オフセット = \(offset)秒")
            completion(true)
        } completion: { date, offset in
            // すべてのNTPサーバーからの応答が処理された後
            if let date = date, let offset = offset {
                print("NTP完全同期完了: 日時 = \(date), オフセット = \(offset)秒")
            } else {
                print("NTP同期失敗")
            }
        }
    }
    
    // NTP補正済みの現在時刻を取得
    func getCorrectedTime() -> TimeInterval? {
        return Clock.timestamp
    }
    
    // 同期が必要かどうかを判断（最後の同期から1時間以上経過）
    func needsSync() -> Bool {
        guard let lastSync = lastSyncTime else { return true }
        return Date().timeIntervalSince(lastSync) > 3600
    }
    
    // NTP補正済みの現在時刻をDateオブジェクトとして取得
    func getCurrentDate() -> Date? {
        return Clock.now
    }
}
