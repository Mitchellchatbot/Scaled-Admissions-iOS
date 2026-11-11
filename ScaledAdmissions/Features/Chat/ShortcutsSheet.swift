import SwiftUI
import Combine

/// Saved replies. Care Assist keeps these in its database; admissions has no
/// table for them yet, so they live on this phone for now.
@MainActor
final class ShortcutsStore: ObservableObject {
    struct Shortcut: Identifiable, Codable, Hashable {
        var id = UUID()
        let text: String
    }

    @Published private(set) var shortcuts: [Shortcut] = []
    private let key = "messageShortcuts"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = saved
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shortcuts.append(Shortcut(text: trimmed))
        save()
    }

    func delete(_ shortcut: Shortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct ShortcutsSheet: View {
    let onSelect: (String) -> Void
    @StateObject private var store = ShortcutsStore()
    @State private var newShortcutText = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()

                List {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.accentText)
                            TextField("New shortcut, tap return to save", text: $newShortcutText, axis: .vertical)
                                .lineLimit(1...3)
                                .focused($addFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    store.add(newShortcutText)
                                    newShortcutText = ""
                                }
                        }
                    } header: {
                        Text("Add shortcut")
                    } footer: {
                        Text("Tapped shortcuts go into the message box so you can change them before sending.")
                    }

                    if !store.shortcuts.isEmpty {
                        Section {
                            ForEach(store.shortcuts) { shortcut in
                                Button {
                                    onSelect(shortcut.text)
                                    dismiss()
                                } label: {
                                    Text(shortcut.text)
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.delete(shortcut)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Your shortcuts")
                        }
                    } else {
                        Section {
                            VStack(spacing: 10) {
                                Image(systemName: "bolt.horizontal")
                                    .font(.title2)
                                    .foregroundStyle(Theme.ink3)
                                Text("No shortcuts yet")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink2)
                                Text("Add your first one above.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Shortcuts")
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
}
