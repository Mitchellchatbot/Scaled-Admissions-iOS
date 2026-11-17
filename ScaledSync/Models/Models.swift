import Foundation

/// A workspace the signed-in person belongs to (organizations + org_members).
struct Workspace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String
}

enum ConversationMode: String, Codable, Sendable {
    case aiActive = "ai_active"
    case humanTakeover = "human_takeover"
    case closed
}

/// One row in the conversation list.
struct ConversationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let contactID: String
    var mode: ConversationMode
    let lastMessageAt: Date?
    let name: String
    let channel: String
    let stage: String
    let photoURL: URL?
    let summary: String?
    var preview: String?
    /// Where the lead came from (an ad's campaign, a link, the website chat).
    var source: LeadSource = .direct
    /// The matching message, when this row came from a search.
    var matchingSnippet: String? = nil

    var aiOn: Bool { mode == .aiActive }

    /// The inbox order: latest message first, chats with none last.
    static func newestFirst(_ a: ConversationSummary, _ b: ConversationSummary) -> Bool {
        switch (a.lastMessageAt, b.lastMessageAt) {
        case let (x?, y?): x != y ? x > y : a.id < b.id
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.id < b.id
        }
    }
    var stageLabel: String { Labels.stage(stage) }
    var channelLabel: String { Labels.channel(channel) }
}

struct MessageMedia: Codable, Hashable, Sendable {
    let type: String
    let url: String
}

struct ThreadMessage: Identifiable, Hashable, Sendable {
    enum Sender: String, Sendable { case contact, ai, human, system }

    let id: String
    let isOutbound: Bool
    let sender: Sender
    let body: String?
    var media: [MessageMedia]
    let createdAt: Date
    let deliveredAt: Date?
    let readAt: Date?
    /// Set on a reply shown before the server has it.
    var isPending = false

    /// The caption under a run of bubbles, as the web inbox writes it.
    var senderLabel: String? {
        switch sender {
        case .contact: nil
        case .ai: "AI agent"
        case .human: "You"
        case .system: "System"
        }
    }
}

/// An open request for a person: the agent is holding the lead until someone takes over.
struct Hold: Hashable, Sendable {
    let reason: String
    let crisis: Bool
    /// When the agent raised it.
    var raisedAt: Date? = nil
    /// "now" for a call right away, "scheduled" for a booked callback.
    var handoff: String? = nil
    var callbackAt: Date? = nil
}

/// How a lead reached the page, labelled like lib/referralDisplay.ts: the ad's
/// campaign first (what a coordinator recognises), then its title or ref.
enum LeadSource: Hashable, Sendable {
    case ad(String?)
    case link(String?)
    case websiteChat
    /// Messaged the page with no referral attached.
    case direct

    init(source: String?, adTitle: String?, ref: String?, adID: String?, campaign: String?) {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        let name = clean(campaign) ?? clean(adTitle) ?? clean(ref)
        switch source?.uppercased() {
        case "ADS": self = .ad(name)
        case "SHORTLINK": self = .link(name)
        case "CUSTOMER_CHAT_PLUGIN": self = .websiteChat
        default:
            if clean(adID) != nil || clean(campaign) != nil || clean(adTitle) != nil { self = .ad(name) }
            else if let name { self = .link(name) }
            else { self = .direct }
        }
    }

    var label: String {
        switch self {
        case .ad(let name): name ?? "Ad"
        case .link(let name): name ?? "Link"
        case .websiteChat: "Website chat"
        case .direct: "Direct"
        }
    }

    var icon: String {
        switch self {
        case .ad: "megaphone.fill"
        case .link: "link"
        case .websiteChat: "globe"
        case .direct: "bubble.left.fill"
        }
    }
}

/// Words shared with the web app (lib/factDisplay.ts).
enum Labels {
    static func stage(_ stage: String) -> String {
        [
            "new": "New",
            "hot": "Hot",
            "ready": "Ready to call",
            "scheduled": "Scheduled",
            "followup": "Follow-up",
            "intake": "Intake",
            "admitted": "Admitted",
            "cold": "Cold",
            "closed": "Closed",
        ][stage] ?? stage.capitalized
    }

    static let stageOrder = ["new", "hot", "ready", "scheduled", "followup", "intake", "admitted", "cold", "closed"]

