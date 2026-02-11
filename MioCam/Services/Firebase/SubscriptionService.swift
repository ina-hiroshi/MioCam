//
//  SubscriptionService.swift
//  MioCam
//
//  サブスクリプション状態を管理するサービス（広告表示判定などに使用）
//

import Foundation
import FirebaseFirestore
import Combine

/// サブスクリプション状態を管理
@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// 広告を表示すべきか（プレミアム未加入 or 無料プランの場合 true）
    @Published private(set) var shouldShowAds: Bool = true

    /// プレミアムプランが有効か
    @Published private(set) var isPremium: Bool = false

    private let db = FirestoreService.shared.db
    private var listener: ListenerRegistration?
    private var currentUserId: String?

    private init() {}

    /// ユーザーIDを設定してサブスクリプション監視を開始
    func startObserving(userId: String?) {
        stopObserving()
        currentUserId = userId

        guard let userId = userId else {
            shouldShowAds = true
            isPremium = false
            return
        }

        listener = db.collection("users").document(userId)
            .collection("subscription").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleSnapshot(snapshot: snapshot, error: error)
                }
            }
    }

    /// 監視を停止
    func stopObserving() {
        listener?.remove()
        listener = nil
        currentUserId = nil
        shouldShowAds = true
        isPremium = false
    }

    private func handleSnapshot(snapshot: DocumentSnapshot?, error: Error?) {
        if let error = error {
            #if DEBUG
            print("SubscriptionService: 取得エラー \(error.localizedDescription)")
            #endif
            shouldShowAds = true
            isPremium = false
            return
        }

        guard let snapshot = snapshot, snapshot.exists else {
            shouldShowAds = true
            isPremium = false
            return
        }

        do {
            let model = try snapshot.data(as: SubscriptionModel.self)
            let premium = model.isPremiumActive
            shouldShowAds = !premium
            isPremium = premium
        } catch {
            #if DEBUG
            print("SubscriptionService: デコードエラー \(error.localizedDescription)")
            #endif
            shouldShowAds = true
            isPremium = false
        }
    }

    /// 1回だけサブスクリプション状態を取得（リアルタイム監視なし）
    func fetchSubscriptionStatus(userId: String?) async -> Bool {
        guard let userId = userId else { return true }

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("subscription").document("current")
                .getDocument()

            guard doc.exists else { return true }
            let model = try doc.data(as: SubscriptionModel.self)
            return !model.isPremiumActive
        } catch {
            #if DEBUG
            print("SubscriptionService: 取得エラー \(error.localizedDescription)")
            #endif
            return true
        }
    }

    #if DEBUG
    /// テスト用：プランを直接設定（課金なし）
    /// - Parameter userId: 指定しない場合は currentUserId を使用
    func setTestPlan(_ plan: SubscriptionPlan, userId: String? = nil) async throws {
        let userId = userId ?? currentUserId
        guard let userId = userId else {
            throw NSError(domain: "SubscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ユーザーIDが設定されていません"])
        }
        let data: [String: Any] = [
            "plan": plan.rawValue,
            "originalTransactionId": "test-\(UUID().uuidString)"
        ]
        try await db.collection("users").document(userId)
            .collection("subscription").document("current")
            .setData(data, merge: true)
    }
    #endif
}
