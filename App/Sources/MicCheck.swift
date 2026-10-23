// MicCheck.swift — a microphone check before a call: after a tone, the user says
// a sentence; the app measures how loud the voice is and how much background
// noise there is, and says what to fix. The sound is measured as it arrives and
// never recorded or saved.

import AVFoundation

enum MicCheck {
    struct Result: Equatable {
        /// Loudness of speech (the loud parts), in dB below full scale.
        let speechLevel: Float
        /// Loudness of the quiet parts between words: the background noise.
        let noiseLevel: Float
        let clipped: Bool
    }

    /// A new engine for each check, so a microphone change since the last one is picked up.
    private static var engine = AVAudioEngine()
    private static var running = false

    static func run() {
        guard !running else { return }
        if AudioSystem.isMicMuted { return Announcer.say(String(localized: "Your microphone is muted. Unmute it first, then check again.")) }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { granted ? start() : Announcer.say(String(localized: "Microphone access was not allowed")) }
            }
        default:
            Announcer.say(String(localized: "Microphone access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Microphone."))
        }
    }

    private static func start() {
        running = true
        Announcer.say(String(localized: "Microphone check. After the tone, say a sentence in your normal voice."))
        // Give the announcement time to finish before listening.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { listen() }
    }

    private static func listen() {
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            running = false
            return Announcer.say(String(localized: "No microphone found"))
        }
        var levels: [Float] = []
        var peak: Float = 0
        let lock = NSLock()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0, bufferPeak: Float = 0
            for i in 0..<Int(buffer.frameLength) {
                sum += samples[i] * samples[i]
                bufferPeak = max(bufferPeak, abs(samples[i]))
            }
            let rms = sqrt(sum / Float(max(buffer.frameLength, 1)))
            lock.lock()
            levels.append(20 * log10(max(rms, 1e-7)))
            peak = max(peak, bufferPeak)
            lock.unlock()
        }
        Tones.play(.status)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            running = false
            return Announcer.say(String(localized: "The microphone couldn't start"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            input.removeTap(onBus: 0)
            engine.stop()
            running = false
            lock.lock()
            let measured = levels
            let maximum = peak
            lock.unlock()
            let result = measure(levels: measured, peak: maximum)
            log("Mic check: speech \(result.speechLevel) dB, noise \(result.noiseLevel) dB, clipped \(result.clipped).")
            Announcer.say(advice(for: result) + " " + String(localized: "Using \(AudioSystem.inputDeviceName)."))
        }
    }

    /// Speech level is the loud end of the measurements, noise the quiet end.
    static func measure(levels: [Float], peak: Float) -> Result {
        let sorted = levels.sorted()
        guard !sorted.isEmpty else { return Result(speechLevel: -120, noiseLevel: -120, clipped: false) }
        func percentile(_ p: Double) -> Float { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        return Result(speechLevel: percentile(0.9), noiseLevel: percentile(0.15), clipped: peak >= 0.99)
    }

    static func advice(for result: Result) -> String {
        if result.speechLevel < -55 { return String(localized: "I couldn't hear you. Check that the right microphone is selected and not muted.") }
        var notes: [String] = []
        if result.clipped || result.speechLevel > -8 {
            notes.append(String(localized: "You're too loud and may sound distorted. Move back a little or lower the input volume."))
        } else if result.speechLevel < -38 {
            notes.append(String(localized: "You're too quiet. Move closer to the microphone or raise the input volume."))
        }
        if result.noiseLevel > -45 || result.speechLevel - result.noiseLevel < 15 {
            notes.append(String(localized: "There's a lot of background noise."))
        }
        return notes.isEmpty ? String(localized: "You sound clear, with little background noise.") : notes.joined(separator: " ")
    }
}
