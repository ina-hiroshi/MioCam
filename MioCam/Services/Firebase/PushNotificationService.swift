//
//  PushNotificationService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import UIKit
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications

/// プッシュ通知サービス（Firebase Cloud Messaging）
class PushNotificationService: NSObject {
    static let shared = PushNotificationService()
    
    private let db = FirestoreService.shared.db
    private let messaging = Messaging.messaging()
    
    private override init() {
        super.init()
    }
    
    /// プッシュ通知サービスを初期化
    func initialize() {
        UNUserNotificationCenter.current().delegate = self
        messaging.delegate = self
        
        // 通知許可をリクエスト
        requestNotificationPermission()
        
        // APNsトークンを取得
        getAPNSToken()
    }
    
    /// 通知許可をリクエスト
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
                return
            }
            
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    /// APNsトークンを取得
    private func getAPNSToken() {
        messaging.token { token, error in
            if let error = error {
                print("Error fetching FCM registration token: \(error)")
                return
            }
            
            if let token = token {
                print("FCM registration token: \(token)")
                // トークンは後でカメラ登録時にFirestoreに保存される
            }
        }
    }
    
    /// FCMトークンをカメラドキュメントに保存
    func saveTokenToCamera(cameraId: String) async throws {
        // messaging.token()はStringを返す（Optionalではない）
        let token = try await messaging.token()
        
        try await db.collection("cameras").document(cameraId).updateData([
            "pushToken": token
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension PushNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // フォアグラウンドで通知を受信した場合の処理
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 通知をタップした場合の処理
        completionHandler()
    }
}

// MARK: - MessagingDelegate
extension PushNotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        // トークンが更新された場合の処理
    }
}
