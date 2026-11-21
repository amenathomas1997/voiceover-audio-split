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
    /// Off the main thread, like the tones: starting sound on a sleeping wireless headset
    /// can block for most of a minute, and the main thread carries the keyboard shortcuts.
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.keep-awake")
    private static var wanted: Bool { UserDefaults.standard.bool(forKey: "keepAudioAwake") }

    static func update(enabled: Bool) {
        queue.async { enabled ? start() : stop() }
    }

    private static func start(retry: Bool = true) {
        guard !engine.isRunning else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        // One second of digital silence, looped.
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        silence.frameLength = silence.frameCapacity
        var playing = false
        // Connecting, starting and playing all throw Objective-C exceptions on a broken
        // graph; caught, not fatal.
        let problem = Tones.caught {
            // Connected again every time: after the output changes the old connection is
            // dead, and a player left on it throws on every later start. (Skipping this once
            // the player was attached, Keep Audio Awake stayed off after the first headset
            // change until the app was restarted.)
            if engine.attachedNodes.contains(player) {
                player.stop()
                engine.disconnectNodeOutput(player)
            } else {
                engine.attach(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
            } catch {
                log("Keep audio awake could not start: \(error)")
                return
            }
            player.scheduleBuffer(silence, at: nil, options: .loops)
            player.play()
            playing = true
        }
        if let problem { log("Keep audio awake could not play: \(problem)") }
        // A new output device (headphones plugged in) stops the engine; start again on it.
        observer = observer ?? NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
            queue.async {
                guard wanted else { return }
                stop()
                start()
            }
        }
        guard playing else {
            engine.stop()
            // The output may not be ready yet (just woken, still connecting): once more, shortly.
            if retry {
                queue.asyncAfter(deadline: .now() + 2) {
                    if wanted { start(retry: false) }
                }
            }
            return
        }
        log("Keeping audio awake.")
    }

    private static func stop() {
        _ = Tones.caught { player.stop() }
        engine.stop()
    }
}

enum VoiceOverRescue {
    private static let voiceOverApp = URL(fileURLWithPath: "/System/Library/CoreServices/VoiceOver.app")

    /// Quits VoiceOver and starts it again, speaking progress with the system voice.
    @MainActor private static var restarting = false

    @MainActor
    static func restart() {
        guard !restarting else { return }
        restarting = true
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 15) { restarting = false } }
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
                if NSWorkspace.shared.isVoiceOverEnabled {
                    // VoiceOver didn't quit, usually because AppleScript control is off.
                    await MainActor.run {
                        Announcer.useSystemVoice = Controller.shared.speechSilenced
                        Announcer.say(String(localized: "VoiceOver couldn't be restarted. In VoiceOver Utility, turn on Allow VoiceOver to be controlled with AppleScript, or press Command F5 twice."))
                    }
                    return
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
