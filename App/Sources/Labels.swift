// Labels.swift — two features JAWS and NVDA users rely on:
//   * Custom labels: name a control that has no name (an "unlabeled button"), and
//     the name is spoken whenever the VoiceOver cursor lands on it
//   * Place markers: mark a spot on a web page (or in an app), and jump back to
//     it later with one key
// Both are saved in the settings, so they survive restarts and settings export.

import AppKit
import SwiftUI

struct CustomLabel: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var appName: String
    var element: ElementSignature
}

struct PlaceMarker: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// A web address without the query ("youtube.com/watch"), or "app:" and a bundle ID.
    var page: String
    var element: ElementSignature
}

// MARK: - Custom labels

enum CustomLabels {
    private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.labels")
    nonisolated(unsafe) private static var lastBounds: CGRect?
    nonisolated(unsafe) private static var labels: [CustomLabel] = []

    /// Watches the VoiceOver cursor while any label exists.
    static func update(_ current: [CustomLabel]) {
        queue.async { labels = current }
        if !current.isEmpty && timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(300))
            timer.setEventHandler { check() }
            timer.resume()
            self.timer = timer
        } else if current.isEmpty, let running = timer {
            running.cancel()
            timer = nil
        }
    }

    private static func check() {
        guard NSWorkspace.shared.isVoiceOverEnabled,
              let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              labels.contains(where: { $0.element.bundleID == front }),
              let bounds = VoiceOverText.cursorBounds(), bounds != lastBounds else { return }
        lastBounds = bounds
        guard let element = AX.underVoiceOverCursor(), let signature = ElementSignature(element),
              let match = labels.first(where: { $0.element.matches(signature) }) else { return }
        // Let VoiceOver start describing the control first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Announcer.say(match.label) }
    }

    /// The control under the VoiceOver cursor, for labelling. Nil when there is none.
    static func capture() -> (signature: ElementSignature, spoken: String)? {
        guard Hotkeys.isTrusted, let element = AX.underVoiceOverCursor(), let signature = ElementSignature(element),
              signature.bundleID != Bundle.main.bundleIdentifier else { return nil }
        return (signature, VoiceOverText.itemUnderCursor() ?? signature.role)
    }
}

/// The label window's state: the control waiting for a label.
final class LabelEditor: ObservableObject {
    static let shared = LabelEditor()
    @Published var pending: ElementSignature?
    @Published var spoken = ""
    @Published var text = ""
}

struct LabelEditorView: View {
    @ObservedObject var editor = LabelEditor.shared
    @ObservedObject var preferences = Preferences.shared
    var close: () -> Void

