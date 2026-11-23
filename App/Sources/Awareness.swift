// Awareness.swift — sounds for things VoiceOver doesn't say on its own, heard through the
// accessibility interface of the app in front (the same one VoiceOver uses):
//   * Progress bar tones, like NVDA's: a short tone that rises as a progress bar fills.
//   * Indentation tones, also like NVDA's: when the text cursor moves to a line that is
//     indented differently, a tone whose pitch says how far. For reading code.
// Both are off until turned on. Nothing is read except a progress bar's value and the
// white space at the start of the line the cursor is on; nothing is stored or sent.

import AppKit
import ApplicationServices
import os

// MARK: - Hearing from the app in front

/// One accessibility observer on the app in front, for the notifications the features
/// that are switched on need. Moves to the new app when another comes forward.
enum FrontAppEvents {
    private static var observer: AXObserver?
    private static var watched: (pid: pid_t, names: [String])?
    /// The questions that follow a notification are asked here, not on the main thread:
    /// a busy app can take its time to answer.
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.front-app-events", qos: .userInitiated)
    /// Notifications waiting to be looked at. A scrolling list sends dozens a second;
    /// past a few, the rest are dropped rather than queued.
    private static let waiting = OSAllocatedUnfairLock(initialState: 0)

    #if DEBUG
    /// For the self-check: listen to this process instead of the app in front, and hear
    /// what was understood from each notification.
    nonisolated(unsafe) static var checkPID: pid_t?
    nonisolated(unsafe) static var onCheck: ((String) -> Void)?
    #endif

    /// Starts, stops or moves the observer to match the settings and the app in front.
    /// Call on the main thread, after either changes.
    static func update() {
        let preferences = Preferences.shared
        var names: [String] = []
        if preferences.progressTones { names.append(kAXValueChangedNotification) }
        if preferences.indentTones { names.append(kAXSelectedTextChangedNotification) }
        var pid = names.isEmpty || !Hotkeys.isTrusted ? nil : Controller.shared.lastUsedApp?.processIdentifier
        #if DEBUG
        if let checkPID, !names.isEmpty { pid = checkPID }
        #endif
        if let pid, let watched, watched.pid == pid, watched.names == names { return }
        stop()
        guard let pid else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, _ in
            FrontAppEvents.received(element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AX.application(pid)
        var added = false
        for name in names where AXObserverAddNotification(created, app, name as CFString, nil) == .success { added = true }
        guard added else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        watched = (pid, names)
        IndentTones.reset()
        ProgressTones.reset()
    }

    private static func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        watched = nil
    }

    private static func received(_ element: AXUIElement, _ notification: String) {
        let room = waiting.withLock { count -> Bool in
            guard count < 6 else { return false }
            count += 1
            return true
        }
        guard room else { return }
        queue.async {
            waiting.withLock { $0 -= 1 }
            switch notification {
            case kAXValueChangedNotification: ProgressTones.changed(element)
            case kAXSelectedTextChangedNotification: IndentTones.moved(in: element)
            default: break
            }
        }
    }
}

// MARK: - Progress bar tones

enum ProgressTones {
    /// The last tone played: how full the bar was, and when. Main thread.
    private static var last: (fraction: Double, time: Date)?

    static func reset() { last = nil }

    /// How full a bar is, from 0 to 1; nil when it doesn't say (a spinner, a busy bar).
    static func fraction(value: Double, min: Double, max: Double) -> Double? {
        guard max > min, value.isFinite else { return nil }
        return Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }

    /// Empty is a low tone (220 Hz) and full a high one (1760 Hz), evenly spaced in pitch.
    static func frequency(for fraction: Double) -> Double {
        220 * pow(8, Swift.min(1, Swift.max(0, fraction)))
    }

    /// Whether a new reading deserves a tone: the first one, one that has just filled the
    /// bar, a step of two percent (not more often than four times a second), or a jump.
    static func shouldSound(_ fraction: Double, last: Double?, secondsSinceLast: TimeInterval) -> Bool {
        guard let last else { return true }
        if fraction >= 1 { return last < 1 }
        let moved = abs(fraction - last)
        return moved >= 0.1 || (moved >= 0.02 && secondsSinceLast >= 0.25)
    }

    /// On the events queue: something's value changed in the app in front.
    static func changed(_ element: AXUIElement) {
        guard AX.string(element, kAXRoleAttribute) == kAXProgressIndicatorRole else { return }
        func number(_ attribute: String) -> Double? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return (value as? NSNumber)?.doubleValue
        }
        guard let value = number(kAXValueAttribute),
              let fraction = fraction(value: value, min: number(kAXMinValueAttribute) ?? 0, max: number(kAXMaxValueAttribute) ?? 1)
        else { return }
        #if DEBUG
        FrontAppEvents.onCheck?(String(format: "bar %.2f", fraction))
        #endif
        DispatchQueue.main.async {
            guard Preferences.shared.progressTones else { return }
            let now = Date()
            guard shouldSound(fraction, last: last?.fraction, secondsSinceLast: now.timeIntervalSince(last?.time ?? .distantPast)) else { return }
            last = (fraction, now)
            Tones.beep(frequency: frequency(for: fraction))
        }
    }
}

