import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !AppConfig.isConfigured {
                SetupNeededView()
            } else {
                switch appState.phase {
                case .starting:
                    SplashView()
                case .signedOut:
                    LoginView()
                case .signedIn:
                    if appState.currentWorkspace != nil {
                        ConversationListView()
                    } else {
                        NoWorkspaceView()
                    }
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: appState.phase)
    }
}

/// Care Assist's splash: soft blobs and a breathing logo.
private struct SplashView: View {
    @State private var blobOffset: CGFloat = 0
    @State private var logoScale: CGFloat = 0.92

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Circle()
                .fill(Theme.accent.opacity(0.13))
                .frame(width: 320)
                .offset(x: 130, y: -300 + blobOffset)
                .blur(radius: 2)

            Circle()
                .fill(Theme.accent.opacity(0.09))
                .frame(width: 220)
                .offset(x: -90, y: 360 - blobOffset)
                .blur(radius: 4)

            Image("ScaledMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Theme.accentText)
                .frame(height: 96)
                .shadow(color: Theme.accent.opacity(0.25), radius: 14, y: 6)
                .scaleEffect(logoScale)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                logoScale = 1.0
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                blobOffset = 18
            }
        }
    }
}

/// Signed in, but not a member of any workspace (or the list did not load).
private struct NoWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Text("No workspace yet")
                .font(.cardTitle)
                .foregroundStyle(Theme.ink)
            Text(appState.workspacesError
                 ?? "\(appState.email ?? "This account") is not on a team yet. Ask an owner to invite you, then open the app again.")
                .font(.body14)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await appState.reloadWorkspaces() } }
                .buttonStyle(PrimaryButtonStyle())
            Button("Sign out") { Task { await appState.signOut() } }
                .font(.label13.weight(.medium))
                .foregroundStyle(Theme.ink)
        }
        .cardStyle(padding: 24)
        .padding(Theme.spacePage)
        .frame(maxHeight: .infinity)
    }
}

/// Shown only in a build made without Config/Secrets.xcconfig.
private struct SetupNeededView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App not set up")
                .font(.cardTitle)
                .foregroundStyle(Theme.ink)
            Text("Run ios/scripts/write-secrets.sh to copy the Supabase URL and key from .env.local, then build again.")
                .font(.body14)
                .foregroundStyle(Theme.ink2)
        }
        .cardStyle(padding: 24)
        .padding(Theme.spacePage)
        .frame(maxHeight: .infinity)
    }
}
