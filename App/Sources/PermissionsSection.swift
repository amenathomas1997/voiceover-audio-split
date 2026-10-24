// PermissionsSection.swift — the Permissions part of Settings: each permission the
// app uses, whether it's allowed (where macOS lets an app check without asking),
// and a button that opens the right page of System Settings. Checking never
// shows a permission prompt.

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
        case .systemAudio: String(localized: "The audio split and every sound feature. Nothing is recorded.")
        case .voiceOver: String(localized: "Announcements in your VoiceOver voice, speech history, captions and Read Item. Also turn on \u{201C}Allow VoiceOver to be controlled with AppleScript\u{201D} in VoiceOver Utility.")
        case .screen: String(localized: "Describing images and videos, and reading the front window.")
        case .microphone: String(localized: "The microphone check, and the voice command if you turn it on.")
        case .speech: String(localized: "The voice command \u{201C}Launch VoiceOver training\u{201D}, if you turn it on. Recognized on your Mac.")
        case .camera: String(localized: "Scan and Read, the camera readers and the framing check.")
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
            return browsers.contains(.notAllowed) ? .notAllowed : .notAsked
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
            Text(String(localized: "What the app is allowed to do. Each button opens the right page of System Settings, where you can turn VoiceOver Audio Split on or off."))
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
                    Button(String(localized: "Open \(permission.title) Settings")) {
                        NSWorkspace.shared.open(permission.settingsURL)
                    }
                }
            }
            HStack {
                Button(String(localized: "Open VoiceOver Utility")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.VoiceOverUtility") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
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
