// Tones.swift — short sounds that confirm a change before the announcement,
// so the result can be recognised without waiting for speech. Each tone plays
// from the side it describes (or in the chosen ear, in one-ear mode). This app's own audio is excluded from the split,
// so tones are never moved or muted by it.

import AVFoundation

enum Tone {
    case speechLeft, speechRight, speechBoth, off, louder, quieter, status
    case quiet, unquiet, micMuted, micOn, device, preset, beep
    /// The typing trainer: a key typed right, or wrong.
    case correct, wrong
}

enum Tones {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private static var stopWork: DispatchWorkItem?

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
        case .correct: [(1175, 0)]
        case .wrong: [(196, 0), (185, 0)]
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
