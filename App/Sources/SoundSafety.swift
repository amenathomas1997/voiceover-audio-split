// SoundSafety.swift — "Keep this sound setting?" Like changing the screen resolution:
// after a change that could leave you unable to hear (the output device, one-ear mode,
// ear balance, the volume limit, the hearing profile, the layout, call audio, ducking,
// the speech device, or a preset chosen by hand), a small window asks whether to keep
// it. Return keeps it; Escape, or doing nothing for 60 seconds, puts everything back the
// way it was. Going back doesn't depend on hearing anything, so a change that took your
// sound away undoes itself. Everyday keys (speech louder, speech left) and presets that
// switch automatically with the app in front don't ask.

import AppKit
import SwiftUI

final class SoundSafety: ObservableObject {
    static let shared = SoundSafety()
    /// How long to wait before going back (shorter only in the debug self-check).
    nonisolated(unsafe) static var seconds = 60

    /// What changed, while waiting for an answer.
    @Published private(set) var changes: [String] = []
    @Published private(set) var secondsLeft = 0
    var isWaiting: Bool { !restores.isEmpty }

    /// How to put back each setting that changed, by key; only the first change of each
    /// counts, so going back returns to how things were before any of them.
    private var restores: [(key: String, restore: () -> Void)] = []
    private var quiet = 0
    private var reverting = false
    private var settle: DispatchWorkItem?
    private var timer: Timer?
    private var panel: NSPanel?
    private var closeObserver: NSObjectProtocol?
    /// Unit tests change settings all the time; the check only runs in them when a test asks.
    var runsInTests = false
    private let inTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Notes a change about to be kept or undone. `restore` puts back the value from before.
    func note(_ key: String, _ name: String, restore: @escaping () -> Void) {
        guard Thread.isMainThread, quiet == 0, !reverting, Preferences.shared.confirmSoundChanges,
              !inTests || runsInTests else { return }
        if !restores.contains(where: { $0.key == key }) { restores.append((key, restore)) }
        if !changes.contains(name) { changes.append(name) }
        // Wait until the changes stop (a preset changes several settings, a stepper several
        // steps), then ask once.
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.ask() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        if panel != nil { secondsLeft = Self.seconds } // Another change: the full minute again.
    }

    /// Runs changes that shouldn't ask, such as automatic presets and settings import.
    func withoutAsking(_ body: () -> Void) {
        quiet += 1
        defer { quiet -= 1 }
        body()
    }

    func keep() {
        guard !changes.isEmpty else { return }
        finish()
        Tones.play(.preset)
        Announcer.say(String(localized: "Sound setting kept."))
    }

    func undo() {
        guard !restores.isEmpty else { return }
        reverting = true
        // Newest first, so a setting changed twice ends up as it was at the start.
        for item in restores.reversed() { item.restore() }
        reverting = false
        finish()
        Tones.play(.device)
        Announcer.say(String(localized: "Sound setting undone. Everything is back as it was."))
        log("Sound safety: changes undone.")
    }

    /// Forgets a waiting change without keeping or undoing it (for tests).
    func discard() { finish() }

    private func finish() {
        settle?.cancel()
        timer?.invalidate()
        timer = nil
        restores = []
        changes = []
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        let panel = panel
        self.panel = nil
        panel?.close()
    }

    private func ask() {
        guard !changes.isEmpty else { return }
        secondsLeft = Self.seconds
        if panel == nil { show() }
        let list = ListFormatter.localizedString(byJoining: changes)
        Tones.play(.status)
        Announcer.say(String(localized: "You changed \(list). Keep this sound setting? Press Return to keep it, or Escape to go back. If you do nothing, it goes back in \(Self.seconds) seconds."))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        secondsLeft -= 1
        if secondsLeft == 15 { Announcer.say(String(localized: "Going back in 15 seconds, unless you press Return to keep it.")) }
        if secondsLeft <= 0 { undo() }
    }

    private func show() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = String(localized: "Keep This Sound Setting?")
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SoundSafetyView())
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        // Closing the window counts as going back, the safe choice. (finish() closes it
        // itself after removing this observer, so keep and undo don't come back here.)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.panel === panel else { return }
            self.undo()
        }
    }
}

private struct SoundSafetyView: View {
    @ObservedObject var safety = SoundSafety.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "You changed \(ListFormatter.localizedString(byJoining: safety.changes))."))
                .font(.headline)
            Text(String(localized: "Keep this sound setting? If you do nothing, it goes back in \(safety.secondsLeft) seconds."))
                .accessibilityLabel(String(localized: "Keep this sound setting? If you do nothing, it goes back in \(SoundSafety.seconds) seconds."))
            HStack {
                Spacer()
                Button(String(localized: "Go Back")) { safety.undo() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Keep")) { safety.keep() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
