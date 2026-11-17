import Foundation
import Combine
import Supabase

@MainActor
final class AppState: ObservableObject {
    enum Phase { case starting, signedOut, signedIn }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var email: String?
    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var workspacesError: String?
    @Published var currentWorkspace: Workspace? {
        didSet { UserDefaults.standard.set(currentWorkspace?.id, forKey: Self.workspaceKey) }
    }

    /// Set by a notification tap; the inbox opens that conversation.
    @Published var pendingConversationID: String?

    private static let workspaceKey = "currentWorkspaceID"
    private var authTask: Task<Void, Never>?
    private var client: SupabaseClient { SupabaseService.shared.client }

    deinit { authTask?.cancel() }

    func start() async {
        guard AppConfig.isConfigured else { return }
        PushManager.shared.openConversation = { [weak self] id in self?.pendingConversationID = id }

        // The stored session, without a network round trip: an offline launch
        // must not sign anyone out. The SDK refreshes the token when it is next used.
        if let session = client.auth.currentSession {
            await didSignIn(session.user)
        } else {
            phase = .signedOut
        }
        observeAuth()
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        await didSignIn(session.user)
    }

    func signOut() async {
        // While still signed in: the server only lets a phone's owner forget it.
        await PushManager.shared.disable()
        try? await client.auth.signOut()
        reset()
    }

    func reloadWorkspaces() async {
        guard let user = client.auth.currentUser else { return }
        await loadWorkspaces(userID: user.id)
    }

    private func didSignIn(_ user: User) async {
        email = user.email
        await loadWorkspaces(userID: user.id)
        phase = .signedIn
        Task { await PushManager.shared.enable() }
    }

    private func loadWorkspaces(userID: UUID) async {
        do {
            workspaces = try await SupabaseService.shared.fetchWorkspaces(userID: userID)
            workspacesError = nil
            let saved = UserDefaults.standard.string(forKey: Self.workspaceKey)
            currentWorkspace = workspaces.first { $0.id == saved } ?? workspaces.first
        } catch {
            workspacesError = "Could not load your workspaces. Pull to try again."
        }
    }

    private func reset() {
        phase = .signedOut
        email = nil
        workspaces = []
        currentWorkspace = nil
    }

    private func observeAuth() {
        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let stream = self?.client.auth.authStateChanges else { return }
            for await (event, _) in stream {
                // A revoked refresh token, or signing out on another screen.
                if event == .signedOut { self?.reset() }
            }
        }
    }
}
