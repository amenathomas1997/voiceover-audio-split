// ScreenWatch.swift — "watch this window": for a window that VoiceOver can't read (an
// installer, a game, a remote desktop, a video call's shared screen), the app takes a
// picture of that one window every few seconds, recognizes its text on the Mac, and says
// the lines that are new. Like Screen OCR, it needs the Screen Recording permission, looks
// only at the window chosen, and keeps nothing: each picture is dropped once it's read.
// It stops with the same command, when the window goes away, or after fifteen minutes.

import AppKit

enum ScreenWatchLogic {
    /// A line as compared: without case, and with runs of spaces as one.
    static func normalize(_ line: String) -> String {
        line.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The lines in `now` that weren't there `before`, in reading order. A line that only
    /// moved (the text scrolled) isn't new.
    static func newLines(before: [String], now: [String]) -> [String] {
        var seen = [String: Int]()
        for line in before { seen[normalize(line), default: 0] += 1 }
        return now.filter { line in
            let key = normalize(line)
            guard !key.isEmpty else { return false }
            if let count = seen[key], count > 0 {
                seen[key] = count - 1
                return false
            }
            return true
        }
    }

    /// What to say for new lines: the first three, then how many more.
    static func announcement(_ lines: [String]) -> String {
        let spoken = lines.prefix(3).map { String($0.prefix(200)) }.joined(separator: ". ")
        let more = lines.count - 3
        return more > 0 ? spoken + ". " + String(localized: "And \(more) more lines.") : spoken
    }
}

@MainActor
final class ScreenWatch {
    static let shared = ScreenWatch()

    private(set) var isWatching = false
    private var task: Task<Void, Never>?
    /// Seconds between looks, and how long it watches before stopping by itself.
    static let seconds = 4.0
    static let limit = 15.0 * 60

    func toggle() {
        isWatching ? stop(saying: String(localized: "Stopped watching the window.")) : start()
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        Tones.play(.status)
        task = Task { [weak self] in await self?.run() }
    }

    func stop(saying text: String?) {
        guard isWatching else { return }
        isWatching = false
        task?.cancel()
        task = nil
        if let text { Announcer.say(text) }
    }

    private static func text(of image: CGImage) async -> [String] {
        await Task.detached { ScreenOCRLayout.recognize(image).map(\.text) }.value
    }

    private func run() async {
        do {
            let first = try await ScreenPicture.frontWindowCapture()
            guard let windowID = first.windowID else {
                return stop(saying: String(localized: "No window to read."))
            }
            var lines = await Self.text(of: first.image)
            guard !Task.isCancelled else { return }
            let name = first.processID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            Announcer.say(name.map { String(localized: "Watching the \($0) window. I'll say when its text changes. Use the same command to stop.") }
                ?? String(localized: "Watching the front window. I'll say when its text changes. Use the same command to stop."))
            log("Screen watch: started.")
            let began = Date()
            var missing = 0, streak = 0
            var lastSpoken = Date.distantPast
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(Self.seconds))
                guard !Task.isCancelled else { return }
                guard Date().timeIntervalSince(began) < Self.limit else {
                    return stop(saying: String(localized: "Stopped watching the window after 15 minutes. Use the command again to carry on."))
                }
                // A look that fails (the screen locked, the window on another desktop) is
                // skipped; three in a row and it stops.
                guard let capture = try? await ScreenPicture.windowCapture(windowID) else {
                    missing += 1
                    if missing >= 3 {
                        return stop(saying: String(localized: "The window has gone or can't be seen, so I stopped watching it."))
                    }
                    continue
                }
                missing = 0
                let now = await Self.text(of: capture.image)
                guard !Task.isCancelled else { return }
                let fresh = ScreenWatchLogic.newLines(before: lines, now: now)
                lines = now
                guard !fresh.isEmpty else {
                    streak = 0
                    continue
                }
                streak += 1
                // Text that changes at every look (a clock, a counter) is said now and then,
                // not every four seconds.
                if streak > 3, Date().timeIntervalSince(lastSpoken) < 20 { continue }
                lastSpoken = Date()
                Tones.play(.beep)
                Announcer.say(ScreenWatchLogic.announcement(fresh))
            }
        } catch let failure as ScreenPicture.Failure {
            stop(saying: failure.message)
        } catch is CancellationError {
            // Stopped by the user: already said.
        } catch {
            stop(saying: String(localized: "Couldn't capture the screen."))
        }
    }
}
