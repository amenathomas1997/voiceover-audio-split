// ScreenOCR.swift — Screen OCR, like NVDA's screen OCR and JAWS's Convenient OCR:
// takes a picture of the front window (or the whole screen), recognizes the text
// in it on the Mac, and lets the user move through the lines and words with the
// arrow keys and click any of them. For apps built without accessibility, shared
// screens in meetings, remote desktops, games and text in videos. Nothing leaves
// the Mac.

import AppKit
import SwiftUI
import Vision

// MARK: - Layout (pure, tested)

enum ScreenOCRLayout {
    /// A word with its box, normalised to the picture (0 to 1, origin bottom left, as Vision gives it).
    struct Word: Equatable {
        let text: String
        let box: CGRect
    }

    /// One recognized line of text and the words in it.
    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
        let box: CGRect
        let words: [Word]

        init(id: Int, text: String, box: CGRect, words: [Word]? = nil) {
            self.id = id
            self.text = text
            self.box = box
            self.words = words ?? ScreenOCRLayout.words(of: text, in: box)
        }
    }

    /// Lines in reading order: rows from top to bottom, and within a row (lines whose
    /// heights overlap, such as columns or a label and its value) from left to right.
    static func ordered(_ lines: [Line]) -> [Line] {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.indices.last, sameRow(rows[last], line) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }.enumerated().map { index, line in
            Line(id: index, text: line.text, box: line.box, words: line.words)
        }
    }

    /// A line belongs to a row when its middle is within the row's lines' height.
    private static func sameRow(_ row: [Line], _ line: Line) -> Bool {
        row.contains { other in
            let overlap = min(other.box.maxY, line.box.maxY) - max(other.box.minY, line.box.minY)
            return overlap > 0.5 * min(other.box.height, line.box.height)
        }
    }

    /// The words of a line, each given a share of the line's box by its length,
    /// for when recognition gives no box of its own for a word.
    static func words(of text: String, in box: CGRect) -> [Word] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return [] }
        let total = CGFloat(parts.reduce(0) { $0 + $1.count } + parts.count - 1)
        var x = box.minX
        return parts.map { part in
            let width = total > 0 ? box.width * CGFloat(part.count) / total : box.width / CGFloat(parts.count)
            let word = Word(text: part, box: CGRect(x: x, y: box.minY, width: width, height: box.height))
            x += width + (total > 0 ? box.width / total : 0)
            return word
        }
    }

    /// Where a normalised box is on screen, in points with the origin at the top left of the
    /// main screen (what mouse events use), given the frame of the picture in that space.
    static func screenRect(_ box: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + box.minX * frame.width,
               y: frame.minY + (1 - box.maxY) * frame.height,
               width: box.width * frame.width,
               height: box.height * frame.height)
    }

    /// The middle of a box on screen: where to click.
    static func screenCenter(_ box: CGRect, in frame: CGRect) -> CGPoint {
        let rect = screenRect(box, in: frame)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    // MARK: Checking a click

    /// A window on screen now: enough to tell whether a click would still land on the text.
    struct OnScreenWindow: Equatable {
        let id: CGWindowID
        let frame: CGRect
        /// 0 for ordinary windows; panels, menus and overlays are above that.
        let layer: Int
        let processID: pid_t
    }

    enum ClickCheck: Equatable {
        /// Safe to click, here (the window may have moved since the picture).
        case click(CGPoint)
        case gone, resized, covered
    }

    /// Whether the text pictured at `point` is still there to click. The picture is of one
    /// moment: since then the window may have closed, moved or changed size, or a dialog or
    /// another window may have come in front, and a click posted blind would press whatever
    /// is there now. `windows` is what's on screen, front to back. A whole-screen picture
    /// has no window to compare, so it is clicked as pictured.
    static func check(click point: CGPoint, picturedFrame: CGRect, windowID: CGWindowID?,
                      windows: [OnScreenWindow], me: pid_t) -> ClickCheck {
        guard let windowID else { return .click(point) }
        guard let window = windows.first(where: { $0.id == windowID }) else { return .gone }
        guard abs(window.frame.width - picturedFrame.width) < 2, abs(window.frame.height - picturedFrame.height) < 2 else { return .resized }
        // Moved but the same size: the text moved with it.
        let now = CGPoint(x: point.x + window.frame.minX - picturedFrame.minX, y: point.y + window.frame.minY - picturedFrame.minY)
        for other in windows {
            if other.id == windowID { break }
            // Ordinary windows, floating panels and dialogs take clicks. Menu bar items, the
            // Dock and see-through overlays (this app's own captions and focus frame among
            // them) are higher layers and don't count.
            let takesClicks = (0...8).contains(other.layer) && !(other.processID == me && other.layer != 0)
            if takesClicks, other.frame.contains(now) { return .covered }
        }
        return .click(now)
    }

    /// The windows on screen now, front to back, in the space mouse events use.
    static func windowsOnScreen() -> [OnScreenWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return OnScreenWindow(id: id, frame: frame, layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                  processID: info[kCGWindowOwnerPID as String] as? pid_t ?? 0)
        }
    }
}

