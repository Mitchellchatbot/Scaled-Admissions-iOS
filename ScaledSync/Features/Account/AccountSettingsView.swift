import SwiftUI

/// Care Assist's account page: who you are, your workspace, where to change your password, sign out.
struct AccountSettingsView: View {
    @EnvironmentObject private var appState: AppState
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
                        securityRow
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
        .confirmationDialog("Sign out of Scaled Sync?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
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

    /// Passwords live in Scaled Sync, so they are changed there.
    @ViewBuilder
    private var securityRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You sign in with your Scaled Sync password.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
            if let url = AppConfig.syncAppURL?.appending(path: "settings/account") {
                Link(destination: url) {
                    HStack {
                        Text("Change Password in Scaled Sync").fontWeight(.semibold)
                        Image(systemName: "arrow.up.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Theme.accentText)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
