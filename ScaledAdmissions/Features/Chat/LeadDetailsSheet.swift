import SwiftUI

/// Care Assist's visitor details, filled from what the AI agent (or a
/// coordinator) captured about the lead: lead_facts plus the contact row.
struct LeadDetailsSheet: View {
    let details: LeadDetails
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()

                Form {
                    header

                    if hasAny(details.phone, details.email) {
                        Section("Contact") {
                            row("Phone", value: details.phone, icon: "phone.fill", copyable: true)
                            row("Email", value: details.email, icon: "envelope.fill", copyable: true)
                            row("Call back", value: details.fact("callback_time"), icon: "calendar")
                        }
                    }

                    if hasAny(details.fact("who_for"), details.fact("age"), details.fact("occupation"), details.fact("location")) {
                        Section("About") {
                            row("For", value: details.fact("who_for"), icon: "person.2.fill")
                            row("Age", value: details.fact("age"), icon: "person.fill")
                            row("Work", value: details.fact("occupation"), icon: "briefcase.fill")
                            row("Location", value: details.fact("location"), icon: "mappin.circle.fill")
                        }
                    }

                    if hasAny(details.fact("substance"), details.fact("history"), details.fact("program"), details.fact("timeline"), details.fact("urgency")) {
                        Section("Background") {
                            row("Substance", value: details.fact("substance"), icon: "pills.fill")
                            row("History", value: details.fact("history"), icon: "clock.arrow.circlepath", multiline: true)
                            row("Seeking", value: details.fact("program"), icon: "heart.circle.fill", multiline: true)
                            row("Timeline", value: details.fact("timeline"), icon: "hourglass")
                            if let urgency = details.fact("urgency") {
                                urgencyRow(urgency)
                            }
                        }
                    }

                    if hasAny(details.fact("payment_path"), details.fact("payer"), details.fact("plan_type"), details.fact("self_pay_willing")) {
                        Section("Insurance") {
                            row("Paying by", value: details.fact("payment_path"), icon: "creditcard.fill")
                            row("Insurance", value: details.fact("payer"), icon: "checkmark.shield.fill")
                            row("Plan", value: details.fact("plan_type"), icon: "doc.text.fill")
                            row("Will discuss cost", value: details.fact("self_pay_willing"), icon: "dollarsign.circle.fill")
                        }
                    }

                    if let summary = details.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                        Section("Summary") {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                    }

                    Section("Conversation") {
                        row("Channel", value: Labels.channel(details.channel), icon: "bubble.left.and.bubble.right.fill")
                        row("Stage", value: Labels.stage(details.stage), icon: "circle.fill")
                        row("From ad", value: details.adTitle, icon: "megaphone.fill", multiline: true)
                        if let started = details.firstContactAt {
                            HStack {
                                Label("Started", systemImage: "clock")
                                    .labelStyle(RowLabelStyle())
                                Spacer()
                                Text(started.formatted(.relative(presentation: .named)))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Lead Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }

    private var header: some View {
        Section {
            HStack(spacing: 14) {
                Avatar(name: details.name, url: nil, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(details.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if let line = details.phone ?? details.email {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    } else {
                        Text("\(Labels.channel(details.channel)) · \(Labels.stage(details.stage))")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                Spacer()
                if let phone = details.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.accentText, in: Circle())
                    }
                    .accessibilityLabel("Call \(details.name)")
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func row(_ label: String, value: String?, icon: String, copyable: Bool = false, multiline: Bool = false) -> some View {
        if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            HStack(alignment: multiline ? .top : .center) {
                Label(label, systemImage: icon)
                    .labelStyle(RowLabelStyle())
                Spacer(minLength: 16)
                Text(v)
                    .foregroundStyle(Theme.ink)
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if copyable {
                    Button {
                        UIPasteboard.general.string = v
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy \(label.lowercased())")
                }
            }
        }
    }

    private func urgencyRow(_ urgency: String) -> some View {
        let color: Color = switch urgency.lowercased() {
        case let u where u.contains("high") || u.contains("urgent") || u.contains("crisis") || u.contains("today"): Theme.badText
        case let u where u.contains("medium") || u.contains("soon") || u.contains("week"): Theme.warnText
        case let u where u.contains("low"): Theme.goodText
        default: Theme.ink2
        }
        return HStack {
            Label("Urgency", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(RowLabelStyle())
            Spacer()
            Text(urgency.prefix(1).uppercased() + urgency.dropFirst())
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    private func hasAny(_ values: String?...) -> Bool {
        values.contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }
}

private struct RowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(Theme.ink3)
                .frame(width: 20)
            configuration.title
                .foregroundStyle(Theme.ink2)
                .font(.subheadline)
        }
    }
}
