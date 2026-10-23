// Tones.swift — short sounds that confirm a change before the announcement,
// so the result can be recognised without waiting for speech. Each tone plays
// from the side it describes (or in the chosen ear, in one-ear mode). This app's own audio is excluded from the split,
// so tones are never moved or muted by it.

import AVFoundation

enum Tone {
    case speechLeft, speechRight, speechBoth, off, louder, quieter, status
    case quiet, unquiet, micMuted, micOn, device, preset, beep
}

/// What the typing trainer plays for each key typed right.
enum TypingSound: String, CaseIterable, Identifiable {
    case click, tone, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: String(localized: "Soft click")
        case .tone: String(localized: "Soft tone")
        case .none: String(localized: "No sound")
        }
    }
}

enum Tones {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private static var stopWork: DispatchWorkItem?
    /// Typing sounds have their own player, so a fast typist never cuts off other tones.
    private static let typingPlayer = AVAudioPlayerNode()

    static func play(_ tone: Tone) {
        guard Preferences.shared.playTones else { return }
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            log("Could not play tone: \(error)")
            return
        }
        player.stop()
        player.scheduleBuffer(buffer(for: tone))
        player.play()

        // Release the audio device shortly after the last tone.
        stopWork?.cancel()
        let work = DispatchWorkItem { player.stop(); engine.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: Typing trainer

    /// A key typed right (`correct`) or wrong. Wrong keys get a gentle low sound
    /// unless typing sounds are off; the spoken correction follows either way.
    static func playTyping(correct: Bool) {
        let kind = TypingSound(rawValue: Preferences.shared.typingSound) ?? .click
        guard kind != .none else { return }
        // Made each time (they're tiny), so they follow the one-ear setting.
        let buffer = makeBuffer(correct ? typingSamples(kind) : wrongSamples())
        if !engine.attachedNodes.contains(typingPlayer) {
            engine.attach(typingPlayer)
            engine.connect(typingPlayer, to: engine.mainMixerNode, format: format)
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        // Each sound fades to silence, so starting the next one over it doesn't click.
        typingPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
        typingPlayer.play()
        stopWork?.cancel()
        let work = DispatchWorkItem { player.stop(); typingPlayer.stop(); engine.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    /// Mono samples for a key typed right: a short, quiet click like a soft key,
    /// or a gentle rounded tone. Both are over in a few hundredths of a second.
    static func typingSamples(_ kind: TypingSound) -> [Float] {
        let rate = format.sampleRate
        switch kind {
        case .click:
            // Noise, smoothed to take the hiss off, with a very fast decay.
            var seed: UInt32 = 12345
            var smooth: Float = 0, previous: Float = 0
            return (0..<Int(rate * 0.018)).map { frame in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                smooth += (noise - smooth) * 0.35
                let body = smooth - previous * 0.6 // Take out the low thump.
                previous = smooth
                let t = Double(frame) / rate
                return body * 0.09 * Float(exp(-t / 0.0025)) * Float(min(1, t / 0.0005))
            }
        case .tone:
            return note(frequency: 659, seconds: 0.07, decay: 0.022, level: 0.055)
        case .none:
            return []
        }
    }

    /// Two soft, low, falling notes: clear without being harsh.
    static func wrongSamples() -> [Float] {
        note(frequency: 330, seconds: 0.11, decay: 0.05, level: 0.09) + note(frequency: 262, seconds: 0.16, decay: 0.07, level: 0.09)
    }

    /// A rounded note like a soft mallet: a quick fade in, then a smooth fade out,
    /// with a touch of the octave above for warmth.
    private static func note(frequency: Double, seconds: Double, decay: Double, level: Float) -> [Float] {
        let rate = format.sampleRate
        return (0..<Int(rate * seconds)).map { frame in
            let t = Double(frame) / rate
            let wave = sin(2 * .pi * frequency * t) + 0.15 * sin(4 * .pi * frequency * t)
            let envelope = min(1, t / 0.004) * exp(-t / decay)
            return Float(wave * envelope) * level
        }
    }

    private static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let pan: Float? = switch Preferences.shared.oneEar { case .off: nil; case .left: -1; case .right: 1 }
        for (i, sample) in samples.enumerated() {
            buffer.floatChannelData![0][i] = sample * min(1, 1 - (pan ?? 0))
            buffer.floatChannelData![1][i] = sample * min(1, 1 + (pan ?? 0))
        }
        return buffer
    }

    /// Notes as (frequency in Hz, pan from -1 left to 1 right).
    private static func notes(for tone: Tone) -> [(Double, Float)] {
        switch tone {
        case .speechLeft: [(660, -0.9), (880, -0.9)]
        case .speechRight: [(660, 0.9), (880, 0.9)]
        case .speechBoth: [(660, 0), (880, 0)]
        case .off: [(660, 0), (440, 0)]
        case .louder: [(990, 0)]
        case .quieter: [(550, 0)]
        case .status: [(770, 0)]
        case .quiet: [(880, 0), (440, 0), (330, 0)]
        case .unquiet: [(330, 0), (440, 0), (880, 0)]
        case .micMuted: [(392, 0), (294, 0)]
        case .micOn: [(294, 0), (392, 0)]
        case .device: [(523, 0), (659, 0), (784, 0)]
        case .preset: [(587, 0), (587, 0)]
        case .beep: [(1320, 0)]
        }
    }

    private static func buffer(for tone: Tone) -> AVAudioPCMBuffer {
        let noteFrames = Int(format.sampleRate * 0.07)
        let notes = notes(for: tone)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(noteFrames * notes.count))!
        buffer.frameLength = buffer.frameCapacity
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        // In one-ear mode, every tone plays in that ear.
        let oneEarPan: Float? = switch Preferences.shared.oneEar {
        case .off: nil
        case .left: -1
        case .right: 1
        }
        for (index, (frequency, notePan)) in notes.enumerated() {
            let pan = oneEarPan ?? notePan
            for frame in 0..<noteFrames {
                let t = Double(frame) / format.sampleRate
                // Short fade in and out so the notes don't click.
                let envelope = Float(min(1, min(Double(frame), Double(noteFrames - frame)) / (format.sampleRate * 0.01)))
                let sample = Float(sin(2 * .pi * frequency * t)) * 0.18 * envelope
                left[index * noteFrames + frame] = sample * min(1, 1 - pan)
                right[index * noteFrames + frame] = sample * min(1, 1 + pan)
            }
        }
        return buffer
    }
}
