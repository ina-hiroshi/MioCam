//
//  AuthViewModel.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import Foundation
import AuthenticationServices
import Combine

/// 認証状態を管理するViewModel
@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let authService = AuthenticationService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 認証状態を監視
        authService.$isAuthenticated
            .assign(to: &$isAuthenticated)
    }
    
    /// Sign in with Apple を実行（SignInWithAppleButtonから取得済みのASAuthorizationを使用）
    func signInWithApple(authorization: ASAuthorization) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authService.signInWithApple(authorization: authorization)
        } catch {
            let nsError = error as NSError
            var message = error.localizedDescription
            
            // エラーの種類に応じて詳細なメッセージを設定
            if nsError.domain == "AuthenticationService" {
                message = nsError.localizedDescription
            } else if nsError.domain.contains("Firebase") {
                message = "Firebase認証エラー: \(nsError.localizedDescription)"
            } else {
                message = "認証エラー: \(nsError.localizedDescription)"
            }
            
            errorMessage = message
        }
        
        isLoading = false
    }
    
    /// サインアウト
    func signOut() {
        do {
            try authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
