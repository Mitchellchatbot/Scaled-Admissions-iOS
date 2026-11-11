import Foundation

/// Values from Config/*.xcconfig, passed through Info.plist.
enum AppConfig {
    static var supabaseURL: URL? { url("SUPABASE_URL") }
    static var supabaseAnonKey: String { string("SUPABASE_ANON_KEY") }
    /// The Next.js app. Replies and the AI switch go through it (app/api/mobile).
    static var apiBaseURL: URL? { url("API_BASE_URL") }

    static var isConfigured: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty && apiBaseURL != nil
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
