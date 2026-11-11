import Foundation
import Combine
import Supabase

/// Care Assist's list model: pages of 20, a filter sheet, debounced search
/// over names and messages, and realtime refresh that keeps rows steady.
@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMorePages = true
    @Published private(set) var errorMessage: String?
    @Published var filter = ConversationFilter.standard {
        // Stage is filtered on the server so every page is full of matches.
        didSet { if filter.stage != oldValue.stage { Task { await load() } } }
    }
    @Published var searchText = ""
    @Published private(set) var searchResults: [ConversationSummary] = []
    @Published private(set) var isSearching = false

    private let pageSize = SupabaseService.pageSize
    private var currentPage = 0
    private var orgID: String?
    private var realtimeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task { await self?.handleSearchChange(query) }
            }
            .store(in: &cancellables)
    }

    deinit {
        realtimeTask?.cancel()
        refreshTask?.cancel()
    }

    var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Search results when searching, the filtered pages otherwise.
    /// Search looks across every chat, whatever the filter: the list opens on
    /// one stage, and a name typed in search should still turn up.
    var displayedConversations: [ConversationSummary] {
        isSearchActive ? searchHits : conversations.filter(filter.matches)
    }

    /// Loaded chats whose name or id matches show at once, as on the web; the
    /// server's wider search (captured facts, summaries, messages) joins them.
    private var searchHits: [ConversationSummary] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var byID: [String: ConversationSummary] = [:]
        for convo in conversations where convo.name.lowercased().contains(needle) { byID[convo.id] = convo }
        for convo in searchResults { byID[convo.id] = convo }
        return byID.values.sorted(by: ConversationSummary.newestFirst)
    }

    /// Every stage, always: the list holds one stage at a time, so what is
    /// loaded says nothing about which others have chats.
    var availableStages: [String] { Labels.stageOrder }

    var availableChannels: [String] {
        let present = Set(conversations.map(\.channel))
        return ["messenger", "instagram", "web", "sms"].filter { present.contains($0) || filter.channel == $0 }
    }

    // MARK: - Load / pagination

    func start(orgID: String) async {
        guard self.orgID != orgID else { return }
        self.orgID = orgID
        conversations = []
        filter = .standard
        searchText = ""
        await load()
        subscribe(orgID: orgID)
    }

    func load() async {
        guard let orgID else { return }
        currentPage = 0
        hasMorePages = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let stage = filter.stage
            let page = try await SupabaseService.shared.fetchConversations(orgID: orgID, from: 0, to: pageSize - 1, stage: stage)
            // A quicker stage change already replaced this read.
            guard stage == filter.stage else { return }
            conversations = page.sorted(by: ConversationSummary.newestFirst)
            hasMorePages = page.count == pageSize
        } catch {
            errorMessage = "Could not load conversations."
        }
    }

    func loadNextPage() async {
        guard let orgID, hasMorePages, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = currentPage + 1
        let from = next * pageSize
        do {
            let stage = filter.stage
            let page = try await SupabaseService.shared.fetchConversations(orgID: orgID, from: from, to: from + pageSize - 1, stage: stage)
            guard stage == filter.stage else { return }
            currentPage = next
            // Offsets drift when a chat jumps to the top between pages: take
            // the fresher copy of any repeat and keep the whole list in time order.
            var byID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
            for convo in page { byID[convo.id] = convo }
            conversations = byID.values.sorted(by: ConversationSummary.newestFirst)
            hasMorePages = page.count == pageSize
        } catch {
            // Silent: pull to refresh tries again.
        }
    }

    /// A conversation by id, for a notification tap that points outside the loaded pages.
    func conversation(id: String) async -> ConversationSummary? {
        if let found = conversations.first(where: { $0.id == id }) { return found }
        guard let orgID else { return nil }
        return try? await SupabaseService.shared.fetchConversations(orgID: orgID, ids: [id]).first
    }

    func updateMode(_ mode: ConversationMode, for id: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].mode = mode }
        if let index = searchResults.firstIndex(where: { $0.id == id }) { searchResults[index].mode = mode }
    }

    // MARK: - Search

    private func handleSearchChange(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let orgID else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await SupabaseService.shared.searchConversations(orgID: orgID, query: trimmed)
        } catch {
            searchResults = []
        }
    }

    // MARK: - Realtime

    /// Realtime respects RLS; an event is only a cue to re-read, as on the web.
    private func subscribe(orgID: String) {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            let client = SupabaseService.shared.client
            let channel = client.channel("inbox-\(orgID)-\(UUID().uuidString.prefix(8))")
            let conversationChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "conversations", filter: "org_id=eq.\(orgID)"
            )
            let messageInserts = channel.postgresChange(
                InsertAction.self, schema: "public", table: "messages", filter: "org_id=eq.\(orgID)"
            )
            try? await channel.subscribeWithError()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in conversationChanges { await self?.scheduleRefresh() }
                }
                group.addTask {
                    for await _ in messageInserts { await self?.scheduleRefresh() }
                }
            }
            await client.removeChannel(channel)
        }
    }

    /// Back from the background: catch up on what was missed and reconnect.
    func resume() async {
        guard let orgID else { return }
        await refresh()
        subscribe(orgID: orgID)
    }

    /// Bursts (the AI replying, receipts arriving) collapse into one re-read.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// A safety net while the list is on screen: realtime can drop events
    /// without saying so, which leaves chats out of order until a pull.
    func refreshWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Re-reads everything loaded so far, keeping unchanged rows as they were
    /// so the list does not flicker.
    func refresh() async {
        guard let orgID else { return }
        let loaded = max((currentPage + 1) * pageSize, conversations.count)
        let stage = filter.stage
        guard let fresh = try? await SupabaseService.shared.fetchConversations(orgID: orgID, from: 0, to: loaded - 1, stage: stage),
              stage == filter.stage else { return }
        let existing = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        var merged = Dictionary(uniqueKeysWithValues: fresh.map { new in
            (new.id, existing[new.id].map { $0 == new ? $0 : new } ?? new)
        })
        // Chats past the re-read window stay, rather than vanishing; one that
        // left this stage goes.
        let loadedIDs = Set(fresh.map(\.id))
        for old in conversations.dropFirst(fresh.count) where merged[old.id] == nil && !loadedIDs.contains(old.id) {
            merged[old.id] = old
        }
        conversations = merged.values.sorted(by: ConversationSummary.newestFirst)
    }
}
