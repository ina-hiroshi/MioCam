//
//  SignInWithAppleView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import AuthenticationServices
import Foundation


/// Sign in with Apple 画面
struct SignInWithAppleView: View {
    @StateObject private var viewModel = AuthViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // ロゴエリア
            VStack(spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                
                Text(String(localized: "app_name"))
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.mioTextPrimary)
            }
            
            // 説明テキスト
            VStack(spacing: 12) {
                Text(String(localized: "tagline"))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.mioTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text(String(localized: "sign_in_apple_prompt"))
                    .font(.system(.body))
                    .foregroundColor(.mioTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Sign in with Apple ボタン
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .cornerRadius(16)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1.0)
            
            if viewModel.isLoading {
                ProgressView()
                    .padding(.bottom, 24)
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(.caption))
                    .foregroundColor(.mioError)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mioPrimary.ignoresSafeArea())
    }
    
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        Task {
            switch result {
            case .success(let authorization):
                await viewModel.signInWithApple(authorization: authorization)
            case .failure(let error):
                let nsError = error as NSError
                var message = error.localizedDescription
                
                // エラーコードに基づいて詳細なメッセージを追加
                if let authError = error as? ASAuthorizationError {
                    switch authError.code {
                    case .unknown:
                        message = String(localized: "auth_error_simulator")
                    case .canceled:
                        message = String(localized: "auth_canceled")
                    case .invalidResponse:
                        message = String(localized: "auth_invalid_response")
                    case .notHandled:
                        message = String(localized: "auth_not_handled")
                    case .failed:
                        message = String(localized: "auth_failed")
                    case .notInteractive:
                        message = String(localized: "auth_not_interactive")
                    case .matchedExcludedCredential:
                        message = String(localized: "auth_matched_excluded")
                    default:
                        message = String(format: String(localized: "auth_unknown_error"), authError.localizedDescription)
                    }
                } else if nsError.domain == "AKAuthenticationError" {
                    if nsError.code == -7026 {
                        message = String(localized: "auth_device_setting_error")
                    }
                }
                
                viewModel.errorMessage = message
            }
        }
    }
}

#Preview {
    SignInWithAppleView()
}
