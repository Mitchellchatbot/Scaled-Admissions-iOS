import SwiftUI

/// Care Assist's filter sheet: stage and channel instead of status and website.
struct ConversationFilterSheet: View {
    @Binding var filter: ConversationFilter
    let availableStages: [String]
    let availableChannels: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        filterSection("AI Assistant") {
                            HStack(spacing: 10) {
                                ForEach([(nil, "All"), (true, "On"), (false, "You have it")], id: \.1) { value, label in
                                    let isSelected = filter.aiEnabled == value
                                    Button(label) {
                                        filter.aiEnabled = isSelected ? nil : value
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Theme.accentText : Theme.chipFlat)
                                    .foregroundStyle(isSelected ? .white : Theme.ink)
                                    .clipShape(Capsule())
                                }
                            }
                        }

                        if !availableStages.isEmpty {
                            filterSection("Stage") {
                                FilterChipRow(
                                    options: [nil] + availableStages.map { Optional($0) },
                                    selected: $filter.stage,
                                    label: { $0.map(Labels.stage) ?? "All" }
                                )
                            }
                        }

                        if availableChannels.count > 1 || filter.channel != nil {
                            filterSection("Channel") {
                                FilterChipRow(
                                    options: [nil] + availableChannels.map { Optional($0) },
                                    selected: $filter.channel,
                                    label: { $0.map(Labels.channel) ?? "All" }
                                )
                            }
                        }

                        filterSection("Last Message") {
                            VStack(spacing: 12) {
                                dateRow(label: "From", date: $filter.dateFrom)
                                dateRow(label: "To", date: $filter.dateTo)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        filter.reset()
                    }
                    .foregroundStyle(filter.isActive ? Theme.accentText : Theme.ink3)
                    .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink2)
            content()
        }
    }

    @ViewBuilder
    private func dateRow(label: String, date: Binding<Date?>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if date.wrappedValue != nil {
                    Button("Clear") { date.wrappedValue = nil }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentText)
                } else {
                    Button("Set") { date.wrappedValue = Date() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentText)
                }
            }
            .padding()

            if let bound = date.wrappedValue {
                DatePicker("", selection: Binding(
                    get: { bound },
                    set: { date.wrappedValue = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.accentText)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FilterChipRow: View {
    let options: [String?]
    @Binding var selected: String?
    let label: (String?) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let isSelected = selected == option
                    Button(label(option)) {
                        selected = isSelected ? nil : option
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isSelected ? Theme.accentText : Theme.chipFlat)
                    .foregroundStyle(isSelected ? .white : Theme.ink)
                    .clipShape(Capsule())
                }
            }
        }
    }
}
