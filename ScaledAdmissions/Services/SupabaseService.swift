import Foundation
import Supabase

/// Reads go straight to Supabase as the signed-in user, so the same row-level
/// security that guards the web inbox decides what this app can see
/// (db/policies.sql). Writes that need a channel token go through MobileAPI.
final class SupabaseService: @unchecked Sendable {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        // Without config the app shows a setup screen; the placeholder only
        // keeps the client constructible.
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL ?? URL(string: "https://not-configured.supabase.co")!,
            supabaseKey: AppConfig.supabaseAnonKey.isEmpty ? "not-configured" : AppConfig.supabaseAnonKey
        )
    }

    // MARK: - Workspaces

    func fetchWorkspaces(userID: UUID) async throws -> [Workspace] {
        struct Org: Decodable { let name: String }
        struct Row: Decodable {
            let org_id: String
            let role: String
            let organizations: Org?
        }
        let rows: [Row] = try await client
            .from("org_members")
            .select("org_id, role, organizations(name)")
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("active", value: true)
            .execute()
            .value
        return rows
            .map { Workspace(id: $0.org_id, name: $0.organizations?.name ?? "Workspace", role: $0.role) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Conversations

    static let pageSize = 20

    /// A page of the workspace's conversations, newest first. With `ids` or
    /// `contactIDs`, only those conversations (for search results and deep links).
    func fetchConversations(orgID: String, from: Int = 0, to: Int = pageSize - 1, ids: [String]? = nil, contactIDs: [String]? = nil, stage: String? = nil) async throws -> [ConversationSummary] {
        struct Contact: Decodable {
            let display_name: String?
            let channel: String
            let stage: String
            let external_id: String
            let profile_photo_url: String?
            let referral_source: String?
            let referral_ad_title: String?
            let referral_ref: String?
            let referral_ad_id: String?
        }
        struct Row: Decodable {
            let id: String
            let contact_id: String
            let mode: ConversationMode
            let last_message_at: String?
            let summary: String?
            let contacts: Contact?
        }
        if let ids, ids.isEmpty { return [] }
        if let contactIDs, contactIDs.isEmpty { return [] }
        // With a stage, the join is inner so the filter drops conversations
        // rather than just their contact, and paging counts only matches.
        let contactColumns = "display_name, channel, stage, external_id, profile_photo_url, referral_source, referral_ad_title, referral_ref, referral_ad_id"
        var query = client
            .from("conversations")
            .select("id, contact_id, mode, last_message_at, summary, contacts\(stage == nil ? "" : "!inner")(\(contactColumns))")
            .eq("org_id", value: orgID)
        if let stage { query = query.eq("contacts.stage", value: stage) }
        if let ids { query = query.in("id", values: ids) }
        if let contactIDs { query = query.in("contact_id", values: contactIDs) }
        let rows: [Row] = try await query
            .order("last_message_at", ascending: false, nullsFirst: false)
            .range(from: from, to: to)
            .execute()
            .value

        async let previewLookup = fetchPreviews(conversationIDs: rows.map(\.id))
        async let campaignLookup = fetchCampaigns(orgID: orgID, adIDs: rows.compactMap { $0.contacts?.referral_ad_id })
        let previews = try await previewLookup
        let campaigns = await campaignLookup

        return rows.compactMap { row in
            guard let contact = row.contacts else { return nil }
            return ConversationSummary(
                id: row.id,
                contactID: row.contact_id,
                mode: row.mode,
                lastMessageAt: ISODate.parse(row.last_message_at),
                name: Self.displayName(contact.display_name, fallback: contact.external_id),
                channel: contact.channel,
                stage: contact.stage,
                photoURL: contact.profile_photo_url.flatMap(URL.init(string:)),
                summary: row.summary,
                preview: previews[row.id],
                source: LeadSource(
                    source: contact.referral_source,
                    adTitle: contact.referral_ad_title,
                    ref: contact.referral_ref,
                    adID: contact.referral_ad_id,
                    campaign: contact.referral_ad_id.flatMap { campaigns[$0] }
                )
            )
        }
    }

    /// Campaign names for ads Meta has been asked about (meta_ads). A nice
    /// to have: a failed read leaves the chip on the ad's own title.
    private func fetchCampaigns(orgID: String, adIDs: [String]) async -> [String: String] {
        let ids = Array(Set(adIDs))
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let ad_id: String; let campaign_name: String? }
        let rows: [Row]? = try? await client
            .from("meta_ads")
            .select("ad_id, campaign_name")
            .eq("org_id", value: orgID)
            .in("ad_id", values: ids)
            .execute()
            .value
        var result: [String: String] = [:]
        for row in rows ?? [] { if let name = row.campaign_name { result[row.ad_id] = name } }
        return result
    }

    static func displayName(_ name: String?, fallback: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// The web inbox's search (lib/inboxSearch.ts): lead names and ids,
    /// anything the agent captured (a name or number the lead typed), the AI
    /// summary, and message text. Rows that matched on a message carry it as
    /// `matchingSnippet`. One failing lookup does not blank the others.
    func searchConversations(orgID: String, query raw: String) async throws -> [ConversationSummary] {
        let query = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard query.count >= 2 else { return [] }
        // `%` and `_` are ILIKE wildcards and PostgREST reads `*` as one; a
        // search for "50%" means the characters.
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "*", with: "")
        let like = "%\(escaped)%"

        struct ContactRow: Decodable { let id: String }
        struct FactRow: Decodable { let contact_id: String }
        struct ConversationRow: Decodable { let id: String }
        struct MessageRow: Decodable { let conversation_id: String; let body: String? }

        async let byName: [ContactRow]? = try? client
            .from("contacts").select("id")
            .eq("org_id", value: orgID).ilike("display_name", pattern: like)
            .limit(30).execute().value
        async let byExternalID: [ContactRow]? = try? client
            .from("contacts").select("id")
            .eq("org_id", value: orgID).ilike("external_id", pattern: like)
            .limit(30).execute().value
        async let byFact: [FactRow]? = try? client
            .from("lead_facts").select("contact_id")
            .eq("org_id", value: orgID).ilike("value", pattern: like)
            .limit(60).execute().value
        async let bySummary: [ConversationRow]? = try? client
            .from("conversations").select("id")
            .eq("org_id", value: orgID).ilike("summary", pattern: like)
            .limit(30).execute().value
        async let byMessage: [MessageRow]? = try? client
            .from("messages").select("conversation_id, body")
            .eq("org_id", value: orgID).neq("sender", value: "system")
            .ilike("body", pattern: like)
            .order("created_at", ascending: false)
            .limit(60).execute().value

        let contactIDs = Set(((await byName) ?? []).map(\.id))
            .union(((await byExternalID) ?? []).map(\.id))
            .union(((await byFact) ?? []).map(\.contact_id))
        var snippets: [String: String] = [:]
        for row in (await byMessage) ?? [] where snippets[row.conversation_id] == nil {
            if let body = row.body { snippets[row.conversation_id] = Self.snippet(from: body, matching: query) }
        }
        let conversationIDs = Set(((await bySummary) ?? []).map(\.id)).union(snippets.keys)

        async let ofContacts = fetchConversations(orgID: orgID, from: 0, to: 59, contactIDs: Array(contactIDs))
        async let ofIDs = fetchConversations(orgID: orgID, from: 0, to: 79, ids: Array(conversationIDs))
        var byID: [String: ConversationSummary] = [:]
        for convo in try await ofContacts + ofIDs { byID[convo.id] = convo }
        var found = byID.values.sorted(by: ConversationSummary.newestFirst)
        for index in found.indices {
            found[index].matchingSnippet = snippets[found[index].id]
        }
        return found
    }

    /// A window of the message around the match, so the highlight is visible.
    static func snippet(from text: String, matching query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return text }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }

    /// The latest message of each chat, for the preview line. One query covers
    /// the busy chats; the quiet ones it misses are asked for one by one
    /// (the same approach as lib/inbox.ts).
    private func fetchPreviews(conversationIDs ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable {
            let conversation_id: String
            let body: String?
            let media: [MessageMedia]?
        }
        func preview(_ row: Row) -> String? {
            if let body = row.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty { return body }
            return (row.media?.isEmpty == false) ? "Attachment" : nil
        }

        let rows: [Row] = try await client
            .from("messages")
            .select("conversation_id, body, media")
            .in("conversation_id", values: ids)
            .neq("sender", value: "system")
            .order("created_at", ascending: false)
            .limit(ids.count * 8)
            .execute()
            .value

        var result: [String: String] = [:]
        for row in rows where result[row.conversation_id] == nil {
            if let text = preview(row) { result[row.conversation_id] = text }
        }

        let missing = ids.filter { result[$0] == nil }
        await withTaskGroup(of: (String, String?).self) { group in
            for id in missing {
                group.addTask {
                    let latest: [Row]? = try? await self.client
                        .from("messages")
                        .select("conversation_id, body, media")
                        .eq("conversation_id", value: id)
                        .neq("sender", value: "system")
                        .order("created_at", ascending: false)
                        .limit(1)
                        .execute()
                        .value
                    return (id, latest?.first.flatMap(preview))
                }
            }
            for await (id, text) in group {
                if let text { result[id] = text }
            }
        }
        return result
    }

    // MARK: - Thread

    func fetchMessages(conversationID: String) async throws -> [ThreadMessage] {
        struct Row: Decodable {
            let id: String
            let direction: String
            let sender: String
            let body: String?
            let media: [MessageMedia]?
            let created_at: String
            let delivered_at: String?
            let read_at: String?
        }
        let rows: [Row] = try await client
            .from("messages")
            .select("id, direction, sender, body, media, created_at, delivered_at, read_at")
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .limit(500)
            .execute()
            .value
        return rows.map { row in
            ThreadMessage(
                id: row.id,
                isOutbound: row.direction == "outbound",
                sender: ThreadMessage.Sender(rawValue: row.sender) ?? .system,
                body: row.body,
                media: row.media ?? [],
                createdAt: ISODate.parse(row.created_at) ?? Date(),
                deliveredAt: ISODate.parse(row.delivered_at),
                readAt: ISODate.parse(row.read_at)
            )
        }
    }

    func fetchMode(conversationID: String) async throws -> ConversationMode? {
        struct Row: Decodable { let mode: ConversationMode }
        let rows: [Row] = try await client
            .from("conversations")
            .select("mode")
            .eq("id", value: conversationID)
            .limit(1)
            .execute()
            .value
        return rows.first?.mode
    }

    /// Mirrors loadHold in lib/inbox.ts.
    func fetchHold(conversationID: String) async throws -> Hold? {
        struct Payload: Decodable { let reason: String? }
        struct Row: Decodable {
            let kind: String
            let payload: Payload?
        }
        let rows: [Row] = try await client
            .from("alerts")
            .select("kind, payload")
            .eq("conversation_id", value: conversationID)
            .in("kind", values: ["crisis", "system"])
            .neq("state", value: "acknowledged")
            .order("created_at", ascending: false)
            .execute()
            .value
        guard let pick = rows.first(where: { $0.kind == "crisis" }) ?? rows.first else { return nil }
        return Hold(reason: Labels.reason(pick.payload?.reason ?? ""), crisis: pick.kind == "crisis")
    }
}