    /// A hold or alert reason, without any technical error the server attached
    /// ("Crisis screening unavailable: 401 {...}" reads "Crisis screening unavailable").
    static func reason(_ raw: String) -> String {
        var text = raw
        if let brace = text.firstIndex(where: { $0 == "{" || $0 == "[" }) { text = String(text[..<brace]) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :0123456789").union(.whitespacesAndNewlines))
        guard let first = text.first else { return "Needs a person" }
        return first.uppercased() + text.dropFirst()
    }

    static func channel(_ channel: String) -> String {
        [
            "messenger": "Messenger",
            "instagram": "Instagram",
            "web": "Website",
            "sms": "Text",
        ][channel] ?? channel.capitalized
    }
}

/// The filter sheet's choices (Care Assist's ConversationFilter, for admissions).
struct ConversationFilter: Equatable {
    /// What the list opens on: the leads ready for a call.
    static let standard = ConversationFilter(stage: "ready")

    var stage: String? = nil
    var channel: String? = nil
    var aiEnabled: Bool? = nil      // nil = all, false = "You have it"
    var dateFrom: Date? = nil
    var dateTo: Date? = nil

    var isActive: Bool {
        stage != nil || channel != nil || aiEnabled != nil || dateFrom != nil || dateTo != nil
    }

    mutating func reset() { self = ConversationFilter() }

    func matches(_ convo: ConversationSummary) -> Bool {
        if let stage, convo.stage != stage { return false }
        if let channel, convo.channel != channel { return false }
        if let ai = aiEnabled, convo.aiOn != ai { return false }
        if let from = dateFrom {
            guard let at = convo.lastMessageAt, at >= Calendar.current.startOfDay(for: from) else { return false }
        }
        if let to = dateTo {
            let end = Calendar.current.startOfDay(for: to).addingTimeInterval(86_399)
            guard let at = convo.lastMessageAt, at <= end else { return false }
        }
        return true
    }
}

/// One row of the workspace's notification feed (public.notifications).
struct FeedItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let conversationID: String?
    let name: String?
    let channel: String?
    let phone: String?
    let detail: [String: String]
    let createdAt: Date

    static let urgentKinds: Set<String> = ["crisis", "handoff"]
    var isUrgent: Bool { Self.urgentKinds.contains(kind) }

    /// Titles from lib/notificationText.ts.
    var title: String {
        [
            "new_lead": "New lead",
            "phone_captured": "Phone number captured",
            "email_captured": "Email captured",
            "insurance_captured": "Insurance captured",
            "card_submitted": "Insurance card uploaded",
            "callback_scheduled": "Callback booked",
            "ready_for_contact": "Ready to call",
            "crisis": "Crisis: needs a person now",
            "handoff": "Asked for a person",
        ][kind] ?? "Update"
    }

    var icon: String {
        switch kind {
        case "new_lead": "message.fill"
        case "phone_captured": "phone.fill"
        case "email_captured": "envelope.fill"
        case "insurance_captured", "card_submitted": "checkmark.shield.fill"
        case "callback_scheduled": "calendar"
        case "ready_for_contact": "phone.arrow.up.right.fill"
        case "crisis": "exclamationmark.triangle.fill"
        case "handoff": "person.fill.questionmark"
        default: "bell.fill"
        }
    }

    /// The line under the title, as the web feed writes it.
    var body: String {
        let who = name ?? "A lead"
        let place = channel.map { $0 == "web" ? "the website" : Labels.channel($0) }
        switch kind {
        case "new_lead":
            return place.map { "\(who) messaged on \($0)." } ?? "\(who) reached out."
        case "phone_captured":
            return phone.map { "\(who) · \($0)" } ?? "\(who) shared a number to call."
        case "email_captured":
            return "\(who) shared an email address."
        case "insurance_captured":
            return detail["payer"].map { "\(who) · \($0)" } ?? "\(who) shared their insurance."
        case "card_submitted":
            return "\(who) sent a photo of their card\(detail["payer"].map { " (\($0))" } ?? "")."
        case "callback_scheduled":
            if let at = ISODate.parse(detail["start_at"]) {
                return "\(who) · \(at.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
            }
            return "\(who) booked a call."
        case "ready_for_contact":
            return "\(who) has a number, coverage and a stated need."
        case "crisis", "handoff":
            return detail["reason"].map { "\(who): \(Labels.reason($0).lowercased())" } ?? "\(who) needs a teammate."
        default:
            return who
        }
    }
}

/// What the agent or a coordinator captured about a lead, for the details sheet.
struct LeadDetails: Hashable, Sendable {
    let name: String
    let phone: String?
    let email: String?
    let channel: String
    let stage: String
    let firstContactAt: Date?
    let adTitle: String?
    let summary: String?
    /// The latest value of each fact (lead_facts), newest wins.
    let facts: [String: String]

    func fact(_ key: String) -> String? {
        guard let value = facts[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
