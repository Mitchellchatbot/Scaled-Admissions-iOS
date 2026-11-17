import SwiftUI

/// Care Assist's chat: round back button, the lead's name with a chevron that
/// opens their details, the AI toggle, a shortcuts button, a capsule reply
/// box, and a jump-to-latest button.
struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm: ChatViewModel
    @State private var isAtBottom = true
    @State private var showDetails = false
    @State private var showShortcuts = false
    @State private var inputResetToken = 0
    @State private var chevronScale: CGFloat = 0.2
    @State private var chevronRotation: Double = -20
    @FocusState private var inputFocused: Bool
    private let onModeChange: (ConversationMode) -> Void

    private let bottomID = "BOTTOM"

    init(conversation: ConversationSummary, onModeChange: @escaping (ConversationMode) -> Void = { _ in }) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
        self.onModeChange = onModeChange
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surface, Theme.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let hold = vm.hold {
                    HoldBanner(hold: hold, aiOn: vm.aiOn) {
                        Task { await vm.setAI(on: false) }
                    }
                    .zIndex(1)
                }

                messages
                inputBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    if vm.details != nil { showDetails = true }
                } label: {
                    HStack(spacing: 8) {
                        Text(vm.details?.name ?? vm.conversation.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if vm.details != nil {
                            ZStack {
                                Circle()
                                    .fill(Theme.accentText)
                                    .frame(width: 22, height: 22)
                                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 2)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .scaleEffect(chevronScale)
                            .rotationEffect(.degrees(chevronRotation))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.details == nil)
                .accessibilityHint("Shows what we know about this lead")
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                }
                .accessibilityLabel("Back")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.setAI(on: !vm.aiOn) }
                } label: {
                    ZStack {
                        Capsule()
                            .fill(vm.aiOn ? Theme.accent.opacity(0.15) : Color.gray.opacity(0.12))
                            .frame(width: 68, height: 30)

                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(vm.mode == .closed ? "Closed" : vm.aiOn ? "AI On" : "AI Off")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(vm.aiOn ? Theme.accentText : Color.gray)

                        if vm.isChangingMode {
                            Capsule()
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 68, height: 30)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }
                .disabled(vm.isChangingMode || vm.mode == .closed)
                .animation(.easeInOut(duration: 0.2), value: vm.aiOn)
                .accessibilityLabel(vm.mode == .closed ? "Chat closed. Reopen it below to reply."
                                    : vm.aiOn ? "AI replies on. Tap to turn off." : "AI replies off. Tap to turn on.")
            }
        }
        .task { await vm.start() }
        // Back from the background: messages that arrived meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await vm.resume() } }
        }
        .onChange(of: vm.mode) { _, mode in onModeChange(mode) }
        .onChange(of: vm.details) { _, new in
            guard new != nil else { return }
            // Springs in so people notice the name can be tapped.
            chevronScale = 0.2
            chevronRotation = -20
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.1)) {
                chevronScale = 1.0
                chevronRotation = 0
            }
        }
        .sheet(isPresented: $showDetails) {
            if let details = vm.details {
                LeadDetailsSheet(details: details)
            }
        }
        .sheet(isPresented: $showShortcuts) {
            ShortcutsSheet { text in
                if vm.draft.isEmpty {
                    vm.draft = text
                } else {
                    vm.draft.append(vm.draft.hasSuffix(" ") ? text : " \(text)")
                }
                inputFocused = true
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messages: some View {
        if vm.isLoading && vm.messages.isEmpty {
            ProgressView("Loading messages…")
                .padding()
                .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        if vm.messages.isEmpty {
                            Text(vm.errorMessage ?? "No messages yet.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink3)
                                .padding(.top, 40)
                        }

                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, message in
                            let previous = index > 0 ? vm.messages[index - 1] : nil
                            VStack(spacing: 12) {
                                if Grouping.startsNewStretch(previous, message) {
                                    TimeDivider(date: message.createdAt)
                                }
                                MessageBubble(message: message)
                            }
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(
                                        scale: 0.4,
                                        anchor: message.isOutbound ? .bottomTrailing : .bottomLeading
                                    )
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 30)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))
                                )
                            )
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: vm.messages.map(\.id))
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    // visibleRect accounts for the bar insets, which contentOffset does not.
                    geo.visibleRect.maxY < geo.contentSize.height - 60
                } action: { _, notAtBottom in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAtBottom = !notAtBottom
                    }
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if isAtBottom {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isAtBottom {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.accentText)
                                .background(Circle().fill(.white).padding(4))
                                .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .accessibilityLabel("Jump to latest")
                    }
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = vm.errorMessage, !vm.messages.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.badText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }

            if vm.mode == .closed {
                closedBar
            } else {
                composer
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: vm.mode == .closed)
    }

    /// Where the composer sits, for a closed chat: replying is blocked until
    /// it is reopened, the same rule as the web inbox.
    private var closedBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This chat is closed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Reopen it to reply. The AI stays off.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            Button {
                Task { await vm.reopen() }
            } label: {
                ZStack {
                    Text("Reopen")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(vm.isChangingMode ? 0 : 1)
                    if vm.isChangingMode {
                        ProgressView().tint(.white)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.accentText)
                .clipShape(Capsule())
                .shadow(color: Theme.accent.opacity(0.4), radius: 6, y: 4)
            }
            .disabled(vm.isChangingMode)
            .accessibilityHint("Hands the chat back to your team so you can reply.")
        }
        .padding(.vertical, 4)
        .padding(.trailing, 2)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
    }

    private var composer: some View {
            HStack(spacing: 10) {
                Button {
                    showShortcuts = true
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Shortcuts")

                TextField(vm.aiOn ? "Reply (turns the AI off)" : "Type a message…", text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
                    .id(inputResetToken)

                Button {
                    let wasFocused = inputFocused
                    inputFocused = false
                    inputResetToken &+= 1
                    Task {
                        await vm.send()
                        if wasFocused { inputFocused = true }
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.accentText)
                        .clipShape(Circle())
                        .shadow(color: Theme.accent.opacity(0.4), radius: 6, y: 4)
                        .scaleEffect(vm.draft.isEmpty ? 0.95 : 1)
                        .animation(.spring(response: 0.3), value: vm.draft)
                }
                .disabled(!vm.canSend)
                .opacity(vm.canSend ? 1 : 0.6)
                .accessibilityLabel("Send")
            }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ThreadMessage

    var body: some View {
        if message.sender == .system {
            Text(message.body ?? "")
                .font(.footnote)
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
        } else {
            HStack {
                if message.isOutbound { Spacer(minLength: 60) }

                VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 6) {
                    if let body = message.body, !body.isEmpty {
                        Text(body)
                            .font(.system(size: 15))
                            .foregroundColor(message.isOutbound ? .white : .primary)
                            .textSelection(.enabled)
                    }
                    ForEach(message.media, id: \.url) { item in
                        MediaView(item: item, outbound: message.isOutbound)
                    }
                    Text(caption)
                        .font(.caption2)
                        .foregroundColor(message.isOutbound ? .white.opacity(0.8) : .secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(message.isOutbound ? Theme.accentText : Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
                .opacity(message.isPending ? 0.6 : 1)

                if !message.isOutbound { Spacer(minLength: 60) }
            }
        }
    }

    /// "AI agent · 9:15 PM · Read" on our side; just the time on theirs.
    private var caption: String {
        var parts: [String] = []
        if message.isOutbound, let label = message.senderLabel { parts.append(label) }
        parts.append(message.createdAt.formatted(date: .omitted, time: .shortened))
        if message.isOutbound {
            if message.isPending {
                parts.append("Sending")
            } else if message.readAt != nil {
                parts.append("Read")
            } else if message.deliveredAt != nil {
                parts.append("Delivered")
            }
        }
        return parts.joined(separator: " · ")
    }
}

private struct MediaView: View {
    let item: MessageMedia
    let outbound: Bool
    @State private var image: UIImage?
    @State private var failed = false

    private var url: URL? {
        guard item.type == "image" || item.type == "sticker",
              let url = URL(string: item.url), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    /// Messenger's thumbs-up and stickers arrive as tiny images; blown up to
    /// photo size they turn into a blurry wall, so they stay small.
    private var isSmall: Bool {
        guard let image else { return item.type == "sticker" }
        return item.type == "sticker" || max(image.size.width * image.scale, image.size.height * image.scale) < 300
    }

    var body: some View {
        if let url, !failed {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: isSmall ? 56 : 220, maxHeight: isSmall ? 56 : 220)
                        .clipShape(RoundedRectangle(cornerRadius: isSmall ? 0 : 14, style: .continuous))
                        .accessibilityLabel(isSmall ? "Sticker" : "Photo")
                } else {
                    ProgressView().frame(width: 56, height: 56)
                }
            }
            .task(id: url) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let loaded = UIImage(data: data) { image = loaded } else { failed = true }
                } catch {
                    failed = true
                }
            }
        } else {
            Label(item.type == "image" ? "Photo" : "\(item.type.capitalized) attachment", systemImage: "paperclip")
                .font(.footnote)
                .foregroundStyle(outbound ? .white.opacity(0.9) : Theme.ink2)
        }
    }
}

