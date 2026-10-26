// HearingProfile.swift — shapes each ear's sound to a hearing loss, like a simple hearing
// aid fitting. The hearing loss at six frequencies, per ear, comes from an audiogram (typed
// in from a hearing test) or from the quick listening test here. Each band is then boosted
// by about half the loss (the "half-gain rule"), up to 25 dB. Everything is done on the Mac.
// This isn't a medical hearing test: the listening test measures your hearing through your
// own headphones, which shows how your ears and frequencies differ, not your hearing level.

import AVFoundation
import SwiftUI

enum HearingProfile {
    /// The audiogram frequencies, in Hz.
    static let frequencies: [Double] = [250, 500, 1000, 2000, 4000, 8000]
    static let maxGain = 25.0

    /// Six losses in dB (0 to 90), or six zeros when missing or malformed.
    static func valid(_ losses: [Double]?) -> [Double] {
        guard let losses, losses.count == frequencies.count else { return Array(repeating: 0, count: frequencies.count) }
        return losses.map { min(90, max(0, $0.isFinite ? $0 : 0)) }
    }

    /// The boost for each band: half the loss above 20 dB (normal hearing), up to 25 dB.
    static func gains(for losses: [Double]) -> [Double] {
        valid(losses).map { min(maxGain, max(0, ($0 - 20) / 2)) }
    }

    /// "500 Hz", "2 kHz".
    static func name(_ frequency: Double) -> String {
        frequency >= 1000 ? String(localized: "\(Int(frequency / 1000)) kHz") : String(localized: "\(Int(frequency)) Hz")
    }

    /// Losses from the listening test's quietest levels heard (dBFS), relative to the best
    /// band: the band heard best counts as normal hearing, and each band heard only louder
    /// counts as that much loss.
    static func losses(fromThresholds thresholds: [Double], best: Double) -> [Double] {
        valid(thresholds.map { $0 - best })
    }

    /// A short spoken summary of a profile.
    static func summary(left: [Double], right: [Double]) -> String {
        func describe(_ losses: [Double]) -> String {
            let worst = zip(frequencies, losses).filter { $0.1 > 20 }.map { name($0.0) }
            return worst.isEmpty ? String(localized: "no boost needed")
                                 : String(localized: "boosted at \(ListFormatter.localizedString(byJoining: worst))")
        }
        return String(localized: "Left ear: \(describe(left)). Right ear: \(describe(right)).")
    }
}

/// The quick listening test: a tone in one ear grows louder until you say you hear it.
@MainActor
final class HearingTest: ObservableObject {
    static let shared = HearingTest()

    @Published private(set) var running = false
    @Published private(set) var step = ""
    @Published private(set) var progress = 0
    var total: Int { HearingProfile.frequencies.count * 2 }

    private var engine: AVAudioEngine?
    private var queue: [(ear: Int, frequency: Double)] = []
    private var current: (ear: Int, frequency: Double)?
    private var level = -80.0
    private var results: [Int: [Double: Double]] = [:]
    private var timer: Timer?
    /// Read on the audio thread: what to play now.
    nonisolated(unsafe) private static var tone: (frequency: Double, amplitude: Float, ear: Int) = (1000, 0, 0)

