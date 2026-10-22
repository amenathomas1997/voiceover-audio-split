// VOAudioSplitKeys — always-on keyboard shortcuts for VoiceOver Audio Split.
//
// Watches for Right Option + arrow keys anywhere on the Mac and runs the
// matching script bundled inside this app (Contents/Resources/Scripts):
//   Right Option + Left    Speech Left   (again: split off)
//   Right Option + Right   Speech Right  (again: split off)
//   Right Option + Up      Speech Louder
//   Right Option + Down    Other Sounds Louder
// Left Option + arrows are left alone, so moving by word in text still works.
// Needs Accessibility permission (System Settings > Privacy & Security).

import AppKit
import ApplicationServices
import Foundation

let scriptsFolder = Bundle.main.resourceURL!.appendingPathComponent("Scripts")

/// Virtual key code -> script name.
let bindings: [Int64: String] = [
    123: "Speech Left",
    124: "Speech Right",
    126: "Speech Louder",
    125: "Other Sounds Louder",
]

/// Device-dependent modifier bits (IOLLEvent.h): which physical Option key is down.
let rightOptionBit: UInt64 = 0x40
let leftOptionBit: UInt64 = 0x20

func log(_ message: String) {
    FileHandle.standardError.write(("VOAudioSplitKeys: " + message + "\n").data(using: .utf8)!)
}

func runScript(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [scriptsFolder.appendingPathComponent("\(name).scpt").path]
    do { try process.run() } catch { log("Could not run \(name): \(error)") }
}

var eventTap: CFMachPort?

func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    // macOS disables slow or idle taps; switch it straight back on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let raw = flags.rawValue
    let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
    guard let script = bindings[keyCode],
          flags.contains(.maskAlternate),
          raw & rightOptionBit != 0,
          raw & leftOptionBit == 0,
          flags.intersection(otherModifiers).isEmpty
    else { return Unmanaged.passUnretained(event) }

    // Swallow the key either way so held keys don't type into the focused app.
    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        runScript(script)
    }
    return nil
}

func installTap() -> Bool {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask,
                                      callback: { _, type, event, _ in handle(type, event) },
                                      userInfo: nil) else { return false }
    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("Listening for Right Option + arrow keys.")
    return true
}

// Ask for Accessibility permission once, then keep trying until it is granted.
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
_ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
if !installTap() {
    log("Waiting for Accessibility permission.")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        if installTap() { timer.invalidate() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