/// The agent is holding the lead until a person takes over. Tap for the
/// whole reason and when it was raised; it springs open and shut.
private struct HoldBanner: View {
    let hold: Hold
    let aiOn: Bool
    let takeOver: () -> Void

    @State private var expanded = false

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hold.crisis ? "exclamationmark.triangle.fill" : "person.fill.questionmark")
                    .padding(.top, 2)
                    .symbolEffect(.bounce, value: expanded)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(hold.crisis ? "Crisis" : "Needs a person")
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    Text(hold.reason)
                        .font(.footnote)
                        .lineLimit(expanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: expanded)
                }
                Spacer(minLength: 8)
                if aiOn {
                    Button("Take over", action: takeOver)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accentText, in: Capsule())
                }
            }

            if expanded, !details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details, id: \.label) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.caption.weight(.semibold))
                                .frame(width: 16)
                            Text(item.label)
                                .font(.footnote.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(item.value)
                                .font(.footnote)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 30)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .foregroundStyle(hold.crisis ? Theme.badText : Theme.warnText)
        .padding(14)
        .background(hold.crisis ? Theme.badSoft : Theme.warnSoft, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(spring) { expanded.toggle() }
        }
        .buttonStyleLikePress()
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Shows less." : "Shows the full reason and when it was raised.")
    }

    private var details: [(icon: String, label: String, value: String)] {
        var rows: [(icon: String, label: String, value: String)] = []
        if let at = hold.raisedAt {
            rows.append(("clock", "Raised", Self.when(at)))
        }
        switch hold.handoff {
        case "now": rows.append(("phone.fill", "Wants", "A call now"))
        case "scheduled":
            rows.append(("calendar", "Callback", hold.callbackAt.map(Self.when) ?? "Booked"))
        default: break
        }
        return rows
    }

    private static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

/// Squishes a little while a finger is down, like a system card.
private struct PressSquish: ViewModifier {
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true }
            )
    }
}

private extension View {
    func buttonStyleLikePress() -> some View { modifier(PressSquish()) }
}

private struct TimeDivider: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.7), in: Capsule())
    }

    private var label: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(time)"
    }
}

/// When to show a centered time (a new stretch of conversation, as in iMessage).
enum Grouping {
    static func startsNewStretch(_ previous: ThreadMessage?, _ message: ThreadMessage) -> Bool {
        guard let previous else { return true }
        return message.createdAt.timeIntervalSince(previous.createdAt) > 60 * 60
            || !Calendar.current.isDate(previous.createdAt, inSameDayAs: message.createdAt)
    }
}
