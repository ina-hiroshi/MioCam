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
    @Published var displayName: String?

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
                if let userId = user?.uid {
                    await self?.loadDisplayName(userId: userId)
                } else {
                    self?.displayName = nil
                }
            }
        }
    }

    /// Firestore から displayName を取得
    private func loadDisplayName(userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            displayName = doc.data()?["displayName"] as? String
        } catch {
            #if DEBUG
            print("AuthenticationService: displayName 取得エラー \(error.localizedDescription)")
            #endif
            displayName = nil
        }
    }

    /// ユーザー名を更新
    func updateDisplayName(_ name: String) async throws {
        guard let userId = currentUser?.uid else { return }
        try await db.collection("users").document(userId).updateData(["displayName": name])
        displayName = name
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
        
        var data: [String: Any] = [
            "appleUserId": appleUserId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        // Apple は初回認証時のみ fullName を返す。再ログイン時は nil のため、
        // 既存の displayName を上書きしない（nil/空の場合はフィールドを追加しない）
        if let displayName = displayName, !displayName.isEmpty {
            data["displayName"] = displayName
        }
        
        try await userRef.setData(data, merge: true)
    }
    
    /// サインアウト
    func signOut() throws {
        try auth.signOut()
    }

    /// アカウントを削除（再認証必須。Sign in with Apple で取得した authorization を渡す）
    func deleteAccount(authorization: ASAuthorization) async throws {
        guard let user = auth.currentUser else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "サインインしていません"])
        }

        let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential
        let idTokenString = appleIDCredential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }

        guard let idTokenString = idTokenString else {
            throw NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "認証情報の取得に失敗しました"])
        }

        let credential = OAuthProvider.credential(providerID: AuthProviderID.apple, idToken: idTokenString, rawNonce: "")
        try await user.reauthenticate(with: credential)

        let userId = user.uid
        try await AccountDeletionService.shared.deleteAllUserData(userId: userId)
        try await user.delete()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
