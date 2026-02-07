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
    
    private lazy var auth: Auth = Auth.auth()
    private lazy var db: Firestore = FirestoreService.shared.db
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var isSetup = false
    
    private override init() {
        super.init()
    }
    
    /// Firebase初期化後に呼ぶ（AppDelegateから）
    func setup() {
        guard !isSetup else { return }
        isSetup = true
        setupAuthStateListener()
    }
    
    /// 認証状態のリスナーを設定
    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    /// SignInWithAppleButtonから取得済みのASAuthorizationを使ってFirebase認証を行う
    func signInWithApple(authorization: ASAuthorization) async throws {
        let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential
        let identityToken = appleIDCredential?.identityToken
        let idTokenString = identityToken.flatMap { String(data: $0, encoding: .utf8) }
        
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
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
