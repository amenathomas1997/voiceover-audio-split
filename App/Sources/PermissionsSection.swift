// PermissionsSection.swift — the Permissions part of Settings: each permission the
// app uses, whether it's allowed (where macOS lets an app check without asking), and
// a button. Checking never shows a permission prompt. If the app hasn't asked yet, the
// button asks: macOS only lists an app in Privacy and Security (camera, microphone,
// speech recognition, controlling VoiceOver) once it has asked. After that, the button
// opens the right page of System Settings.

import AppKit
import AVFoundation
import Speech
import SwiftUI

enum Permission: String, CaseIterable, Identifiable {
    case accessibility, systemAudio, voiceOver, screen, microphone, speech, camera, automation

    var id: String { rawValue }

    enum Status { case allowed, notAllowed, notAsked, unknown }

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .systemAudio: String(localized: "System audio recording")
        case .voiceOver: String(localized: "Controlling VoiceOver")
        case .screen: String(localized: "Screen recording")
        case .microphone: String(localized: "Microphone")
        case .speech: String(localized: "Speech Recognition")
        case .camera: String(localized: "Camera")
        case .automation: String(localized: "Safari and Chrome")
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: String(localized: "Keyboard shortcuts, custom labels, place markers and Do It for Me.")
        case .systemAudio: String(localized: "The audio split, call captions and every sound feature. Nothing is recorded. Your Mac asks the first time you turn the split on.")
        case .voiceOver: String(localized: "Announcements in your VoiceOver voice, speech history, captions and Read Item. VoiceOver must be on. Also turn on the AppleScript setting in VoiceOver Utility: see the steps below.")
        case .screen: String(localized: "Describing images and videos, and reading the front window.")
        case .microphone: String(localized: "The microphone check, and voice commands if you turn them on.")
        case .speech: String(localized: "Voice commands and call captions, if you use them. Recognized on your Mac.")
        case .camera: String(localized: "Scan and Read, the camera readers, the object finder and the framing check.")
        case .automation: String(localized: "Presets for websites. Only needed if you use them.")
        }
    }

    /// The System Settings page for it.
    var settingsURL: URL {
        let page = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .systemAudio: "Privacy_AudioCapture"
        case .voiceOver, .automation: "Privacy_Automation"
        case .screen: "Privacy_ScreenCapture"
        case .microphone: "Privacy_Microphone"
        case .speech: "Privacy_SpeechRecognition"
        case .camera: "Privacy_Camera"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(page)")!
    }

    /// Checks without asking. Can wait on another app, so don't call on the main thread.
    func status() -> Status {
        switch self {
        case .accessibility: return AXIsProcessTrusted() ? .allowed : .notAllowed
        case .systemAudio: return .unknown // macOS doesn't let apps check this.
        case .screen: return CGPreflightScreenCaptureAccess() ? .allowed : .notAllowed
        case .microphone: return Self.capture(.audio)
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .allowed
            case .notDetermined: return .notAsked
            default: return .notAllowed
            }
        case .camera: return Self.capture(.video)
        case .voiceOver: return Self.automation("com.apple.VoiceOver")
        case .automation:
            let browsers = ["com.apple.Safari", "com.google.Chrome"].map(Self.automation)
            if browsers.contains(.allowed) { return .allowed }
            // Neither browser is open, so it can't be asked: unknown, not "not asked yet".
            if browsers.allSatisfy({ $0 == .unknown }) { return .unknown }
            return browsers.contains(.notAllowed) ? .notAllowed : .notAsked
        }
    }

    /// Whether the app can ask macOS itself (showing the Allow prompt and adding the
    /// app to the list), rather than only opening System Settings.
    var canAsk: Bool { self != .systemAudio }

    /// Asks macOS for the permission, showing its prompt; calls back on the main thread.
    func ask(then done: @escaping () -> Void) {
        let finish = { DispatchQueue.main.async(execute: done) }
        switch self {
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in finish() }
        case .camera: AVCaptureDevice.requestAccess(for: .video) { _ in finish() }
        case .speech: SFSpeechRecognizer.requestAuthorization { _ in finish() }
        case .screen:
            _ = CGRequestScreenCaptureAccess()
            finish()
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            finish()
        case .voiceOver: Self.askToAutomate(["com.apple.VoiceOver"], then: finish)
        case .automation: Self.askToAutomate(["com.apple.Safari", "com.google.Chrome"], then: finish)
        case .systemAudio: finish()
        }
    }

    /// Shows macOS's "wants to control" prompt for apps that are running.
    private static func askToAutomate(_ bundleIDs: [String], then done: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            for id in bundleIDs where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                if let descriptor = NSAppleEventDescriptor(bundleIdentifier: id).aeDesc {
                    _ = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, true)
                }
            }
            done()
        }
    }

    private static func capture(_ type: AVMediaType) -> Status {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .notAllowed
        }
    }

    /// Whether this app may send Apple Events to another app, without prompting.
    private static func automation(_ bundleID: String) -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .notAllowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unknown // For example, the app isn't running.
        }
    }
}