extension SupabaseService {
    // MARK: - Notifications

    /// The workspace's feed, newest first (the web's /notifications).
    func fetchFeed(orgID: String, urgentOnly: Bool = false, limit: Int = 60) async throws -> [FeedItem] {
        struct Contact: Decodable { let display_name: String?; let channel: String?; let phone: String? }
        struct Row: Decodable {
            let id: String
            let kind: String
            let conversation_id: String?
            let detail: [String: AnyJSON]?
            let created_at: String
            let contacts: Contact?
        }
        var query = client
            .from("notifications")
            .select("id, kind, conversation_id, detail, created_at, contacts(display_name, channel, phone)")
            .eq("org_id", value: orgID)
        if urgentOnly { query = query.in("kind", values: Array(FeedItem.urgentKinds)) }
        let rows: [Row] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map { row in
            var detail: [String: String] = [:]
            for (key, value) in row.detail ?? [:] {
                if case .string(let text) = value { detail[key] = text }
            }
            let name = row.contacts?.display_name?.trimmingCharacters(in: .whitespaces)
            return FeedItem(
                id: row.id,
                kind: row.kind,
                conversationID: row.conversation_id,
                name: (name?.isEmpty == false) ? name : nil,
                channel: row.contacts?.channel,
                phone: row.contacts?.phone,
                detail: detail,
                createdAt: ISODate.parse(row.created_at) ?? Date()
            )
        }
    }

