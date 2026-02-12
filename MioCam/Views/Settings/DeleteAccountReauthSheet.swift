//
//  DeleteAccountReauthSheet.swift
//  MioCam
//
//  アカウント削除のため Sign in with Apple で再認証するシート
//

import SwiftUI
import AuthenticationServices

/// アカウント削除の再認証シート
struct DeleteAccountReauthSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text(String(localized: "delete_account_reauth_message"))
                    .font(.system(.body))
                    .foregroundColor(.mioTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleReauthResult(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .cornerRadius(16)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                .opacity(isLoading ? 0.6 : 1.0)

                if isLoading {
                    ProgressView()
                        .padding(.top, 16)
                }

                if let message = errorMessage {
                    Text(message)
                        .font(.system(.caption))
                        .foregroundColor(.mioError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mioPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "delete_account_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func handleReauthResult(_ result: Result<ASAuthorization, Error>) {
        Task {
            switch result {
            case .success(let authorization):
                await deleteAccount(authorization: authorization)
            case .failure(let error):
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    // ユーザーがキャンセルした場合はエラー表示しない
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount(authorization: ASAuthorization) async {
        errorMessage = nil
        isLoading = true

        do {
            try await authService.deleteAccount(authorization: authorization)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    DeleteAccountReauthSheet()
        .environmentObject(AuthenticationService.shared)
}