    var body: some View {
        Form {
            if let pending = editor.pending {
                Section(String(localized: "Label this item")) {
                    Text(String(localized: "VoiceOver says: \(editor.spoken)"))
                    TextField(String(localized: "Label"), text: $editor.text)
                        .onSubmit { save(pending) }
                    Button(String(localized: "Save label")) { save(pending) }
                        .disabled(editor.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section(String(localized: "Your labels")) {
                if preferences.customLabels.isEmpty {
                    Text(String(localized: "No labels yet. Put the VoiceOver cursor on an unlabeled control and choose Label Item in the menu."))
                }
                ForEach(preferences.customLabels) { label in
                    HStack {
                        Text(String(localized: "\(label.label), in \(label.appName)"))
                        Spacer()
                        Button(String(localized: "Delete \(label.label)")) {
                            preferences.customLabels.removeAll { $0.id == label.id }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
    }

    private func save(_ signature: ElementSignature) {
        let text = editor.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let appName = NSRunningApplication.runningApplications(withBundleIdentifier: signature.bundleID).first?.localizedName
            ?? signature.bundleID
        preferences.customLabels.removeAll { $0.element.matches(signature) }
        preferences.customLabels.append(CustomLabel(label: text, appName: appName, element: signature))
        editor.pending = nil
        editor.text = ""
        Announcer.say(String(localized: "Saved label \(text)"))
        close()
    }
}

// MARK: - Place markers

enum PlaceMarkers {
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.place-markers")
    nonisolated(unsafe) private static var nextIndex: [String: Int] = [:]

    /// The current page: the front browser tab's address, or the front app.
    static func currentPage() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        if let script = SitePresets.browsers[bundleID], let address = AppleScriptRunner.run(script, logErrors: false) {
            return page(for: address)
        }
        return "app:" + bundleID
    }

    /// "https://www.example.com/news/today?id=4#top" becomes "example.com/news/today".
    static func page(for address: String) -> String {
        guard let url = URL(string: address), let host = url.host() else { return address }
        let site = SitePresets.normalize(host)
        let path = url.path()
        return path.isEmpty || path == "/" ? site : site + path
    }

    static func add() {
        queue.async {
            guard Hotkeys.isTrusted else { return say(String(localized: "Allow keyboard shortcuts in Settings first; place markers use the same permission.")) }
            guard let page = currentPage(), let element = AX.underVoiceOverCursor(), let signature = ElementSignature(element) else {
                return say(String(localized: "No item under the VoiceOver cursor"))
            }
            let spoken = (VoiceOverText.itemUnderCursor() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String((spoken.isEmpty ? signature.text : spoken).prefix(80))
            DispatchQueue.main.async {
                let markers = Preferences.shared.placeMarkers
                Preferences.shared.placeMarkers = markers + [PlaceMarker(name: name, page: page, element: signature)]
                let count = markers.filter { $0.page == page }.count + 1
                Announcer.say(String(localized: "Place marker \(count) added: \(name)"))
            }
        }
    }

    /// Moves the VoiceOver cursor to the next place marker on this page.
    static func next() {
        let markers = Preferences.shared.placeMarkers
        queue.async {
            guard let page = currentPage() else { return }
            let here = markers.filter { $0.page == page }
            guard !here.isEmpty else { return say(String(localized: "No place markers on this page. Add one with Add a Place Marker.")) }
            let index = (nextIndex[page] ?? 0) % here.count
            nextIndex[page] = index + 1
            let marker = here[index]
            guard let window = AX.frontWindow(),
                  let element = find(marker.element, in: window), AX.moveVoiceOverCursor(to: element) else {
                return say(String(localized: "Couldn't find place marker \(marker.name) on this page"))
            }
            say(String(localized: "Place marker \(index + 1) of \(here.count)"))
        }
    }

    /// The element matching a signature: same identifier or text first, then the same place.
    static func find(_ signature: ElementSignature, in window: AXUIElement) -> AXUIElement? {
        let candidates = AX.descendants(of: window).filter { AX.string($0, kAXRoleAttribute) == signature.role }
        return candidates.first { ElementSignature($0)?.matches(signature) == true }
            ?? candidates.first { !signature.text.isEmpty && AX.text($0).localizedCaseInsensitiveContains(signature.text) }
    }

    private static func say(_ text: String) {
        DispatchQueue.main.async { Announcer.say(text) }
    }
}

struct PlaceMarkersSection: View {
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        Section(String(localized: "Custom labels and place markers")) {
            Text(String(localized: "Label an unlabeled control, and its label is spoken whenever VoiceOver lands on it. Place markers save a spot on a web page to jump back to. Both are in the menu and the command palette, and can be given keys."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "\(preferences.customLabels.count) labels, \(preferences.placeMarkers.count) place markers"))
            ForEach(preferences.placeMarkers) { marker in
                HStack {
                    Text(String(localized: "\(marker.name), on \(marker.page)"))
                    Spacer()
                    Button(String(localized: "Delete place marker \(marker.name)")) {
                        preferences.placeMarkers.removeAll { $0.id == marker.id }
                    }
                }
            }
            Button(String(localized: "Manage labels…")) { Controller.shared.run(.customLabel) }
        }
    }
}
