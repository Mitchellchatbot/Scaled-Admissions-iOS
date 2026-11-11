import Foundation
import Supabase

/// Calls to the web app's app/api/mobile routes. Sending a reply needs the
/// workspace's encrypted Meta token, which never leaves the server, so these
/// go through Next.js rather than straight to Supabase.
enum MobileAPI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func sendReply(conversationID: String, body: String) async throws {
        try await post("api/mobile/conversations/\(conversationID)/reply", json: ["body": body])
    }

    static func registerDevice(token: String, environment: String) async throws {
        try await post("api/mobile/devices", json: ["token": token, "environment": environment])
    }

    static func unregisterDevice(token: String) async throws {
        try await post("api/mobile/devices", json: ["token": token], method: "DELETE")
    }

    static func setMode(conversationID: String, mode: ConversationMode) async throws {
        try await post("api/mobile/conversations/\(conversationID)/mode", json: ["mode": mode.rawValue])
    }

    /// Signed links for photos kept in private storage, keyed by their `storage:` reference.
    static func mediaURLs(conversationID: String) async throws -> [String: String] {
        guard let base = AppConfig.apiBaseURL else { throw Failure(message: "The app is not set up yet.") }
        let session = try await SupabaseService.shared.client.auth.session
        var request = URLRequest(url: base.appending(path: "api/mobile/conversations/\(conversationID)/media"))
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(message: "Could not load photos.")
        }
        struct Body: Decodable { let urls: [String: String] }
        return try JSONDecoder().decode(Body.self, from: data).urls
    }

    private static func post(_ path: String, json: [String: String], method: String = "POST") async throws {
        guard let base = AppConfig.apiBaseURL else { throw Failure(message: "The app is not set up yet.") }

        // `session` refreshes an expired access token before handing it over.
        let session = try await SupabaseService.shared.client.auth.session

        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(json)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Could not reach Scaled Admissions. Check your connection.")
        }

        guard let http = response as? HTTPURLResponse else { throw Failure(message: "Could not send.") }
        guard (200..<300).contains(http.statusCode) else {
            struct Body: Decodable { let error: String? }
            let serverMessage = (try? JSONDecoder().decode(Body.self, from: data))?.error
            throw Failure(message: sentenceCase(serverMessage ?? "Could not send (\(http.statusCode))."))
        }
    }

    /// The server's errors are written lowercase for inline use; on a phone they stand alone.
    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capitalized = first.uppercased() + text.dropFirst()
        return capitalized.hasSuffix(".") ? capitalized : capitalized + "."
    }
}
