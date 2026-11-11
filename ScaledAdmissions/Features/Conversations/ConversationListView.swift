import SwiftUI

/// Care Assist's conversation list, for admissions: filter (top left),
/// account (top right), a floating bar for search, "Needs a person" and
/// notifications, and card rows that page in as you scroll.
struct ConversationListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = ConversationListViewModel()
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var showSearch = false
    @State private var feedSheet: NotificationsSheet.Tab?
    @State private var deepLinkConvo: ConversationSummary?
    @State private var hasUnseenNotifications = false
    @AppStorage("notificationsSeenAt") private var notificationsSeenAt: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Theme.surface, Theme.surface.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    if vm.isLoading && vm.conversations.isEmpty {
                        loadingView
                    } else if let error = vm.errorMessage, vm.conversations.isEmpty {
                        errorView(error)
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityLabel("Account")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: vm.filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityLabel("Filter")
                }
            }
            .safeAreaInset(edge: .bottom) {
                floatingIsland
            }
            .navigationDestination(isPresented: $showSettings) {
                AccountSettingsView()
            }
            .navigationDestination(item: $deepLinkConvo) { convo in
                chat(for: convo)
            }
            .sheet(isPresented: $showFilter) {
                ConversationFilterSheet(
                    filter: $vm.filter,
                    availableStages: vm.availableStages,
                    availableChannels: vm.availableChannels
                )
            }
            .sheet(item: $feedSheet) { tab in
                NotificationsSheet(initialTab: tab)
                    .environmentObject(appState)
            }
            .task(id: appState.currentWorkspace?.id) {
                guard let id = appState.currentWorkspace?.id else { return }
                deepLinkConvo = nil
                await vm.start(orgID: id)
                await checkNotifications()
            }
            // Back from a chat: catch up at once, then keep the order honest
            // even if realtime misses an event. Cancelled while off screen.
            .task {
                await vm.refresh()
                await vm.refreshWhileVisible()
            }
            .onChange(of: vm.conversations.first?.lastMessageAt) { _, _ in
                Task { await checkNotifications() }
            }
            // iOS drops the live connection in the background, so coming back
            // re-reads the list and listens again.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await vm.resume()
                    await checkNotifications()
                }
            }
            .onChange(of: feedSheet) { _, tab in
                // Closing the feed marks it read.
                if tab == nil {
                    notificationsSeenAt = Date().timeIntervalSince1970
                    hasUnseenNotifications = false
                }
            }
            // onAppear too: a notification tapped while the app was closed
            // arrives before this screen exists.
            .onAppear { openPending(appState.pendingConversationID) }
            .onChange(of: appState.pendingConversationID) { _, id in openPending(id) }
        }
    }

    private func openPending(_ id: String?) {
        guard let id else { return }
        appState.pendingConversationID = nil
        Task {
            if let convo = await vm.conversation(id: id) { deepLinkConvo = convo }
        }
    }

    private func chat(for convo: ConversationSummary) -> some View {
        ChatView(conversation: convo) { mode in
            vm.updateMode(mode, for: convo.id)
        }
    }

    private func checkNotifications() async {
        guard let orgID = appState.currentWorkspace?.id,
              let latest = try? await SupabaseService.shared.fetchFeed(orgID: orgID, limit: 1).first else { return }
        hasUnseenNotifications = latest.createdAt.timeIntervalSince1970 > notificationsSeenAt
    }

    // MARK: - Floating island

    private var floatingIsland: some View {
        HStack(spacing: 0) {
            islandButton(icon: "magnifyingglass", isActive: showSearch, label: "Search") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showSearch.toggle()
                    if !showSearch { vm.searchText = "" }
                }
            }

            islandDivider

            islandButton(icon: "exclamationmark.bubble", isActive: false, label: "Needs a person") {
                feedSheet = .urgent
            }

            islandDivider

            islandButton(icon: "bell", isActive: false, label: "Notifications", badge: hasUnseenNotifications) {
                feedSheet = .all
            }
        }
        .padding(.horizontal, 8)
        .glassEffect(in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(.bottom, 12)
    }

    private func islandButton(
        icon: String,
        isActive: Bool,
        label: String,
        badge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isActive ? Theme.accentText : Theme.ink2)
                .frame(width: 60, height: 52)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: -16, y: 13)
                    }
                }
        }
        .accessibilityLabel(label)
    }

    private var islandDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 22)
    }

    // MARK: - Search bar

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.ink3)
                .font(.system(size: 15))

            TextField("Search names and messages", text: $vm.searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.ink3)
                }
            }

            Button("Cancel") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.searchText = ""
                    showSearch = false
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.accentText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - List

    /// Which workspace this is, under the title. Someone in two workspaces
    /// otherwise has no way to tell the list is not the one the website shows.
    @ViewBuilder
    private var workspaceSwitcher: some View {
        if let current = appState.currentWorkspace {
            HStack {
                if appState.workspaces.count > 1 {
                    Menu {
                        ForEach(appState.workspaces) { workspace in
                            Button {
                                appState.currentWorkspace = workspace
                            } label: {
                                if workspace.id == current.id {
                                    Label(workspace.name, systemImage: "checkmark")
                                } else {
                                    Text(workspace.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "building.2")
                                .font(.system(size: 13, weight: .semibold))
                            Text(current.name)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accentSoft, in: Capsule())
                    }
                    .accessibilityLabel("Workspace: \(current.name). Switch workspace")
                } else {
                    Label(current.name, systemImage: "building.2")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
            }
        }
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                workspaceSwitcher

                if showSearch {
                    searchBarView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if vm.isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if vm.displayedConversations.isEmpty {
                    noResultsView
                        .padding(.top, 40)
                } else {
                    ForEach(vm.displayedConversations) { convo in
                        NavigationLink {
                            chat(for: convo)
                        } label: {
                            ConversationListRow(
                                convo: convo,
                                searchQuery: vm.isSearchActive ? vm.searchText : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if !vm.isSearchActive && convo.id == vm.displayedConversations.last?.id {
                                Task { await vm.loadNextPage() }
                            }
                        }
                    }

                    if vm.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
        .refreshable { await vm.load() }
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: vm.isSearchActive ? "magnifyingglass"
                  : vm.filter.isActive ? "line.3.horizontal.decrease.circle" : "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(Theme.ink3)
            Text(vm.isSearchActive ? "No results for \"\(vm.searchText)\""
                 : vm.filter.isActive ? "No conversations match your filters"
                 : "No conversations yet. New leads show up here the moment they message you.")
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            if vm.filter.isActive {
                Button("Clear Filters") {
                    vm.filter.reset()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Theme.accentText)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading conversations…")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.warn)
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await vm.load() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Theme.accentText)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding()
    }
}

// MARK: - Row

struct ConversationListRow: View {
    let convo: ConversationSummary
    var searchQuery: String? = nil

    /// A person has the chat: highlighted like Care Assist's unread rows,
    /// because the AI is no longer answering it.
    private var needsYou: Bool { convo.mode == .humanTakeover }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Avatar(name: convo.name, url: convo.photoURL, size: 46, emphasized: needsYou)

                if needsYou {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(convo.name)
                        .font(needsYou ? .headline.weight(.black) : .headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Spacer()

                    if let date = convo.lastMessageAt {
                        Text(RelativeTime.short(date))
                            .font(.caption)
                            .foregroundStyle(needsYou ? Theme.accentText : Theme.ink3)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(convo.stageLabel) · \(convo.channelLabel)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    ModeBadge(mode: convo.mode)
                }

                SourceChip(source: convo.source)

                if let query = searchQuery, let snippet = convo.matchingSnippet {
                    highlightedSnippet(snippet, query: query)
                        .font(.subheadline)
                        .lineLimit(2)
                } else if let preview = convo.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(needsYou ? Theme.accentSoft : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    needsYou ? Theme.accent.opacity(0.35) : Color.white.opacity(0.05),
                    lineWidth: needsYou ? 1.2 : 1
                )
        )
        .shadow(
            color: needsYou ? Theme.accent.opacity(0.12) : .black.opacity(0.05),
            radius: 8,
            y: 4
        )
    }

    private func highlightedSnippet(_ text: String, query: String) -> Text {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return Text(text).foregroundColor(Theme.ink2.opacity(0.8))
        }
        let before = String(text[..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])
        return Text(
            "\(Text(before).foregroundStyle(Theme.ink2.opacity(0.8)))\(Text(match).foregroundStyle(Theme.accentText).bold())\(Text(after).foregroundStyle(Theme.ink2.opacity(0.8)))"
        )
    }
}

/// Where the lead came from: the ad's campaign, a link, the website chat.
struct SourceChip: View {
    let source: LeadSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(source.label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(source == .direct ? Theme.ink3 : Theme.ink2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.chipFlat, in: Capsule())
        .accessibilityLabel("Source: \(source.label)")
    }
}

/// "AI on" in blue, or "You have it", matching the web inbox.
struct ModeBadge: View {
    let mode: ConversationMode

    var body: some View {
        switch mode {
        case .aiActive:
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                Text("AI")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accentSoft, in: Capsule())
        case .humanTakeover:
            Text("You have it")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.accentText, in: Capsule())
        case .closed:
            Text("Closed")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.chipFlat, in: Capsule())
        }
    }
}

struct Avatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 46
    var emphasized = false

    /// Initials from the words that start with a letter. Unnamed leads are
    /// shown by their platform id, which has none, so they get a person icon.
    private var initials: String {
        name.split(separator: " ")
            .compactMap { $0.first }
            .filter(\.isLetter)
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(emphasized ? 0.25 : 0.15))
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Theme.accentText.opacity(0.7))
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
            }
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }
}

/// "3:04 PM" today, "Yesterday", a weekday this week, then "Nov 3".
enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