    func start() {
        guard !running else { return }
        queue = [0, 1].flatMap { ear in HearingProfile.frequencies.map { (ear, $0) } }
        results = [:]
        progress = 0
        running = true
        guard startEngine() else {
            running = false
            return Announcer.say(String(localized: "The listening test couldn't play sound."))
        }
        Announcer.say(String(localized: "Listening test. Put on headphones and turn the volume to a comfortable level. You'll hear tones in one ear at a time, getting louder. Press Return as soon as you hear each one. Press Escape to stop."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in self?.next() }
    }

    func heard() {
        guard running, let current else { return }
        results[current.ear, default: [:]][current.frequency] = level
        Tones.play(.status)
        next()
    }

    func stop(saying text: String? = String(localized: "Listening test stopped.")) {
        timer?.invalidate()
        timer = nil
        Self.tone.amplitude = 0
        engine?.stop()
        engine = nil
        running = false
        current = nil
        step = ""
        if let text { Announcer.say(text) }
    }

    private func next() {
        guard running else { return }
        timer?.invalidate()
        Self.tone.amplitude = 0
        guard !queue.isEmpty else { return finish() }
        let item = queue.removeFirst()
        current = item
        progress = total - queue.count
        level = -80
        let ear = item.ear == 0 ? String(localized: "Left ear") : String(localized: "Right ear")
        step = "\(ear), \(HearingProfile.name(item.frequency))"
        // A pause first, so the tone isn't masked by the spoken step.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.running, self.current?.frequency == item.frequency, self.current?.ear == item.ear else { return }
            Self.tone = (item.frequency, Float(pow(10, self.level / 20)), item.ear)
            // Louder by 5 dB a second, up to the loudest safe level.
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    self.level += 5
                    if self.level > -10 { return self.heard() } // Not heard even loud: count it as loud.
                    Self.tone.amplitude = Float(pow(10, self.level / 20))
                }
            }
        }
    }

    private func finish() {
        let all = results.values.flatMap(\.values)
        let best = all.min() ?? -80
        let frequencies = HearingProfile.frequencies
        let left = HearingProfile.losses(fromThresholds: frequencies.map { results[0]?[$0] ?? best }, best: best)
        let right = HearingProfile.losses(fromThresholds: frequencies.map { results[1]?[$0] ?? best }, best: best)
        let preferences = Preferences.shared
        preferences.hearingLeft = left
        preferences.hearingRight = right
        preferences.hearingProfileOn = true
        Tones.play(.device)
        stop(saying: String(localized: "Listening test done. Your hearing profile is on. \(HearingProfile.summary(left: left, right: right))"))
    }

    private func startEngine() -> Bool {
        let engine = AVAudioEngine()
        let output = engine.outputNode.outputFormat(forBus: 0)
        guard output.sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: 2) else { return false }
        let rate = output.sampleRate
        nonisolated(unsafe) var phase = 0.0
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let tone = HearingTest.tone
            let step = 2 * Double.pi * tone.frequency / rate
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * tone.amplitude
                phase += step
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                for (channel, buffer) in buffers.enumerated() {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = channel == tone.ear ? sample : 0
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return false }
        self.engine = engine
        return true
    }
}

struct HearingProfileView: View {
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var test = HearingTest.shared

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Use my hearing profile"), isOn: $preferences.hearingProfileOn)
                Text(String(localized: "Boosts the frequencies you hear less well, separately for each ear, for VoiceOver and all other sound. It isn't a medical hearing test or a hearing aid."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Listening test")) {
                if test.running {
                    Text(String(localized: "Tone \(test.progress) of \(test.total): \(test.step)"))
                    Button(String(localized: "I Hear It")) { test.heard() }
                        .keyboardShortcut(.defaultAction)
                    Button(String(localized: "Stop the Test")) { test.stop() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(String(localized: "Start the Listening Test")) { test.start() }
                    Text(String(localized: "Takes about two minutes with headphones on. It replaces the numbers below."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "Hearing loss in dB, from an audiogram")) {
                ForEach(Array(HearingProfile.frequencies.enumerated()), id: \.offset) { index, frequency in
                    Stepper(String(localized: "Left ear, \(HearingProfile.name(frequency)): \(Int(preferences.hearingLeft[index])) dB"),
                            value: $preferences.hearingLeft[index], in: 0...90, step: 5)
                    Stepper(String(localized: "Right ear, \(HearingProfile.name(frequency)): \(Int(preferences.hearingRight[index])) dB"),
                            value: $preferences.hearingRight[index], in: 0...90, step: 5)
                }
                Button(String(localized: "Reset to No Loss")) {
                    preferences.hearingLeft = HearingProfile.valid(nil)
                    preferences.hearingRight = HearingProfile.valid(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onDisappear { if test.running { test.stop() } }
    }
}