// MARK: - Indentation

enum Indentation {
    struct Measure: Equatable {
        /// Columns of white space before the first character; a tab counts as four.
        let width: Int
        let tabs: Int
        let spaces: Int
    }

    /// The white space a line starts with, or nil for a blank line (which says nothing
    /// about how the text around it is indented).
    static func measure(_ line: String, tabWidth: Int = 4) -> Measure? {
        var tabs = 0, spaces = 0
        for character in line {
            if character == "\t" {
                tabs += 1
            } else if character == " " || character == "\u{00A0}" {
                spaces += 1
            } else if character.isNewline {
                return nil
            } else {
                return Measure(width: tabs * tabWidth + spaces, tabs: tabs, spaces: spaces)
            }
        }
        return nil
    }

    /// No indentation is 220 Hz; every column is a quarter tone higher, so four spaces are
    /// one whole tone and each level of code is easy to tell from the next. It stops rising
    /// after 72 columns.
    static func frequency(forWidth width: Int) -> Double {
        220 * pow(2, Double(Swift.min(Swift.max(width, 0), 72)) / 24)
    }

    static func spoken(_ measure: Measure?) -> String {
        guard let measure else { return String(localized: "This line is blank.") }
        if measure.width == 0 { return String(localized: "Not indented.") }
        let tabs = String(localized: "\(measure.tabs) tabs"), spaces = String(localized: "\(measure.spaces) spaces")
        if measure.tabs > 0 && measure.spaces > 0 { return String(localized: "Indented \(tabs) and \(spaces).") }
        return String(localized: "Indented \(measure.tabs > 0 ? tabs : spaces).")
    }
}

enum IndentTones {
    /// Events queue: the text being edited, the line the cursor was on, and how far the
    /// last line that had text was indented.
    nonisolated(unsafe) private static var lastElement: AXUIElement?
    nonisolated(unsafe) private static var lastLine = -1
    nonisolated(unsafe) private static var lastWidth: Int?

    static func reset() {
        lastElement = nil
        lastLine = -1
        lastWidth = nil
    }

    /// The start of the line the text cursor is on, in `element`, with its line number.
    /// Only the first characters are read: enough to see the white space.
    static func currentLine(in element: AXUIElement) -> (number: Int, start: String)? {
        var value: CFTypeRef?
        var number: Int?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &value) == .success {
            number = (value as? NSNumber)?.intValue
        }
        if number == nil {
            // Some apps only say where the selection is: ask which line that is.
            var selection: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
                  let selection, CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            AXValueGetValue(selection as! AXValue, .cfRange, &range)
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXLineForIndexParameterizedAttribute as CFString,
                                                             NSNumber(value: range.location), &value) == .success else { return nil }
            number = (value as? NSNumber)?.intValue
        }
        guard let number else { return nil }
        var lineRange: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForLineParameterizedAttribute as CFString,
                                                         NSNumber(value: number), &lineRange) == .success,
              let lineRange, CFGetTypeID(lineRange) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        AXValueGetValue(lineRange as! AXValue, .cfRange, &range)
        range.length = Swift.min(range.length, 200)
        guard range.length > 0, let start = AXValueCreate(.cfRange, &range) else { return (number, "") }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         start, &text) == .success else { return nil }
        return (number, text as? String ?? "")
    }

    /// On the events queue: the text cursor or selection moved in the app in front.
    static func moved(in element: AXUIElement) {
        // Only where text has lines: a text area, not a search field.
        guard AX.string(element, kAXRoleAttribute) == kAXTextAreaRole, let line = currentLine(in: element) else { return }
        let sameText = lastElement.map { CFEqual($0, element) } ?? false
        if !sameText {
            lastElement = element
            lastLine = -1
            lastWidth = nil
        }
        guard line.number != lastLine else { return }
        lastLine = line.number
        #if DEBUG
        FrontAppEvents.onCheck?("line \(line.number) indent \(Indentation.measure(line.start)?.width ?? -1)")
        #endif
        guard let measure = Indentation.measure(line.start), measure.width != lastWidth else { return }
        // The first line looked at in a text sets the level without a tone, unless it's indented.
        let first = lastWidth == nil
        lastWidth = measure.width
        if first && measure.width == 0 { return }
        DispatchQueue.main.async {
            guard Preferences.shared.indentTones else { return }
            Tones.beep(frequency: Indentation.frequency(forWidth: measure.width), seconds: 0.08)
        }
    }

    /// Says how far the line the text cursor is on is indented, whichever app it's in.
    static func sayCurrent() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AX.application(getpid()) // Sets the time limit for every question.
            let focused = AX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
            let line = focused.flatMap { currentLine(in: $0) }
            DispatchQueue.main.async {
                guard let line else {
                    return Announcer.say(String(localized: "Put the text cursor in some text first, such as a code editor."))
                }
                Announcer.say(Indentation.spoken(Indentation.measure(line.start)))
            }
        }
    }
}
