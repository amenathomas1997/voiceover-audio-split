// ClipboardHistory.swift — the last 20 pieces of text copied, newest first, to
// hear again or copy back. The clipboard is watched by ClipboardWatcher (in
// Extras.swift), which already skips what password managers mark as concealed
// or transient. Kept in memory only, never saved to disk, and gone when the app quits.

import AppKit
import SwiftUI

final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()
    static let limit = 20
    /// Setting: keep the history (on unless turned off).
    static let enabledKey = "clipboardHistory"
    /// Very long copies are kept shortened, so the history stays small.
    static let longest = 100_000

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let time: Date
    }

    /// Newest first.
    @Published private(set) var items: [Item] = []

    private let defaults: UserDefaults
    private let announce: (String) -> Void

    init(defaults: UserDefaults = .standard, announce: @escaping (String) -> Void = Announcer.say) {
        self.defaults = defaults
        self.announce = announce
    }

    var isEnabled: Bool {
        // Off until turned on: copied text can be private.
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? false }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { items = [] }
            if self === Self.shared { ClipboardWatcher.refresh() }
        }
    }

    /// Adds copied text. Copying something already in the list moves it to the top.
    func record(_ text: String, at time: Date = Date()) {
        guard isEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let kept = text.count > Self.longest ? String(text.prefix(Self.longest)) : text
        items.removeAll { $0.text == kept }
        items.insert(Item(text: kept, time: time), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    func clear() {
        items = []
        announce(String(localized: "Clipboard history cleared."))
    }

    /// Puts an item back on the clipboard (it moves to the top of the list).
    func copy(_ item: Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        record(item.text)
        // With "say what you copy" on, the clipboard watcher says it already.
        if !Preferences.shared.announceClipboard {
            announce(String(localized: "Copied: \(Self.short(item.text))"))
        }
    }

    /// The item `number` copies ago: 1 is the newest.
    func item(_ number: Int) -> Item? {
        number >= 1 && number <= items.count ? items[number - 1] : nil
    }

    /// What "say clipboard item N" says.
    func spokenItem(_ number: Int) -> String {
        guard !items.isEmpty else { return String(localized: "The clipboard history is empty.") }
        guard let item = item(number) else {
            return items.count == 1 ? String(localized: "There is only 1 item in the clipboard history.")
                                    : String(localized: "There are only \(items.count) items in the clipboard history.")
        }
        return String(localized: "Item \(number) of \(items.count): \(Self.short(item.text, limit: 1000))")
    }

    /// Says the item `number` copies ago: 1 is the newest, 2 the one before.
    func speak(_ number: Int) { announce(spokenItem(number)) }

    /// Copies the item `number` copies ago back to the clipboard.
    func copy(number: Int) {
        guard let item = item(number) else { return announce(spokenItem(number)) }
        copy(item)
    }

    static func short(_ text: String, limit: Int = 120) -> String {
        let flat = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

// MARK: - Window

struct ClipboardHistoryView: View {
    @ObservedObject var history = ClipboardHistory.shared
    @State private var selection: ClipboardHistory.Item.ID?

    private static let timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .short
        return format
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !history.isEnabled {
                Text(String(localized: "Clipboard history is off."))
            } else if history.items.isEmpty {
                Text(String(localized: "Nothing yet. Text you copy will appear here, newest first."))
            }
            Toggle(String(localized: "Keep clipboard history"), isOn: Binding(get: { history.isEnabled },
                                                                              set: { history.isEnabled = $0 }))
            List(Array(history.items.enumerated()), id: \.element.id, selection: $selection) { index, item in
                Text(ClipboardHistory.short(item.text, limit: 200))
                    .lineLimit(2)
                    .accessibilityLabel(String(localized: "\(ClipboardHistory.short(item.text, limit: 300)), copied at \(Self.timeFormat.string(from: item.time)), \(index + 1) of \(history.items.count)"))
                    .tag(item.id)
            }
            .accessibilityLabel(String(localized: "Clipboard history, newest first"))
            .onKeyPress(.return) {
                copySelected()
                return .handled
            }
            HStack {
                Button(String(localized: "Copy selected"), action: copySelected).disabled(selection == nil)
                Spacer()
                Button(String(localized: "Clear")) {
                    history.clear()
                    selection = nil
                }
                .disabled(history.items.isEmpty)
            }
            Text(String(localized: "Press Return to copy the selected item again. Kept in memory only, never saved to disk. Passwords that password managers mark as private are left out."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520, height: 480)
    }

    private func copySelected() {
        guard let item = history.items.first(where: { $0.id == selection }) else { return }
        history.copy(item)
        selection = history.items.first?.id
    }
}
