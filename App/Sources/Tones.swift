// Tones.swift — short sounds that confirm a change before the announcement,
// so the result can be recognised without waiting for speech. Each tone plays
// from the side it describes (or in the chosen ear, in one-ear mode). This app's own audio is excluded from the split,
// so tones are never moved or muted by it.

import AVFoundation
import os

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
    private static var observer: NSObjectProtocol?
    /// Set when the output changed under the engine (a wireless headset asleep, the Mac
    /// woken, headphones unplugged): the players are connected again before the next sound.
    /// Without that, the first tone afterwards ended the app with an audio exception.
    private static var needsReconnect = false

    /// Everything that touches the engine runs here, never on the main thread. Starting sound
    /// can take a very long time when the output is a wireless headset that has gone to
    /// sleep (measured on the user's Mac: over 45 seconds for a bare engine), and the main
    /// thread also carries the keyboard shortcuts: a tone played there froze them for as long.
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.tones", qos: .userInteractive)
    /// Sounds asked for and not yet started.
    private static let waiting = OSAllocatedUnfairLock(initialState: 0)

    /// Runs a sound's work on the queue, unless the queue is stuck behind an output that
    /// isn't answering: a tone seconds late, or a dozen at once when it finally answers, is
    /// worse than none.
    private static func enqueue(_ work: @escaping () -> Void) {
        let asked = Date()
        let room = waiting.withLock { count -> Bool in
            guard count < 3 else { return false }
            count += 1
            return true
        }
        guard room else { return }
        queue.async {
            waiting.withLock { $0 -= 1 }
            guard Date().timeIntervalSince(asked) < 1.5 else { return }
            work()
        }
    }

    static func play(_ tone: Tone) {
        guard Preferences.shared.playTones else { return }
        // Made here, on the caller's thread: it reads the one-ear setting.
        let sound = buffer(for: tone)
        enqueue {
            guard start(player, sound) else { return }
            // Release the audio device shortly after the last tone.
            stopWork?.cancel()
            let work = DispatchWorkItem {
                _ = caught { player.stop() }
                engine.stop()
            }
            stopWork = work
            queue.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    // MARK: Starting a sound safely

    /// Gets the engine ready for `node`: attached, connected (again, after an output
    /// change) and running. False when there's no output to play on.
    private static func prepare(_ node: AVAudioPlayerNode) -> Bool {
        observer = observer ?? NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in queue.async { needsReconnect = true } }
        var ready = false
        // Connecting and starting throw Objective-C exceptions too, in the very state that
        // needs them (an output still waking reports no channels or no rate), so the whole of
        // getting ready is caught, not only the play that follows. (The output's format isn't
        // asked for first: reaching for the engine's output node before anything is connected
        // can deadlock inside the audio framework, on the main thread.)
        let problem = caught {
            if needsReconnect {
                for attached in [player, typingPlayer] where engine.attachedNodes.contains(attached) {
                    attached.stop()
                    engine.disconnectNodeOutput(attached)
                    engine.connect(attached, to: engine.mainMixerNode, format: format)
                }
                needsReconnect = false
            }
            if !engine.attachedNodes.contains(node) {
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
            }
            do {
                if !engine.isRunning { try engine.start() }
                ready = true
            } catch {
                log("Could not play a sound: \(error)")
            }
        }
        if let problem {
            log("Could not get a sound ready: \(problem)")
            needsReconnect = true
        }
        return ready
    }

    /// Plays `buffer` on `node`. A player on a broken graph reports it by throwing an
    /// Objective-C exception, which Swift can't catch and which would end the app (it did,
    /// twenty hours after a login). Here it becomes one retry on a rebuilt graph, then silence.
    private static func start(_ node: AVAudioPlayerNode, _ buffer: AVAudioPCMBuffer,
                              options: AVAudioPlayerNodeBufferOptions = [], stopFirst: Bool = true) -> Bool {
        for attempt in 1...2 {
            guard prepare(node) else { return false }
            let problem = caught {
                if stopFirst { node.stop() }
                node.scheduleBuffer(buffer, at: nil, options: options)
                node.play()
            }
            guard let problem else { return true }
            log("A sound could not start (attempt \(attempt)): \(problem)")
            needsReconnect = true
            engine.stop()
        }
        return false
    }

    /// Runs `block`, returning the reason if it threw an Objective-C exception.
    static func caught(_ block: () -> Void) -> String? {
        var error: NSError?
        return VOACatchException(block, &error) ? nil : (error?.localizedDescription ?? "unknown audio problem")
    }

    // MARK: Typing trainer

    /// A key typed right (`correct`) or wrong. Wrong keys get a gentle low sound
    /// unless typing sounds are off; the spoken correction follows either way.
    static func playTyping(correct: Bool) {
        let kind = TypingSound(rawValue: Preferences.shared.typingSound) ?? .click
        guard kind != .none else { return }
        // Made each time (they're tiny), so they follow the one-ear setting.
        let buffer = makeBuffer(correct ? typingSamples(kind) : wrongSamples())
        enqueue {
            // Each sound fades to silence, so starting the next one over it doesn't click.
            guard start(typingPlayer, buffer, options: .interrupts, stopFirst: false) else { return }
            stopWork?.cancel()
            let work = DispatchWorkItem {
                _ = caught { player.stop(); typingPlayer.stop() }
                engine.stop()
            }
            stopWork = work
            queue.asyncAfter(deadline: .now() + 10, execute: work)
        }
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

// MARK: - Tones made as they play

/// A tone made as it plays: the light detector, the audio mouse, the object finder and the
/// listening test. All of the sound engine's work is done on a queue of its own, never the
/// main thread: setting up sound can block for most of a minute while the output device is
/// asleep (a wireless headset with the Mac locked), and the main thread carries the
/// keyboard shortcuts.
final class LiveTone: @unchecked Sendable {
    private let queue: DispatchQueue
    /// Counts starts and stops, so a start that was overtaken while it waited is dropped.
    private let generation = OSAllocatedUnfairLock(initialState: 0)
    // Used on the queue only.
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?

    init(_ name: String) {
        queue = DispatchQueue(label: "VoiceOverAudioSplit.tone.\(name)", qos: .userInitiated)
    }

    /// Starts the tone, replacing any already playing. `done` hears on the main thread
    /// whether it's playing. `outputChanged`, when given, is called on the main thread if the
    /// output device changes while it plays; without it, the tone carries on on the new output.
    func start(sampleRate: Double = 44100, channels: AVAudioChannelCount,
               render: @escaping AVAudioSourceNodeRenderBlock,
               outputChanged: (() -> Void)? = nil, done: ((Bool) -> Void)? = nil) {
        let mine = generation.withLock { count -> Int in
            count += 1
            return count
        }
        queue.async {
            self.close()
            let playing = self.isCurrent(mine)
                && self.open(sampleRate: sampleRate, channels: channels, render: render, outputChanged: outputChanged, mine: mine)
            if let done { DispatchQueue.main.async { done(playing) } }
        }
    }

    func stop() {
        generation.withLock { $0 += 1 }
        queue.async { self.close() }
    }

    private func isCurrent(_ mine: Int) -> Bool { generation.withLock { $0 } == mine }

    private func open(sampleRate: Double, channels: AVAudioChannelCount, render: @escaping AVAudioSourceNodeRenderBlock,
                      outputChanged: (() -> Void)?, mine: Int) -> Bool {
        guard sampleRate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else { return false }
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode(format: format, renderBlock: render)
        var started = false
        // Connecting and starting can throw an Objective-C exception while the output is changing.
        _ = Tones.caught {
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            started = (try? engine.start()) != nil
        }
        guard started else { return false }
        self.engine = engine
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                          queue: nil) { [weak self] _ in
            guard let self else { return }
            if let outputChanged {
                DispatchQueue.main.async { if self.isCurrent(mine) { outputChanged() } }
            } else {
                // Headphones connected while it plays stop the engine: start it again on the new output.
                self.queue.async {
                    guard self.isCurrent(mine), let engine = self.engine, !engine.isRunning else { return }
                    _ = Tones.caught { try? engine.start() }
                }
            }
        }
        return true
    }

    private func close() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let engine { _ = Tones.caught { engine.stop() } }
        engine = nil
    }
}
