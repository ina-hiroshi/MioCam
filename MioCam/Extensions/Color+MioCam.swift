//
//  Color+MioCam.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI

extension Color {
    // MARK: - Background Colors
    
    /// プライマリ背景色（ライト: #FFF8F0, ダーク: #1C1C1E）
    static let mioPrimary = Color("MioPrimary")
    
    /// セカンダリ背景色（ライト: #FFFFFF, ダーク: #2C2C2E）
    static let mioSecondaryBg = Color("MioSecondaryBg")
    
    // MARK: - Text Colors
    
    /// プライマリテキスト色（ライト: #2D2D2D, ダーク: #F5F5F5）
    static let mioTextPrimary = Color("MioTextPrimary")
    
    /// セカンダリテキスト色（共通: #8E8E93）
    static let mioTextSecondary = Color("MioTextSecondary")
    
    // MARK: - Accent Colors
    
    /// アクセントカラー（メイン）（ライト: #FF9F6A, ダーク: #FFB088）
    static let mioAccent = Color("MioAccent")
    
    /// アクセントカラー（サブ）（ライト: #7EC8C8, ダーク: #8ED8D8）
    static let mioAccentSub = Color("MioAccentSub")
    
    // MARK: - Status Colors
    
    /// 成功/オンライン色（共通: #6FCF97）
    static let mioSuccess = Color("MioSuccess")
    
    /// 警告色（共通: #F2C94C）
    static let mioWarning = Color("MioWarning")
    
    /// エラー/オフライン色（共通: #EB5757）
    static let mioError = Color("MioError")
}
