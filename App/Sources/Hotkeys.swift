// Hotkeys.swift — a right-hand modifier (Right Option by default) + a key, anywhere on the Mac:
//   + Left    speech left   (again: split off)
//   + Right   speech right  (again: split off)
//   + Up      speech louder
//   + Down    other sounds louder
//   + Space   say what is on
//   + M       open the app's menu (useful when the menu bar item is hidden)
//   + Q       quiet everything but VoiceOver (again: bring it back)
//   + W       say which apps are playing
//   + = / -   front app louder / quieter
//   + 0       mute or unmute the front app
//   + D       switch to the next output device
//   + X       mute or unmute the microphone
//   + 1 to 9  apply a preset
//   + S       silence VoiceOver's voice (again: bring it back)
//   + R       read the item under the VoiceOver cursor
//   + H       open speech history
//   + C       say what is on the clipboard
//   + F       check camera framing
//   + L       layer: the next key alone runs its command (slash lists them, Escape cancels)
// The left-hand key of the same kind is left alone, so for example Left Option +
// arrows still move by word in text.
// Needs Accessibility permission (System Settings > Privacy & Security).

import AppKit
import ApplicationServices

enum Hotkeys {
    private enum Action: Equatable {
        case left, right, louder, quieter, status, menu, quiet, playing
        case appLouder, appQuieter, appMute, device, microphone
        case silence, readItem, history, clipboard, camera, layer, layerHelp
        case preset(Int)
    }

    /// Virtual key codes.
    private static let bindings: [Int64: Action] = [
        123: .left, 124: .right, 126: .louder, 125: .quieter, 49: .status, 46: .menu, 12: .quiet, 13: .playing,
        24: .appLouder, 27: .appQuieter, 29: .appMute, 2: .device, 7: .microphone,
        18: .preset(1), 19: .preset(2), 20: .preset(3), 21: .preset(4), 23: .preset(5),
        22: .preset(6), 26: .preset(7), 28: .preset(8), 25: .preset(9),
        1: .silence, 15: .readItem, 4: .history, 8: .clipboard, 3: .camera, 37: .layer,
    ]

    /// After the layer key, the next key on its own (within a few seconds) runs its command.
    nonisolated(unsafe) private static var layerUntil: Date?
    private static let escapeKey: Int64 = 53
    private static let slashKey: Int64 = 44

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

        // Layer: take the next key press, whatever modifiers are held.
        if let until = layerUntil {
            layerUntil = nil
            if until > Date() {
                swallowedKeys.insert(keyCode)
                let action: Action? = keyCode == escapeKey ? nil : keyCode == slashKey ? .layerHelp : bindings[keyCode]
                log("Layer key: \(keyCode)")
                DispatchQueue.main.async {
                    if let action, action != .layer { perform(action) } else { Announcer.say("Layer cancelled") }
                }
                return nil
            }
        }

        let flags = event.flags
        let (flag, rightBit, leftBit) = bits(for: modifier)
        let otherModifiers = CGEventFlags([.maskCommand, .maskControl, .maskShift, .maskAlternate]).subtracting(flag)
        guard let action = bindings[keyCode],
              flags.contains(flag),
              flags.rawValue & rightBit != 0,
              flags.rawValue & leftBit == 0,
              flags.intersection(otherModifiers).isEmpty
        else { return Unmanaged.passUnretained(event) }

        // Swallow the key either way so held keys don't type into the focused app.
        swallowedKeys.insert(keyCode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            log("Shortcut: \(action)")
            if case .layer = action { layerUntil = Date().addingTimeInterval(4) }
            DispatchQueue.main.async { perform(action) }
        }
        return nil
    }

    private static func perform(_ action: Action) {
        let controller = Controller.shared
        switch action {
        case .left: controller.toggle(.left)
        case .right: controller.toggle(.right)
        case .louder: controller.changeBalance(by: Preferences.shared.balanceStep)
        case .quieter: controller.changeBalance(by: -Preferences.shared.balanceStep)
        case .status: controller.announceStatus()
        case .menu: (NSApp.delegate as? AppDelegate)?.popUpMenu()
        case .quiet: controller.toggleQuiet()
        case .playing: controller.announcePlaying()
        case .appLouder: controller.changeFrontAppVolume(by: 3)
        case .appQuieter: controller.changeFrontAppVolume(by: -3)
        case .appMute: controller.toggleFrontAppMute()
        case .device: controller.nextOutputDevice()
        case .microphone: controller.toggleMicrophone()
        case .preset(let number): controller.applyPreset(number: number)
        case .silence: controller.toggleSilence()
        case .readItem: controller.readItem()
        case .history: (NSApp.delegate as? AppDelegate)?.showHistory()
        case .clipboard: controller.sayClipboard()
        case .camera: controller.checkCamera()
        case .layer:
            Tones.play(.status)
            Announcer.say("Layer")
        case .layerHelp:
            Announcer.say("Layer keys: arrows for the split and volume, S silence, R read item, H history, "
                          + "C clipboard, F camera, Q quiet, W what's playing, D device, X microphone, "
                          + "M menu, Space status, equals, minus and zero for the front app, 1 to 9 presets. "
                          + "Escape cancels.")
        }
    }
}