    // MARK: - Lead details

    func fetchLeadDetails(contactID: String, summary: String?) async throws -> LeadDetails {
        struct Contact: Decodable {
            let display_name: String?
            let external_id: String
            let phone: String?
            let email: String?
            let channel: String
            let stage: String
            let first_contact_at: String?
            let referral_ad_title: String?
        }
        struct Fact: Decodable { let key: String; let value: String? }

        async let contactRows: [Contact] = client
            .from("contacts")
            .select("display_name, external_id, phone, email, channel, stage, first_contact_at, referral_ad_title")
            .eq("id", value: contactID)
            .limit(1)
            .execute()
            .value
        async let factRows: [Fact] = client
            .from("lead_facts")
            .select("key, value")
            .eq("contact_id", value: contactID)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value

        guard let contact = try await contactRows.first else {
            throw MobileAPI.Failure(message: "Could not find this lead.")
        }
        // Newest row per key wins; an empty newest row means someone cleared it.
        var facts: [String: String] = [:]
        var seen = Set<String>()
        for fact in try await factRows where !seen.contains(fact.key) {
            seen.insert(fact.key)
            if let value = fact.value, !value.isEmpty { facts[fact.key] = value }
        }
        return LeadDetails(
            name: Self.displayName(contact.display_name, fallback: contact.external_id),
            phone: contact.phone ?? facts["phone"],
            email: contact.email ?? facts["email"],
            channel: contact.channel,
            stage: contact.stage,
            firstContactAt: ISODate.parse(contact.first_contact_at),
            adTitle: contact.referral_ad_title,
            summary: summary,
            facts: facts
        )
    }

    // MARK: - Account

    func updatePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
    }
}

/// Postgres timestamps arrive as ISO 8601, with or without fractional seconds.
enum ISODate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractional.date(from: value) ?? plain.date(from: value)
    }
}
