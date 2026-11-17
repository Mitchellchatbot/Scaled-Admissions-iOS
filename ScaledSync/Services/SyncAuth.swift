import Foundation
import Supabase

/// One login for Scaled Sync and this app. For someone whose password is not
/// this app's own (AppState.signIn tries that first), we sign in to the
/// Scaled Sync Supabase project, then trade that token for a session in
/// this app's project at app/api/mobile/session (lib/syncAuth.ts on the web
/// side). The Scaled Sync session is kept, under its own keychain key, so the
/// app can notice when that login is revoked (`stillValid`).
enum SyncAuth {
    struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String
    }

    /// Whether a check found the Scaled Sync login gone, or could not tell.
    enum Check { case valid, revoked, unknown }

    static let client = SupabaseClient(
        supabaseURL: AppConfig.syncSupabaseURL ?? URL(string: "https://not-configured.supabase.co")!,
        supabaseKey: AppConfig.syncSupabaseAnonKey.isEmpty ? "not-configured" : AppConfig.syncSupabaseAnonKey,
        options: SupabaseClientOptions(auth: .init(storageKey: "scaled-sync-login"))
    )

    /// Signs in to Scaled Sync and returns a session for this app's project.
    static func signIn(email: String, password: String) async throws -> Tokens {
        let session: Session
        do {
            session = try await client.auth.signIn(email: email, password: password)
        } catch let AuthError.api(_, code, _, response) {
            if code == .emailNotConfirmed {
                throw MobileAPI.Failure(message: "Confirm your email with Scaled Sync first, then sign in.")
            }
            if response.statusCode == 429 {
                throw MobileAPI.Failure(message: "Too many attempts. Wait a minute and try again.")
            }
            throw MobileAPI.Failure(message: "That email and password did not match.")
        } catch {
            throw MobileAPI.Failure(message: "Could not reach Scaled Sync. Check your connection.")
        }

        do {
            return try await MobileAPI.exchangeSyncToken(session.accessToken)
        } catch {
            // No session here, so none should be left over there either.
            await signOut()
            throw error
        }
    }

    /// Asks Scaled Sync whether this login still stands. A deleted, banned or
    /// signed-out-everywhere user fails the token refresh or the user lookup.
    /// Offline, or with no Scaled Sync session at all (someone signed in
    /// before this app used Scaled Sync), the answer is `unknown`.
    static func stillValid() async -> Check {
        guard client.auth.currentSession != nil else { return .unknown }
        do {
            _ = try await client.auth.user()
            return .valid
        } catch let AuthError.api(_, _, _, response) where (400..<500).contains(response.statusCode) && response.statusCode != 429 {
            return .revoked
        } catch AuthError.sessionMissing {
            return .revoked
        } catch {
            return .unknown
        }
    }

    /// Ends this phone's Scaled Sync session only, never the person's others.
    static func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }
}
