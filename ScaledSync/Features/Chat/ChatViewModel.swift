import Foundation
import Combine
import Supabase

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ThreadMessage] = []
    @Published private(set) var mode: ConversationMode
    @Published private(set) var hold: Hold?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var isChangingMode = false
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published private(set) var details: LeadDetails?

    let conversation: ConversationSummary
    private var realtimeTask: Task<Void, Never>?
    /// Signed links for stored photos. They last an hour, so they are kept for the visit.
    private var signedMedia: [String: String] = [:]

    init(conversation: ConversationSummary) {
        self.conversation = conversation
        self.mode = conversation.mode
    }

    deinit { realtimeTask?.cancel() }

    var aiOn: Bool { mode == .aiActive }
    var canSend: Bool { mode != .closed && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending }

    func start() async {
        isLoading = messages.isEmpty
        defer { isLoading = false }
        await reload()
        subscribe()
        await loadDetails()
    }

    func reload() async {
        let id = conversation.id
        async let fetchedMessages = SupabaseService.shared.fetchMessages(conversationID: id)
        async let fetchedMode = SupabaseService.shared.fetchMode(conversationID: id)
        async let fetchedHold = SupabaseService.shared.fetchHold(conversationID: id)
        do {
            let fresh = await withSignedMedia(try await fetchedMessages)
            // Keep a reply that is still on its way at the bottom.
            messages = fresh + messages.filter(\.isPending)
            if let newMode = try? await fetchedMode, !isChangingMode { mode = newMode }
            hold = try? await fetchedHold
        } catch {
            if messages.isEmpty { errorMessage = "Could not load this chat." }
        }
    }

    /// Photos kept in private storage come back as `storage:` references the
    /// phone cannot open; the server signs them (app/api/mobile/.../media).
    private func withSignedMedia(_ list: [ThreadMessage]) async -> [ThreadMessage] {
        let missing = list.flatMap(\.media).map(\.url)
            .filter { $0.hasPrefix("storage:") && signedMedia[$0] == nil }
        if !missing.isEmpty,
           let urls = try? await MobileAPI.mediaURLs(conversationID: conversation.id) {
            signedMedia.merge(urls) { _, new in new }
        }
        guard !signedMedia.isEmpty else { return list }
        return list.map { message in
            var copy = message
            copy.media = message.media.map { MessageMedia(type: $0.type, url: signedMedia[$0.url] ?? $0.url) }
            return copy
        }
    }

    /// iOS drops the live connection in the background; catch up and listen again.
    func resume() async {
        await reload()
        subscribe()
    }

    func loadDetails() async {
        details = try? await SupabaseService.shared.fetchLeadDetails(
            contactID: conversation.contactID,
            summary: conversation.summary
        )
    }

    /// Sends as the signed-in teammate. Replying hands the chat to a person,
    /// so the AI stops answering it (lib/conversationControl.ts).
    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A closed chat stays quiet until someone reopens it, as on the web.
        guard mode != .closed, !text.isEmpty, !isSending else { return }

        draft = ""
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        let pending = ThreadMessage(
            id: "pending-\(UUID().uuidString)",
            isOutbound: true,
            sender: .human,
            body: text,
            media: [],
            createdAt: Date(),
            deliveredAt: nil,
            readAt: nil,
            isPending: true
        )
        messages.append(pending)

        do {
            try await MobileAPI.sendReply(conversationID: conversation.id, body: text)
            mode = .humanTakeover
            messages.removeAll { $0.id == pending.id }
            await reload()
        } catch {
            messages.removeAll { $0.id == pending.id }
            // Never lose what they typed.
            if draft.isEmpty { draft = text }
            errorMessage = error.localizedDescription
        }
    }

    /// The web's "Reopen chat": back to a teammate, with the AI still off
    /// until someone switches it on.
    func reopen() async {
        guard mode == .closed else { return }
        await setAI(on: false)
    }

    func setAI(on: Bool) async {
        let previous = mode
        let next: ConversationMode = on ? .aiActive : .humanTakeover
        guard next != previous else { return }
        mode = next   // flips the moment it is pressed
        isChangingMode = true
        defer { isChangingMode = false }
        do {
            try await MobileAPI.setMode(conversationID: conversation.id, mode: next)
            if on { hold = nil }
        } catch {
            mode = previous
            errorMessage = "Could not change that. Try again."
        }
    }

    /// New messages, and delivery and read receipts, arrive while reading.
    private func subscribe() {
        realtimeTask?.cancel()
        let id = conversation.id
        realtimeTask = Task { [weak self] in
            let client = SupabaseService.shared.client
            let channel = client.channel("thread-\(id)")
            let messageChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "messages", filter: "conversation_id=eq.\(id)"
            )
            let conversationChanges = channel.postgresChange(
                UpdateAction.self, schema: "public", table: "conversations", filter: "id=eq.\(id)"
            )
            try? await channel.subscribeWithError()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in messageChanges { await self?.reload() }
                }
                group.addTask {
                    for await _ in conversationChanges { await self?.reload() }
                }
            }
            await client.removeChannel(channel)
        }
    }
}