final class PermissionsModel: ObservableObject {
    @Published var statuses: [Permission: Permission.Status] = [:]
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        // Pick up changes made in System Settings while this window is open.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let found = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, $0.status()) })
            DispatchQueue.main.async { self.statuses = found }
        }
    }
}

struct PermissionsSection: View {
    @StateObject private var model = PermissionsModel()

    var body: some View {
        Section(String(localized: "Permissions")) {
            Text(String(localized: "What the app is allowed to do. If it hasn't asked yet, the button asks: your Mac shows a prompt, and you choose Allow. After that, the button opens the right page of System Settings, where VoiceOver Audio Split is in the list and you can turn it on or off."))
                .font(.caption).foregroundStyle(.secondary)
                // On one row, not the whole section: a Form applies section modifiers to every row.
                .onAppear { model.start() }
                .onDisappear { model.stop() }
            ForEach(Permission.allCases) { permission in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "\(permission.title): \(describe(model.statuses[permission]))"))
                        Text(permission.purpose).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    if model.statuses[permission] == .notAsked && permission.canAsk {
                        Button(String(localized: "Ask for \(permission.title)")) {
                            permission.ask { model.refresh() }
                        }
                    } else {
                        Button(String(localized: "Open \(permission.title) Settings")) {
                            // Asking first puts the app in these lists; macOS can't say whether it was asked.
                            if [.screen, .accessibility].contains(permission) && model.statuses[permission] != .allowed {
                                permission.ask { NSWorkspace.shared.open(permission.settingsURL) }
                            } else {
                                NSWorkspace.shared.open(permission.settingsURL)
                            }
                        }
                    }
                }
            }
            VoiceOverAppleScriptSteps()
            HStack {
                Button(String(localized: "Open the Setup Guide")) {
                    (NSApp.delegate as? AppDelegate)?.showSetupGuide()
                }
            }
        }
    }

    private func describe(_ status: Permission.Status?) -> String {
        switch status {
        case .allowed: String(localized: "allowed")
        case .notAllowed: String(localized: "not allowed")
        case .notAsked: String(localized: "not asked yet")
        case .unknown: String(localized: "macOS doesn't say; if the feature works, it's allowed")
        case nil: String(localized: "checking")
        }
    }
}

/// Where the AppleScript setting is in VoiceOver Utility, step by step with VoiceOver.
struct VoiceOverAppleScriptSteps: View {
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Turning on the AppleScript setting in VoiceOver Utility")).font(.headline)
            Text(String(localized: "1. Press Open VoiceOver Utility below, or press VO F8."))
            Text(String(localized: "2. VoiceOver Utility opens with General chosen in the list of categories."))
            Text(String(localized: "3. Press VO F to find text, type AppleScript, and press Return. VoiceOver goes to the checkbox \u{201C}Allow VoiceOver to be controlled with AppleScript\u{201D}. Or press Tab until you hear it."))
            Text(String(localized: "4. If it says unchecked, press VO Space to check it."))
            Text(String(localized: "5. Close VoiceOver Utility with Command Q, and press Test Announcement below."))
            Text(String(localized: "The first time, your Mac asks whether VoiceOver Audio Split may control VoiceOver. Choose OK. If you chose Don't Allow before, turn it on in System Settings, Privacy and Security, Automation, under VoiceOver Audio Split."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Open VoiceOver Utility")) { Self.openVoiceOverUtility() }
                Button(String(localized: "Test Announcement")) {
                    result = String(localized: "Testing…")
                    VoiceOverSetup.check { result = $0 }
                }
            }
            if let result { Text(result) }
        }
        .padding(.vertical, 4)
    }

    static func openVoiceOverUtility() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.VoiceOverUtility") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Works out which part of controlling VoiceOver is missing, and says what to do.
enum VoiceOverSetup {
    enum Result: Equatable { case working, voiceOverOff, notAllowed, appleScriptOff }

    static func message(_ result: Result) -> String {
        switch result {
        case .working: String(localized: "Working. VoiceOver spoke the test.")
        case .voiceOverOff: String(localized: "VoiceOver is off. Turn it on with Command F5, then test again.")
        case .notAllowed: String(localized: "Your Mac doesn't allow VoiceOver Audio Split to control VoiceOver. Open System Settings, Privacy and Security, Automation, and under VoiceOver Audio Split turn on VoiceOver.")
        case .appleScriptOff: String(localized: "VoiceOver didn't respond, so the AppleScript setting is probably off. Follow the steps above to check it in VoiceOver Utility.")
        }
    }

    /// Tests, asking for permission to control VoiceOver if the Mac hasn't asked yet.
    static func check(completion: @escaping (String) -> Void) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return completion(message(.voiceOverOff)) }
        DispatchQueue.global(qos: .userInitiated).async {
            var allowed = true
            if let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.VoiceOver").aeDesc {
                let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, true)
                allowed = status == noErr || status == OSStatus(procNotFound)
            }
            guard allowed else { return DispatchQueue.main.async { completion(message(.notAllowed)) } }
            Announcer.testVoiceOver { working in completion(message(working ? .working : .appleScriptOff)) }
        }
    }
}
