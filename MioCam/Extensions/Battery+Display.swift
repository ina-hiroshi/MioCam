//
//  Battery+Display.swift
//  MioCam
//
//  バッテリー表示用の共通ユーティリティ（iOS）
//

import SwiftUI

enum BatteryDisplay {
    /// バッテリーレベルに応じたSF Symbol名を返す
    static func icon(level: Int) -> String {
        switch level {
        case 0..<10:
            return "battery.0"
        case 10..<25:
            return "battery.25"
        case 25..<50:
            return "battery.50"
        case 50..<75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    /// バッテリーレベルに応じた色を返す
    /// - Parameters:
    ///   - level: バッテリーレベル（0-100）
    ///   - defaultColor: 正常時の色（デフォルト: mioTextPrimary）
    static func color(level: Int, defaultColor: Color = .mioTextPrimary) -> Color {
        switch level {
        case 0..<10:
            return .mioError
        case 10..<20:
            return .mioWarning
        default:
            return defaultColor
        }
    }
}
