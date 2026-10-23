// SpeechTools.swift — features built on what VoiceOver says:
//   * speech history: everything VoiceOver said recently, to review and copy
//   * read item: speak the item under the VoiceOver cursor on request (useful
//     while VoiceOver is silenced, like JAWS speech on demand)
//   * say clipboard: read out what was copied
// VoiceOver's text comes from its AppleScript interface (the "last phrase" and
// the "vo cursor"), which needs "Allow VoiceOver to be controlled with AppleScript".

import AppKit
import Combine

struct SpokenPhrase: Identifiable, Hashable {
    let id = UUID()
    let time: Date
    let text: String
}

final class SpeechHistory: ObservableObject {
    static let shared = SpeechHistory()
    static let limit = 300

    /// Newest first. Kept in memory only, never saved to disk.
    @Published private(set) var phrases: [SpokenPhrase] = []

    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.history")
    private var timer: DispatchSourceTimer?
    private var lastText = ""

    /// Starts or stops listening, following the setting.
    func update(enabled: Bool) {
        if enabled && timer == nil {
            // VoiceOver has no "phrase spoken" notification, so ask a few times a second.
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(350))
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        } else if !enabled, let timer {
            timer.cancel()
            self.timer = nil
        }
    }

    private func poll() {
        guard NSWorkspace.shared.isVoiceOverEnabled,
              // Checked several times a second, so failures aren't logged.
              let text = VoiceOverText.run("return content of last phrase", logErrors: false),
              !text.isEmpty, text != lastText else { return }
        lastText = text
        let phrase = SpokenPhrase(time: Date(), text: text)
        DispatchQueue.main.async {
            self.phrases.insert(phrase, at: 0)
            if self.phrases.count > Self.limit { self.phrases.removeLast(self.phrases.count - Self.limit) }
        }
    }

    func clear() {
        phrases.removeAll()
    }
}

enum AppleScriptRunner {
    /// NSAppleScript isn't safe to use from several threads at once, and history,
    /// announcements, Read Item, the focus frame and website presets all use it,
    /// so every script goes through this one queue.
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.applescript")

    /// Runs a script and returns its text result, or nil on failure. Don't call from the main thread.
    @discardableResult
    static func run(_ source: String, logErrors: Bool = true) -> String? {
        queue.sync {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error, logErrors { log("AppleScript failed: \(error[NSAppleScript.errorMessage] ?? error)") }
            return error == nil ? (result?.stringValue ?? "") : nil
        }
    }
}

enum VoiceOverText {
    /// Runs one line of AppleScript inside `tell application "VoiceOver"` and
    /// returns the text result, or nil on failure. Don't call from the main thread.
    @discardableResult
    static func run(_ line: String, logErrors: Bool = true) -> String? {
        AppleScriptRunner.run("tell application id \"com.apple.VoiceOver\" to \(line)", logErrors: logErrors)
    }

    /// Escapes text for use inside an AppleScript string.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The text of the item under the VoiceOver cursor.
    static func itemUnderCursor() -> String? {
        run("return text under cursor of vo cursor")
    }
}

enum Clipboard {
    /// A spoken description of the clipboard: its text (shortened if long), or what kind of thing it holds.
    static func describe() -> String {
        let board = NSPasteboard.general
        if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let limit = 1000
            return text.count > limit ? String(text.prefix(limit)) + ". And more" : text
        }
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            let names = files.prefix(5).map(\.lastPathComponent)
            return "\(files.count) \(files.count == 1 ? "file" : "files"): " + ListFormatter.localizedString(byJoining: names)
        }
        if board.data(forType: .tiff) != nil || board.data(forType: .png) != nil { return "An image" }
        return "The clipboard is empty"
    }
}

/// Presets for websites: which browsers can be asked for their current address,
/// and how a site's host name matches a rule.
enum SitePresets {
    /// Bundle ID to the AppleScript that returns the front tab's address.
    static let browsers: [String: String] = [
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to return URL of front document",
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to return URL of active tab of front window",
    ]

    /// A rule for "youtube.com" also matches "www.youtube.com" and "m.youtube.com".
    static func match(host: String, in rules: [String: String]) -> String? {
        let host = host.lowercased()
        return rules.first { site, _ in host == site || host.hasSuffix("." + site) }?.value
    }

    /// "https://www.YouTube.com/watch" or "www.youtube.com" becomes "youtube.com".
    static func normalize(_ entry: String) -> String {
        var text = entry.trimmingCharacters(in: .whitespaces).lowercased()
        if let host = URL(string: text.contains("://") ? text : "https://\(text)")?.host() { text = host }
        return text.hasPrefix("www.") ? String(text.dropFirst(4)) : text
    }
}
