//
//  AppDelegate.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import FirebaseCrashlytics

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Firebase初期化（MioCamAppで既に実行済み）
        
        // Crashlytics初期化
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        // プッシュ通知サービス初期化
        PushNotificationService.shared.initialize()
        
        return true
    }
    
    // APNsトークン取得成功時
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // APNsトークン取得失敗時
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}
