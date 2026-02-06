//
//  AuthenticationService.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import Combine

/// Sign in with Apple + Firebase Auth 認証サービス
@MainActor
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    
    private let auth = Auth.auth()
    private let db = FirestoreService.shared.db
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    private override init() {
        super.init()
        setupAuthStateListener()
    }
    
    /// 認証状態のリスナーを設定
    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                // #region agent log
                DebugLog.write([
                    "sessionId": "debug-session",
                    "runId": "pre-fix",
                    "hypothesisId": "H1",
                    "location": "AuthenticationService.swift:setupAuthStateListener",
                    "message": "Auth state changed",
                    "data": [
                        "hasUser": user != nil
                    ],
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
                // #endregion
            }
        }
    }
    
    /// SignInWithAppleButtonから取得済みのASAuthorizationを使ってFirebase認証を行う
    func signInWithApple(authorization: ASAuthorization) async throws {
        let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential
        let identityToken = appleIDCredential?.identityToken
        let idTokenString = identityToken.flatMap { String(data: $0, encoding: .utf8) }
        
        // #region agent log
        DebugLog.write([
            "sessionId": "debug-session",
            "runId": "pre-fix",
            "hypothesisId": "H2",
            "location": "AuthenticationService.swift:signInWithApple",
            "message": "Apple credential extraction",
            "data": [
                "hasAppleIDCredential": appleIDCredential != nil,
                "hasIdentityToken": identityToken != nil,
                "idTokenLength": idTokenString?.count ?? 0
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
        // #endregion
        
        guard let appleIDCredential = appleIDCredential,
              let idTokenString = idTokenString else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get Apple ID credential"])
        }
        
        let credential = OAuthProvider.credential(providerID: AuthProviderID.apple, idToken: idTokenString, rawNonce: "")
        let authResult = try await auth.signIn(with: credential)
        
        // ユーザードキュメントを作成/更新
        try await createOrUpdateUserDocument(userId: authResult.user.uid, appleUserId: appleIDCredential.user, displayName: appleIDCredential.fullName?.givenName)
    }
    
    /// ユーザードキュメントを作成または更新
    private func createOrUpdateUserDocument(userId: String, appleUserId: String, displayName: String?) async throws {
        let userRef = db.collection("users").document(userId)
        
        try await userRef.setData([
            "appleUserId": appleUserId,
            "displayName": displayName ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    /// サインアウト
    func signOut() throws {
        try auth.signOut()
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }
}

enum DebugLog {
    private static let logPath = "/Users/inahiroshi/開発/MioCam/.cursor/debug.log"
    
    static func write(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        
        let lineWithNewline = line + "\n"
        
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            if let lineData = lineWithNewline.data(using: .utf8) {
                handle.write(lineData)
            }
            try? handle.close()
        } else {
            try? lineWithNewline.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
