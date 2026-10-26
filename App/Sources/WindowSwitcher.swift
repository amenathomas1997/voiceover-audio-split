// WindowSwitcher.swift — every open window of every app in one list ("Mail:
// Inbox"), filtered as you type; Return brings that window to the front. Uses
// the accessibility interface (Accessibility permission, like the shortcuts),
// asked off the main thread with short timeouts, so a frozen app can't hang it.
// Window titles are only shown here, never logged or saved.

import AppKit
import ApplicationServices
import SwiftUI

/// One window of one app.
struct WindowEntry: Identifiable {
    let id: String
    let pid: pid_t
    let appName: String
    let title: String
    let minimized: Bool
    let element: AXUIElement?

    /// "Mail: Inbox", as listed and searched.
    var label: String {
        let name = title.isEmpty ? String(localized: "Untitled window") : title
        return minimized ? String(localized: "\(appName): \(name), minimized") : "\(appName): \(name)"
    }
}

enum WindowSwitcher {
    /// Entries containing every typed word, ignoring case and accents, in the order given.
    static func filter(_ entries: [WindowEntry], query: String) -> [WindowEntry] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let text = fold(entry.label)
            return words.allSatisfy(text.contains)
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Apps front to back, by where their windows are on screen (no screen
    /// recording permission is needed for this; titles come from accessibility).
    static func appOrder() -> [pid_t] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var order: [pid_t] = []
        for window in info {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  (window[kCGWindowLayer as String] as? Int) == 0, !order.contains(pid) else { continue }
            order.append(pid)
        }
        return order
    }

    /// Every window of every regular app, front app first. Slow apps are asked at the same
    /// time and each answers within the accessibility timeout. Call off the main thread.
    static func windows() -> [WindowEntry] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
        }
        let order = appOrder()
        let sorted = apps.sorted { a, b in
            (order.firstIndex(of: a.processIdentifier) ?? Int.max) < (order.firstIndex(of: b.processIdentifier) ?? Int.max)
        }
        var results = [[WindowEntry]](repeating: [], count: sorted.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: sorted.count) { index in
            let app = sorted[index]
            let found = windows(of: app)
            lock.lock()
            results[index] = found
            lock.unlock()
        }
        return results.flatMap { $0 }
    }

    private static func windows(of app: NSRunningApplication) -> [WindowEntry] {
        let pid = app.processIdentifier
        let element = AX.application(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        let name = app.localizedName ?? app.bundleIdentifier ?? String(localized: "App")
        return windows.enumerated().compactMap { index, window in
            AXUIElementSetMessagingTimeout(window, AX.timeout)
            let role = AX.string(window, kAXRoleAttribute)
            guard role.isEmpty || role == kAXWindowRole as String else { return nil }
            let subrole = AX.string(window, kAXSubroleAttribute)
            // Floating palettes, popovers and tooltips aren't windows to switch to.
            guard subrole.isEmpty || [kAXStandardWindowSubrole as String, kAXDialogSubrole as String].contains(subrole)
            else { return nil }
            let title = AX.string(window, kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
            let minimized = AX.string(window, kAXMinimizedAttribute) == "1"
            return WindowEntry(id: "\(pid)-\(index)-\(title)", pid: pid, appName: name, title: title,
                               minimized: minimized, element: window)
        }
    }

    /// Brings the window to the front: un-minimizes it, raises it and activates its app.
    /// Returns false if the window is gone. Call off the main thread.
    static func raise(_ entry: WindowEntry) -> Bool {
        guard let window = entry.element, NSRunningApplication(processIdentifier: entry.pid) != nil else { return false }
        if entry.minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard raised == .success || raised == .cannotComplete else { return false }
        DispatchQueue.main.sync {
            guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        // Activating can bring another of the app's windows forward; raise this one again.
        Thread.sleep(forTimeInterval: 0.15)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }
}

// MARK: - Model and window

final class WindowSwitcherModel: ObservableObject {
    static let shared = WindowSwitcherModel()

    @Published private(set) var entries: [WindowEntry] = []
    @Published private(set) var loading = false
    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.windowSwitcher", qos: .userInitiated)
    private var generation = 0

    /// Lists the windows again, in the background.
    func reload() {
        guard AXIsProcessTrusted() else {
            entries = []
            return
        }
        generation += 1
        let current = generation
        loading = true
        queue.async { [weak self] in
            let found = WindowSwitcher.windows()
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.entries = found
                self.loading = false
            }
        }
    }

    /// Raises the window after `close` (which hides this app's window), saying so only if it fails.
    func switchTo(_ entry: WindowEntry, close: @escaping () -> Void) {
        close()
        queue.async {
            if !WindowSwitcher.raise(entry) {
                DispatchQueue.main.async {
                    Announcer.say(String(localized: "That window couldn't be brought forward. It may have closed."))
                }
            }
        }
    }
}

/// A search field and the list of windows. `close` closes this window and gives the keyboard back.
struct WindowSwitcherView: View {
    var close: () -> Void
    @ObservedObject var model = WindowSwitcherModel.shared
    @State private var query = ""
    @State private var selection: WindowEntry.ID?
    @FocusState private var searchFocused: Bool

    private var results: [WindowEntry] { WindowSwitcher.filter(model.entries, query: query) }

    private var summary: String {
        if !AXIsProcessTrusted() {
            return String(localized: "The window switcher needs Accessibility permission. Turn it on in System Settings, Privacy and Security, Accessibility.")
        }
        if model.loading && model.entries.isEmpty { return String(localized: "Looking for windows…") }
        if results.isEmpty { return String(localized: "No matching windows") }
        return results.count == 1 ? String(localized: "1 window. Press Return to switch to it.")
                                  : String(localized: "\(results.count) windows. Press Return to switch to the first, or choose one below.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Type part of an app or window name"), text: $query)
                .focused($searchFocused)
                .onSubmit { switchTo(results.first { $0.id == selection } ?? results.first) }
            Text(summary).font(.caption)
            List(results, selection: $selection) { entry in
                Text(entry.label).tag(entry.id)
            }
            .accessibilityLabel(String(localized: "Open windows, front app first"))
            .onKeyPress(.return) {
                switchTo(results.first { $0.id == selection })
                return .handled
            }
            HStack {
                Button(String(localized: "Switch to selected")) { switchTo(results.first { $0.id == selection }) }
                    .disabled(selection == nil)
                Spacer()
                Button(String(localized: "Refresh")) { model.reload() }
            }
        }
        .padding()
        .frame(width: 560, height: 460)
        .onAppear {
            query = ""
            selection = nil
            searchFocused = true
            model.reload()
        }
    }

    private func switchTo(_ entry: WindowEntry?) {
        guard let entry else { return }
        model.switchTo(entry, close: close)
    }
}
