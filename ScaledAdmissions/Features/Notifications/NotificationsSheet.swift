import SwiftUI
import Supabase

/// Care Assist's notifications sheet, fed by the workspace's notification feed
/// (the same one as the web's bell). "Needs a person" shows only crises and
/// requests for a teammate. Tapping a row opens that conversation.
struct NotificationsSheet: View {
    enum Tab: String, Hashable, Identifiable {
        case all, urgent
        var id: String { rawValue }
    }

    @State private var tab: Tab
    @State private var items: [FeedItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    init(initialTab: Tab) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Theme.surface, Theme.surface.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("Everything").tag(Tab.all)
                        Text("Needs a person").tag(Tab.urgent)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    content
                }
            }
            .navigationTitle(tab == .urgent ? "Needs a Person" : "Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                }
            }
            .task(id: tab) { await load() }
            .task { await subscribe() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if items.isEmpty {
            emptyView
        } else {
            List {
                ForEach(items) { item in
                    row(item)
                        .contentShape(Rectangle())
                        .onTapGesture { open(item) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
    }

    private func row(_ item: FeedItem) -> some View {
        let tint: Color = item.kind == "crisis" ? Theme.bad
            : item.kind == "handoff" ? Theme.warn
            : ["callback_scheduled", "ready_for_contact"].contains(item.kind) ? Theme.good
            : Theme.accent
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.kind == "crisis" ? Theme.badText : Theme.ink)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            if item.conversationID != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.85))
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: tab == .urgent ? "checkmark.bubble" : "bell.slash")
                .font(.largeTitle)
                .foregroundStyle(Theme.ink3)
            Text(errorMessage ?? (tab == .urgent ? "No one is waiting on a person" : "No notifications"))
                .foregroundStyle(Theme.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard let orgID = appState.currentWorkspace?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await SupabaseService.shared.fetchFeed(orgID: orgID, urgentOnly: tab == .urgent)
            errorMessage = nil
        } catch {
            items = []
            errorMessage = "Could not load notifications."
        }
    }

    /// New notifications appear while the sheet is open.
    private func subscribe() async {
        guard let orgID = appState.currentWorkspace?.id else { return }
        let client = SupabaseService.shared.client
        let channel = client.channel("feed-\(orgID)-\(UUID().uuidString.prefix(8))")
        let inserts = channel.postgresChange(
            InsertAction.self, schema: "public", table: "notifications", filter: "org_id=eq.\(orgID)"
        )
        try? await channel.subscribeWithError()
        for await _ in inserts { await load() }
        await client.removeChannel(channel)
    }

    private func open(_ item: FeedItem) {
        guard let id = item.conversationID else { return }
        dismiss()
        appState.pendingConversationID = id
    }
}
