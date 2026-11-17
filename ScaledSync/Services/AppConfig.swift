import Foundation

/// Values from Config/*.xcconfig, passed through Info.plist.
enum AppConfig {
    static var supabaseURL: URL? { url("SUPABASE_URL") }
    static var supabaseAnonKey: String { string("SUPABASE_ANON_KEY") }
    /// The Next.js app. Replies and the AI switch go through it (app/api/mobile).
    static var apiBaseURL: URL? { url("API_BASE_URL") }
    /// Scaled Sync's project, where people's passwords live (SyncAuth).
    static var syncSupabaseURL: URL? { url("SYNC_SUPABASE_URL") }
    static var syncSupabaseAnonKey: String { string("SYNC_SUPABASE_ANON_KEY") }
    /// The Scaled Sync web app, where passwords are changed and reset.
    static var syncAppURL: URL? { url("SYNC_APP_URL") }

    static var isConfigured: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty && apiBaseURL != nil
            && syncSupabaseURL != nil && !syncSupabaseAnonKey.isEmpty
    }

    private static func string(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting comes through as "" or as the literal "$(KEY)".
        return raw.hasPrefix("$(") ? "" : raw
    }

    private static func url(_ key: String) -> URL? {
        let value = string(key)
        guard value.hasPrefix("http"), let url = URL(string: value), url.host != nil else { return nil }
        return url
    }
}
