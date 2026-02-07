//
//  SignInWithAppleView.swift
//  MioCam
//
//  Created on 2026-02-06.
//

import SwiftUI
import AuthenticationServices


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
                
                Text("MioCam")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.mioTextPrimary)
            }
            
            // 説明テキスト
            VStack(spacing: 12) {
                Text("古いiPhoneを、世界一シンプルな見守り窓に。")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.mioTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text("Sign in with Appleで簡単に始められます")
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
                        message = "認証エラーが発生しました。実機で実行していることを確認してください。シミュレーターではSign in with Appleが正しく動作しない場合があります。"
                    case .canceled:
                        message = "認証がキャンセルされました。"
                    case .invalidResponse:
                        message = "無効な認証応答が返されました。"
                    case .notHandled:
                        message = "認証リクエストが処理できませんでした。"
                    case .failed:
                        message = "認証に失敗しました。"
                    case .notInteractive:
                        message = "認証が対話的に処理できませんでした。"
                    case .matchedExcludedCredential:
                        message = "除外された認証情報が一致しました。"
                    default:
                        message = "不明な認証エラー: \(authError.localizedDescription)"
                    }
                } else if nsError.domain == "AKAuthenticationError" {
                    if nsError.code == -7026 {
                        message = "デバイスの設定に問題があります。実機で実行していることを確認してください。"
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
