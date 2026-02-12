//
//  AppSettingsSheet.swift
//  MioCam
//
//  アプリ設定シート（ユーザー名）
//

import SwiftUI

/// アプリ設定シート
struct AppSettingsSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var subscriptionService: SubscriptionService
    @Environment(\.dismiss) private var dismiss

    @State private var displayNameInput: String = ""
    @State private var isSavingDisplayName = false
    @State private var displayNameError: String?
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountReauth = false

    var body: some View {
        NavigationStack {
            List {
                // ユーザー名
                Section(header: Text(String(localized: "user_name"))) {
                    TextField(String(localized: "display_name_placeholder"), text: $displayNameInput)
                        .textContentType(.username)
                        .autocapitalization(.words)
                        .disabled(isSavingDisplayName)

                    if let error = displayNameError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.mioError)
                    }

                    Button {
                        saveDisplayName()
                    } label: {
                        HStack {
                            Spacer()
                            if isSavingDisplayName {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(String(localized: "save"))
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(displayNameInput.isEmpty || isSavingDisplayName)
                }

                // アカウント削除
                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        Text(String(localized: "delete_account"))
                    }
                }
            }
            .navigationTitle(String(localized: "settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                displayNameInput = authService.displayName ?? ""
            }
            .onChange(of: authService.displayName) { newValue in
                displayNameInput = newValue ?? ""
            }
            .alert(String(localized: "delete_account"), isPresented: $showDeleteAccountConfirmation) {
                Button(String(localized: "cancel"), role: .cancel) {}
                Button(String(localized: "delete_confirm"), role: .destructive) {
                    showDeleteAccountReauth = true
                }
            } message: {
                Text(String(localized: "delete_account_confirm"))
            }
            .sheet(isPresented: $showDeleteAccountReauth) {
                DeleteAccountReauthSheet()
                    .environmentObject(authService)
                    .environmentObject(subscriptionService)
                    .onDisappear {
                        showDeleteAccountReauth = false
                    }
            }
        }
    }

    // MARK: - Actions

    private func saveDisplayName() {
        let name = displayNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            displayNameError = String(localized: "display_name_required")
            return
        }

        displayNameError = nil
        isSavingDisplayName = true

        Task {
            do {
                try await authService.updateDisplayName(name)
            } catch {
                displayNameError = error.localizedDescription
            }
            isSavingDisplayName = false
        }
    }
}

#Preview {
    AppSettingsSheet()
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SubscriptionService.shared)
}
