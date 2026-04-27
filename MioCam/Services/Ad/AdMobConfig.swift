//
//  AdMobConfig.swift
//  MioCam
//
//  広告ユニット ID（Debug は Google テスト、Release は本番）。
//  AdMob アプリ ID（GADApplicationIdentifier）は Info.plist に本番値を記載（SDK が確実に読み取るため）。
//

import Foundation

enum AdMobConfig {
    /// バナー広告ユニット ID
    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    #else
    static let bannerUnitID = "ca-app-pub-3113647340712066/2491837202"
    #endif
}
