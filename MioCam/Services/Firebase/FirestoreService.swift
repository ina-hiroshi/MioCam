//
//  FirestoreService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import FirebaseFirestore

/// Firestore共通サービス（シングルトン管理・ヘルパーメソッド）
class FirestoreService {
    static let shared = FirestoreService()
    
    let db: Firestore
    
    private init() {
        db = Firestore.firestore()
    }
    
    /// 現在のタイムスタンプを生成
    func currentTimestamp() -> Timestamp {
        return Timestamp()
    }
    
    /// 6桁のランダムなペアリングコードを生成（英数字）
    func generatePairingCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}