// MARK: - Recognition

extension ScreenOCRLayout {
    /// Recognized lines in reading order, with a box for each word where Vision can give one.
    static func recognize(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).enumerated().compactMap { index, observation -> Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var words: [Word] = []
            var search = candidate.string.startIndex
            for part in candidate.string.split(whereSeparator: \.isWhitespace) {
                guard let range = candidate.string.range(of: part, range: search..<candidate.string.endIndex) else { continue }
                search = range.upperBound
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? .null
                words.append(Word(text: String(part), box: box))
            }
            // Fall back to shares of the line when any word has no box of its own.
            let usable = words.allSatisfy { !$0.box.isNull && $0.box.width > 0 } ? words : nil
            return Line(id: index, text: text, box: observation.boundingBox, words: usable)
        }
        return ordered(lines)
    }
}

// MARK: - The session

/// The last picture's lines, the place in them, and the keys while navigating.
@MainActor
final class ScreenOCR: ObservableObject {
    static let shared = ScreenOCR()

    @Published private(set) var lines: [ScreenOCRLayout.Line] = []
    @Published private(set) var current = 0
    @Published private(set) var busy = false
    @Published private(set) var status = String(localized: "Press Capture to read the front window.")
    @Published private(set) var navigating = false
    @Published private(set) var wholeScreen = false

    private var frame = CGRect.zero
    private var target: pid_t?
    /// The window pictured (nil for a whole screen), checked again before every click.
    private var windowID: CGWindowID?
    private var word: Int?
    private var generation = 0
    private var appWatcher: Any?
    private var keysWatcher: Any?
    private var sleepWatchers: [Any] = []
    private var idle: DispatchWorkItem?
    /// With no key for this long, the arrow keys go back to the app. Left on, they were
    /// still taken in that app the next morning.
    static let idleSeconds: TimeInterval = 120
    private var captureTask: Task<Void, Never>?
    /// Which capture is the current one, so a late or abandoned one changes nothing.
    private var captureToken = 0
    private var captureStarted = Date.distantPast

    var text: String { lines.map(\.text).joined(separator: "\n") }

    /// Takes the picture, recognizes the text, and (from a key or the menu) starts the arrow keys.
    func capture(wholeScreen: Bool = false, thenNavigate: Bool) {
        // A capture that hasn't come back after fifteen seconds is given up on, so a
        // picture that never arrives can't block every later one.
        if busy, Date().timeIntervalSince(captureStarted) < 15 { return Announcer.say(String(localized: "Still recognizing")) }
        stopNavigation(say: nil)
        captureTask?.cancel()
        captureToken += 1
        let token = captureToken
        captureStarted = Date()
        busy = true
        self.wholeScreen = wholeScreen
        status = String(localized: "Recognizing…")
        Tones.play(.status)
        Announcer.say(wholeScreen ? String(localized: "Screen OCR of the whole screen") : String(localized: "Screen OCR"))
        captureTask = Task { [weak self] in
            do {
                let capture = try wholeScreen ? await ScreenPicture.screenCapture() : await ScreenPicture.frontWindowCapture()
                let lines = await Task.detached { ScreenOCRLayout.recognize(capture.image) }.value
                guard !Task.isCancelled, let self, captureToken == token else { return }
                self.lines = lines
                frame = capture.frame
                target = capture.processID
                windowID = capture.windowID
                current = 0
                word = nil
                busy = false
                if lines.isEmpty {
                    status = String(localized: "No text found.")
                    Announcer.say(status)
                    return
                }
                status = String(localized: "\(lines.count) lines.")
                if thenNavigate {
                    startNavigation()
                } else {
                    Announcer.say(status)
                }
            } catch let failure as ScreenPicture.Failure {
                guard let self, captureToken == token else { return }
                busy = false
                status = failure.message
                Announcer.say(failure.message)
            } catch {
                guard let self, captureToken == token else { return }
                busy = false
                status = String(localized: "Couldn't capture the screen.")
                Announcer.say(status)
            }
        }
    }

