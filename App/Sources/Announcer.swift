// Announcer.swift — speaks status changes. With VoiceOver running, the text is
// sent to VoiceOver itself (via Apple Events), so it uses the user's own voice
// and settings. VoiceOver ignores accessibility announcements from background
// apps like this one, so those can't be used. If VoiceOver refuses (it isn't
// running, "Allow VoiceOver to be controlled with AppleScript" is off, or the
// user declined the Automation prompt), the system voice is used instead.

import AppKit
import AVFoundation

enum Announcer {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.announcer")
    /// While VoiceOver is silenced its voice can't be heard, so use the system voice.
    nonisolated(unsafe) static var useSystemVoice = false

    /// The last thing announced, for "Audio Split, repeat that".
    nonisolated(unsafe) private(set) static var lastText = ""
    /// About when the current announcement will have been spoken, so the voice commands
    /// can ignore the microphone hearing the app's own speech.
    nonisolated(unsafe) private(set) static var speakingUntil = Date.distantPast

    /// Notes that something is being said aloud, roughly how long it takes.
    static func markSpeaking(_ text: String) {
        let seconds = 1.0 + Double(text.split(separator: " ").count) * 0.4
        speakingUntil = max(speakingUntil, Date().addingTimeInterval(seconds))
    }

    static func say(_ text: String) {
        lastText = text
        markSpeaking(text)
        queue.async {
            if !useSystemVoice && NSWorkspace.shared.isVoiceOverEnabled && sendToVoiceOver(text) { return }
            DispatchQueue.main.async {
                synthesizer.stopSpeaking(at: .immediate)
                synthesizer.speak(AVSpeechUtterance(string: text))
            }
        }
    }

    /// For the setup guide: tries to speak through VoiceOver and reports whether it worked.
    static func testVoiceOver(completion: @escaping (Bool) -> Void) {
        queue.async {
            let ok = NSWorkspace.shared.isVoiceOverEnabled && sendToVoiceOver("VoiceOver announcements are working")
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private static func sendToVoiceOver(_ text: String) -> Bool {
        VoiceOverText.run("output " + VoiceOverText.quoted(text)) != nil
    }
}
