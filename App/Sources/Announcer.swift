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

    static func say(_ text: String) {
        queue.async {
            if NSWorkspace.shared.isVoiceOverEnabled && sendToVoiceOver(text) { return }
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
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "tell application id \"com.apple.VoiceOver\" to output \"\(escaped)\"")?
            .executeAndReturnError(&error)
        if let error { log("VoiceOver announcement failed: \(error)") }
        return error == nil
    }
}
