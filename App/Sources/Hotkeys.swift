// Hotkeys.swift — a right-hand modifier (Right Option by default) + a command key,
// anywhere on the Mac. Which key runs which command is in Commands.swift and can
// be changed in Settings; digits 1 to 9 apply presets. After the layer key, the
// next key on its own runs its command (slash lists them, Escape cancels).
// The left-hand key of the same kind is left alone, so for example Left Option +
// arrows still move by word in text.
// Needs Accessibility permission (System Settings > Privacy & Security).

import AppKit
import ApplicationServices

enum Hotkeys {
    private enum Action: Equatable {
        case command(Command)
        case preset(Int)
        case user(UUID)
        case layerHelp
    }

    private static func action(for keyCode: Int64) -> Action? {
        if let command = KeyMap.commandForKey[keyCode] { return .command(command) }
        if let user = KeyMap.userCommandForKey[keyCode] { return .user(user) }
        return Key.presetDigits[keyCode].map(Action.preset)
    }

    /// After the layer key, the next key on its own (within a few seconds) runs its command.
    nonisolated(unsafe) private static var layerUntil: Date?

    /// Device-dependent modifier bits (IOLLEvent.h): which physical key is down.
    private static func bits(for modifier: ShortcutModifier) -> (flag: CGEventFlags, right: UInt64, left: UInt64) {
        switch modifier {
        case .option: (.maskAlternate, 0x40, 0x20)
        case .command: (.maskCommand, 0x10, 0x08)
        case .control: (.maskControl, 0x2000, 0x01)
        case .shift: (.maskShift, 0x04, 0x02)
        }
    }

    nonisolated(unsafe) private static var tap: CFMachPort?
    /// Keys whose press was taken as a shortcut; their release is taken too, so
    /// VoiceOver and other apps never see half of a keystroke.
    nonisolated(unsafe) private static var swallowedKeys = Set<Int64>()
    /// Read on the event tap thread; written on main when the setting changes.
    nonisolated(unsafe) static var modifier = ShortcutModifier.option
    /// While set (VoiceOver lessons and practice, the typing trainer), sees every key press
    /// first, with the key event for its characters; returning true takes the key.
    nonisolated(unsafe) static var keyObserver: ((Int64, CGEventFlags, NSEvent?) -> Bool)? {
        didSet {
            keyObserverGeneration &+= 1
            keyObserverIsBrief = false
            // Whoever had the keys can notice it no longer does (Screen OCR leaves its mode).
            NotificationCenter.default.post(name: observerChanged, object: nil)
        }
    }
    /// Posted whenever the observer is set or cleared.
    static let observerChanged = Notification.Name("VoiceOverAudioSplit.keyObserverChanged")
    /// Set, after taking the keys, by an observer that only waits a few seconds for one key
    /// (the resource monitor's digit): another feature may take over from it.
    nonisolated(unsafe) static var keyObserverIsBrief = false
    /// Changes each time the observer is set, so a short-lived observer (the resource monitor's
    /// digit) clears only itself, never a lesson that took over meanwhile.
    nonisolated(unsafe) private(set) static var keyObserverGeneration = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility permission if needed, then keeps trying until it is granted.
    static func start() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if installTap() { return }
        log("Waiting for Accessibility permission.")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            if installTap() { timer.invalidate() }
        }
    }

    private static func installTap() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        // Listen at the hardware level, ahead of other listeners: VoiceOver also
        // reads keys there, and in places where its Quick Nav letter keys are on it
        // would otherwise take keys such as D and X before this app sees them.
        // Fall back to the session level if the hardware level isn't allowed.
        var level = "hardware"
        var created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, _ in Hotkeys.handle(type, event) },
                                        userInfo: nil)
        if created == nil {
            level = "session"
            created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, _ in Hotkeys.handle(type, event) },
                                        userInfo: nil)
        }
        guard let newTap = created else { return false }
        tap = newTap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0), .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        log("Listening for shortcuts at the \(level) level.")
        // macOS switches a listener off when the app is slow to answer, and says so only
        // through the listener itself. Looked at every few seconds as well, a listener that
        // stayed off is found and switched back on.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            log("The shortcut listener was off; switched back on.")
        }
        return true
    }

    private static func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables slow or idle taps; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return swallowedKeys.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // A held key whose first press was taken: take its repeats too, so they don't
        // reach VoiceOver or type into the app (and so a held layer key doesn't cancel the layer).
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat && swallowedKeys.contains(keyCode) { return nil }

        if let observer = keyObserver, event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           observer(keyCode, event.flags, NSEvent(cgEvent: event)) {
            swallowedKeys.insert(keyCode)
            return nil
        }

        // Layer: take the next key press, whatever modifiers are held.
        if let until = layerUntil {
            layerUntil = nil
            if until > Date() {
                swallowedKeys.insert(keyCode)
                let action: Action? = keyCode == Key.escape ? nil : keyCode == Key.slash ? .layerHelp : action(for: keyCode)
                log("Layer key: \(keyCode)")
                DispatchQueue.main.async {
                    if let action, action != .command(.layer) { perform(action) } else { Announcer.say(String(localized: "Layer cancelled")) }
                }
                return nil
            }
        }

        let flags = event.flags
        let (flag, rightBit, leftBit) = bits(for: modifier)
        let otherModifiers = CGEventFlags([.maskCommand, .maskControl, .maskShift, .maskAlternate]).subtracting(flag)
        guard let action = action(for: keyCode),
              flags.contains(flag),
              flags.rawValue & rightBit != 0,
              flags.rawValue & leftBit == 0,
              flags.intersection(otherModifiers).isEmpty
        else {
            // Passed on whole: forget any old taken press of this key whose release was missed
            // (for example in a password field), so this release reaches the app.
            swallowedKeys.remove(keyCode)
            return Unmanaged.passUnretained(event)
        }

        // Swallow the key either way so held keys don't type into the focused app.
        swallowedKeys.insert(keyCode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            log("Shortcut: \(action)")
            if action == .command(.layer) { layerUntil = Date().addingTimeInterval(4) }
            DispatchQueue.main.async { perform(action) }
        }
        return nil
    }

    private static func perform(_ action: Action) {
        // In input help, every key except input help itself says what it does instead.
        if InputHelp.isOn && action != .command(.inputHelp) {
            switch action {
            case .command(let command): InputHelp.describe(command.title, key: KeyMap.key(for: command)?.name)
            case .preset(let number):
                let presets = Preferences.shared.presets
                InputHelp.describe(number <= presets.count ? String(localized: "Preset \(presets[number - 1].name)")
                                                           : String(localized: "Preset \(number), not set up"),
                                   key: "\(number)")
            case .user(let id):
                InputHelp.describe(Preferences.shared.userCommands.first { $0.id == id }?.name ?? String(localized: "Your command"), key: nil)
            case .layerHelp: InputHelp.describe(String(localized: "Lists the layer keys"), key: String(localized: "Slash"))
            }
            return
        }
        switch action {
        case .command(let command): Controller.shared.run(command)
        case .preset(let number): Controller.shared.applyPreset(number: number)
        case .user(let id): UserCommands.run(id)
        case .layerHelp: Announcer.say(KeyMap.spokenList)
        }
    }
}
