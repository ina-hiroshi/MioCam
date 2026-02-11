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
                Section(header: Text("ユーザー名")) {
                    TextField("表示名を入力", text: $displayNameInput)
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
                                Text("保存")
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
                        Text("アカウントを削除")
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
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
            .alert("アカウントを削除", isPresented: $showDeleteAccountConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    showDeleteAccountReauth = true
                }
            } message: {
                Text("アカウントとデータは完全に削除され、元に戻せません。削除しますか？")
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
            displayNameError = "名前を入力してください"
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
