import SwiftUI

/// Care Assist's account page: who you are, your workspace, password, sign out.
struct AccountSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSavingPassword = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var showSignOutConfirm = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surface, Theme.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    avatarSection

                    if let successMessage { feedbackBanner(successMessage, isError: false) }
                    if let errorMessage { feedbackBanner(errorMessage, isError: true) }

                    settingsCard(title: "Workspace") {
                        if appState.workspaces.count > 1 {
                            VStack(spacing: 8) {
                                ForEach(appState.workspaces) { workspace in
                                    workspaceRow(workspace)
                                }
                            }
                        } else if let workspace = appState.currentWorkspace {
                            workspaceRow(workspace)
                        }
                    }

                    settingsCard(title: "Security") {
                        VStack(spacing: 14) {
                            secureField(icon: "lock", placeholder: "New Password", text: $newPassword)
                            secureField(icon: "lock.rotation", placeholder: "Confirm Password", text: $confirmPassword)

                            Button {
                                Task { await savePassword() }
                            } label: {
                                HStack {
                                    if isSavingPassword {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("Update Password").fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(Theme.accentText)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 3)
                            }
                            .disabled(isSavingPassword)
                        }
                    }

                    Button {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.bad)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign out of Scaled Admissions?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await appState.signOut() }
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 90, height: 90)
                Text(String((appState.email ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
            }
            Text(appState.email ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 8)
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        let isCurrent = workspace.id == appState.currentWorkspace?.id
        return Button {
            appState.currentWorkspace = workspace
        } label: {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(Theme.ink3)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .foregroundStyle(Theme.ink)
                    Text(workspace.role.capitalized)
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentText)
                }
            }
            .padding()
            .background(Theme.chipFlat)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .padding(.horizontal)
    }

    private func secureField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Theme.ink3)
                .frame(width: 20)
            SecureField(placeholder, text: text)
                .textContentType(.newPassword)
        }
        .padding()
        .background(Theme.chipFlat)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func feedbackBanner(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
            Text(message).font(.subheadline)
        }
        .foregroundStyle(isError ? Theme.badText : Theme.goodText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isError ? Theme.badSoft : Theme.goodSoft)
        )
        .padding(.horizontal)
    }

    private func savePassword() async {
        successMessage = nil
        errorMessage = nil
        guard newPassword.count >= 8 else {
            errorMessage = "Use at least 8 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "The passwords do not match."
            return
        }
        isSavingPassword = true
        defer { isSavingPassword = false }
        do {
            try await SupabaseService.shared.updatePassword(newPassword)
            newPassword = ""
            confirmPassword = ""
            successMessage = "Password updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