    /// Stops a capture in progress (the window closed) and the keys.
    func stop() {
        captureTask?.cancel()
        captureTask = nil
        captureToken += 1
        busy = false
        stopNavigation(say: nil)
    }

    // MARK: Keys

    /// Takes the arrow keys, Return, Home, End, C and Escape until Escape, another plain key,
    /// or another app coming to the front. Keys with modifiers (VoiceOver's own, Command
    /// shortcuts) pass through untouched. Not while a lesson is watching the keys.
    func startNavigation() {
        guard !lines.isEmpty else { return Announcer.say(String(localized: "Capture the screen first.")) }
        // The keys come through the same listener as the shortcuts: without it, the arrow
        // keys would be announced and then do nothing.
        guard Hotkeys.isTrusted else {
            return Announcer.say(String(localized: "Allow keyboard shortcuts in Settings first; this uses the same permission."))
        }
        // A lesson, practice or the typing trainer keeps the keys; a few seconds' wait for a
        // digit (the resource monitor) gives way.
        if Hotkeys.keyObserver != nil, !navigating, !Hotkeys.keyObserverIsBrief {
            return Announcer.say(String(localized: "The keys are busy with a lesson. Use the Screen OCR window instead."))
        }
        navigating = true
        current = min(current, lines.count - 1)
        word = nil
        let observer: (Int64, CGEventFlags, NSEvent?) -> Bool = { [weak self] keyCode, flags, event in
            // The event tap runs on the main run loop, so this is on main.
            guard let self else { return false }
            return MainActor.assumeIsolated { self.handle(keyCode, flags, event) }
        }
        Hotkeys.keyObserver = observer
        generation = Hotkeys.keyObserverGeneration
        restartIdleTimer()
        // Sleeping, locking the screen or switching user ends it too.
        let workspace = NSWorkspace.shared.notificationCenter
        sleepWatchers = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopNavigation(say: nil) }
            }
        }
        // If a lesson, practice or the typing trainer takes the keys, this is over.
        keysWatcher = NotificationCenter.default.addObserver(forName: Hotkeys.observerChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.navigating, Hotkeys.keyObserverGeneration != self.generation else { return }
                self.stopNavigation(say: nil)
            }
        }
        appWatcher = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, pid != self.target, pid != ProcessInfo.processInfo.processIdentifier {
                    self.stopNavigation(say: String(localized: "Screen OCR off"))
                }
            }
        }
        Announcer.say(String(localized: "Screen OCR: \(lines.count) lines. Up and Down Arrow move by line, Left and Right by word, Return clicks, Escape leaves. \(lines[current].text)"))
    }

    func stopNavigation(say message: String?) {
        guard navigating else { return }
        navigating = false
        // Only this observer is cleared, never a lesson that took over meanwhile.
        if Hotkeys.keyObserverGeneration == generation { Hotkeys.keyObserver = nil }
        if let appWatcher { NSWorkspace.shared.notificationCenter.removeObserver(appWatcher) }
        appWatcher = nil
        if let keysWatcher { NotificationCenter.default.removeObserver(keysWatcher) }
        keysWatcher = nil
        sleepWatchers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        sleepWatchers = []
        idle?.cancel()
        idle = nil
        if let message { Announcer.say(message) }
    }

    private func restartIdleTimer() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.stopNavigation(say: String(localized: "Screen OCR off")) }
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleSeconds, execute: work)
    }

    private enum Keys {
        static let up: Int64 = 126, down: Int64 = 125, left: Int64 = 123, right: Int64 = 124
        static let home: Int64 = 115, end: Int64 = 119, pageUp: Int64 = 116, pageDown: Int64 = 121
        static let `return`: Int64 = 36, enter: Int64 = 76, escape: Int64 = 53, c: Int64 = 8, space: Int64 = 49
    }

    /// What a key does while the keys belong to Screen OCR.
    enum KeyAction: Equatable {
        case line(Int), word(Int), first, last, click(right: Bool), copy, leave
        /// For VoiceOver or the app, and the mode stays on.
        case pass
        /// Any other key is for the app: the mode ends and the key goes through.
        case leaveAndPass
    }

    /// Decided from the key alone, so it can be tested with the flags real keys carry.
    /// macOS marks every arrow, Home, End and Page key with the Fn flag (and the keypad
    /// flag): counted as a modifier, as it first was here, those keys were never taken and
    /// moving by line and word didn't work at all. Caps Lock switched on marks every key
    /// too; only Caps Lock held down is VoiceOver's key.
    nonisolated static func action(keyCode: Int64, flags: CGEventFlags, letter: Character?, capsLockHeld: Bool) -> KeyAction {
        // VoiceOver's own keys (Control Option, or Caps Lock held) and Command shortcuts.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty || capsLockHeld { return .pass }
        switch keyCode {
        case Keys.up: return .line(-1)
        case Keys.down: return .line(1)
        case Keys.left: return .word(-1)
        case Keys.right: return .word(1)
        case Keys.home, Keys.pageUp: return .first
        case Keys.end, Keys.pageDown: return .last
        case Keys.return, Keys.enter, Keys.space: return .click(right: flags.contains(.maskShift))
        case Keys.escape: return .leave
        default:
            // C by the letter typed: it's on another key on Dvorak and other layouts.
            if letter == "c" || (letter == nil && keyCode == Keys.c) { return .copy }
            return .leaveAndPass
        }
    }

    /// Returns true when the key was taken.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags, _ event: NSEvent?) -> Bool {
        guard navigating else { return false }
        restartIdleTimer()
        switch Self.action(keyCode: keyCode, flags: flags, letter: KeyCombo.letter(typedBy: event), capsLockHeld: KeyCombo.capsLockHeld) {
        case .pass: return false
        case .leaveAndPass:
            stopNavigation(say: String(localized: "Screen OCR off"))
            return false
        case .line(let step): moveLine(by: step)
        case .word(let step): moveWord(by: step)
        case .first: go(to: 0)
        case .last: go(to: lines.count - 1)
        case .click(let right): click(right: right)
        case .copy: copyAll()
        case .leave: stopNavigation(say: String(localized: "Screen OCR off"))
        }
        return true
    }

    // MARK: Moving

    func go(to index: Int) {
        guard lines.indices.contains(index) else { return }
        current = index
        word = nil
        Announcer.say(lines[index].text)
    }

    func moveLine(by step: Int) {
        let next = current + step
        guard lines.indices.contains(next) else {
            Tones.play(.status)
            return Announcer.say(step < 0 ? String(localized: "First line. \(lines[current].text)") : String(localized: "Last line. \(lines[current].text)"))
        }
        go(to: next)
    }

    func moveWord(by step: Int) {
        let words = lines[current].words
        guard !words.isEmpty else { return Announcer.say(lines[current].text) }
        let next = (word ?? (step < 0 ? words.count : -1)) + step
        guard words.indices.contains(next) else {
            Tones.play(.status)
            return Announcer.say(step < 0 ? String(localized: "Start of line") : String(localized: "End of line"))
        }
        word = next
        Announcer.say(words[next].text)
    }

    func select(_ line: ScreenOCRLayout.Line) {
        guard let index = lines.firstIndex(of: line) else { return }
        current = index
        word = nil
    }

    // MARK: Clicking

    /// Clicks the middle of the current word, or line, bringing its app forward first.
    func click(right: Bool = false) {
        guard lines.indices.contains(current) else { return }
        click(line: lines[current], word: word, right: right)
    }

    func click(line: ScreenOCRLayout.Line, word index: Int? = nil, right: Bool = false) {
        let box = index.flatMap { line.words.indices.contains($0) ? line.words[$0].box : nil } ?? line.box
        let pictured = ScreenOCRLayout.screenCenter(box, in: frame)
        let label = index.flatMap { line.words.indices.contains($0) ? line.words[$0].text : nil } ?? line.text
        // Without the permission the click is dropped silently, and "Clicked" would be a lie.
        guard CGPreflightPostEventAccess() else {
            return Announcer.say(String(localized: "Allow keyboard shortcuts in Settings first; this uses the same permission."))
        }
        // The picture is of one moment, and a click changes the screen: the keys go back to
        // the app, so what's typed next isn't taken for C or a second click.
        stopNavigation(say: nil)
        let app = target.flatMap { NSRunningApplication(processIdentifier: $0) }
        if target != nil, app?.isTerminated != false {
            return Announcer.say(String(localized: "That window has closed. Capture again."))
        }
        if let app, !app.isActive { app.activate() }
        let frame = frame, windowID = windowID
        Task { @MainActor in
            // Until the app has come forward (at most a second), so the click lands in it
            // and not in this app's own window.
            for _ in 0..<20 where app?.isActive == false { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(120))
            switch ScreenOCRLayout.check(click: pictured, picturedFrame: frame, windowID: windowID,
                                         windows: ScreenOCRLayout.windowsOnScreen(), me: ProcessInfo.processInfo.processIdentifier) {
            case .gone: Announcer.say(String(localized: "That window has closed. Capture again."))
            case .resized: Announcer.say(String(localized: "That window changed size. Capture again."))
            case .covered: Announcer.say(String(localized: "Something is in front of that text. Capture again."))
            case .click(let point):
                await Self.post(click: point, right: right)
                Announcer.say(right ? String(localized: "Right clicked \(label)") : String(localized: "Clicked \(label)"))
            }
        }
    }

    private static func post(click point: CGPoint, right: Bool) async {
        let button: CGMouseButton = right ? .right : .left
        let source = CGEventSource(stateID: .hidSystemState)
        func send(_ type: CGEventType) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
            // A Shift still held from Shift-Return must not make it a Shift-click.
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        send(.mouseMoved)
        try? await Task.sleep(for: .milliseconds(30))
        send(right ? .rightMouseDown : .leftMouseDown)
        // Some apps miss a press and release that arrive in the same instant.
        try? await Task.sleep(for: .milliseconds(40))
        send(right ? .rightMouseUp : .leftMouseUp)
    }

    func copyAll() {
        guard !lines.isEmpty else { return Announcer.say(String(localized: "Nothing to copy")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Announcer.say(String(localized: "Copied"))
    }
}

// MARK: - Window

struct ScreenOCRView: View {
    @ObservedObject private var model = ScreenOCR.shared
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.status)
                .accessibilityAddTraits(.updatesFrequently)
            List(selection: $selection) {
                ForEach(model.lines) { line in
                    HStack {
                        Text(line.text)
                        Spacer()
                        Button(String(localized: "Click")) { model.click(line: line) }
                            .accessibilityLabel(String(localized: "Click \(line.text)"))
                    }
                    .tag(line.id)
                }
            }
            .frame(minHeight: 240)
            .accessibilityLabel(String(localized: "Recognized lines"))
            HStack {
                Button(String(localized: "Capture Window")) { model.capture(wholeScreen: false, thenNavigate: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
                Button(String(localized: "Capture Whole Screen")) { model.capture(wholeScreen: true, thenNavigate: false) }
                    .disabled(model.busy)
                Button(String(localized: "Copy All")) { model.copyAll() }
                    .disabled(model.lines.isEmpty)
                Button(String(localized: "Speak All")) { Announcer.say(model.text) }
                    .disabled(model.lines.isEmpty)
            }
            Text(String(localized: "The text is recognized on this Mac. Clicking a line presses the mouse where that text is in the app."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 520)
        .onChange(of: selection) { _, new in
            if let new, let line = model.lines.first(where: { $0.id == new }) { model.select(line) }
        }
        .onDisappear { model.stop() }
    }
}
