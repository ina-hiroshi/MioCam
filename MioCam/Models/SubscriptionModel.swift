//
//  SubscriptionModel.swift
//  MioCam
//
//  Firestore `/users/{userId}/subscription/current` のデータモデル
//

import Foundation
import FirebaseFirestore

/// サブスクリプションプラン
enum SubscriptionPlan: String, Codable {
    case free
    case premium
}

/// Firestore のサブスクリプションステータス
struct SubscriptionModel: Codable {
    var plan: SubscriptionPlan
    var expiresAt: Timestamp?
    var originalTransactionId: String?

    /// 有効なプレミアムサブスクか（plan=premium かつ expiresAt が未来）
    var isPremiumActive: Bool {
        guard plan == .premium else { return false }
        guard let expiresAt = expiresAt else { return true }
        return expiresAt.dateValue() > Date()
    }
}
