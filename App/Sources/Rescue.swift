// Rescue.swift — fixes for two everyday VoiceOver problems AppleVis users report:
//   * Keep audio awake: headphones and Bluetooth devices go to sleep between
//     phrases, so the first word VoiceOver says can be clipped. Playing silence
//     keeps the output awake.
//   * VoiceOver rescue: when Quick Nav stops working or focus gets stuck, the
//     usual fix is restarting VoiceOver. One key does it, with spoken progress
//     in the system voice while VoiceOver is off.

import AppKit
import AVFoundation

enum KeepAudioAwake {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var observer: NSObjectProtocol?

    static func update(enabled: Bool) {
        enabled ? start() : stop()
    }

    private static func start() {
        guard !engine.isRunning else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        // One second of digital silence, looped.
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        silence.frameLength = silence.frameCapacity
        do {
            try engine.start()
        } catch {
            log("Keep audio awake could not start: \(error)")
            return
        }
        player.scheduleBuffer(silence, at: nil, options: .loops)
        player.play()
        // A new output device (headphones plugged in) stops the engine; start again on it.
        observer = observer ?? NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            guard Preferences.shared.keepAudioAwake else { return }
            stop()
            start()
        }
        log("Keeping audio awake.")
    }

    private static func stop() {
        player.stop()
        engine.stop()
    }
}

enum VoiceOverRescue {
    private static let voiceOverApp = URL(fileURLWithPath: "/System/Library/CoreServices/VoiceOver.app")

    /// Quits VoiceOver and starts it again, speaking progress with the system voice.
    @MainActor
    static func restart() {
        let wasRunning = NSWorkspace.shared.isVoiceOverEnabled
        Announcer.useSystemVoice = true
        Announcer.say(wasRunning ? String(localized: "Restarting VoiceOver") : String(localized: "Starting VoiceOver"))
        log("VoiceOver rescue.")
        Task {
            if wasRunning {
                _ = await Task.detached { VoiceOverText.run("quit", logErrors: true) }.value
                // Wait for VoiceOver to finish quitting.
                for _ in 0..<20 where NSWorkspace.shared.isVoiceOverEnabled {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                try await NSWorkspace.shared.openApplication(at: voiceOverApp, configuration: configuration)
            } catch {
                log("Could not start VoiceOver: \(error)")
            }
            for _ in 0..<20 where !NSWorkspace.shared.isVoiceOverEnabled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            await MainActor.run {
                Announcer.useSystemVoice = Controller.shared.speechSilenced
                if !NSWorkspace.shared.isVoiceOverEnabled {
                    Announcer.say(String(localized: "VoiceOver didn't start. Press Command F5 to turn it on."))
                }
            }
        }
    }
}
