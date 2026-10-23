// Mixer.swift — decides where each captured sound goes and processes it, in real time.
//
// Sources, one per process tap, in tap order:
//   speech  VoiceOver (and call apps set to go with speech), mono
//   others  everything not captured by another source, stereo
//   calls   call apps kept in both ears, stereo
//   app     one app with its own volume / mute / ear, stereo
//
// For each source and output channel there is a Route: how much of the
// source's left and right go to that channel. The main thread recomputes the
// routes whenever settings change; the audio thread only reads them.
//
// After mixing, each output pair (left and right of the main device, and of the
// speech device if used) goes through: one-ear mix, ear balance, volume limit.
// Before mixing, speech can get a clarity boost, and other sounds are lowered
// while VoiceOver speaks (ducking) and evened out when loud (leveler).

import CoreAudio
import Foundation

enum Mixer {
    enum Source: Equatable {
        case speech, others, calls
        case app(String)
    }

    /// Everything the routes depend on, set by the Controller.
    struct State {
        /// nil when the split is off: speech and other sounds then play in both ears.
        var split: Side?
        var layout = Layout.opposite
        var stereoOthers = false
        var speechGain: Float = 1
        var othersGain: Float = 1
        /// Silence everything except VoiceOver.
        var quietAll = false
        /// Silence VoiceOver's voice (speech on demand).
        var speechMuted = false
        var appRules: [AppRule] = []
    }

    struct Route {
        var fromLeft: Float = 0
        var fromRight: Float = 0
    }

    static let maxSources = 12
    static let maxChannels = 16
    private static let maxFrames = 16384

    // MARK: Shared with the audio thread
    // Plain Float/Int/Bool stores are effectively atomic on Apple hardware,
    // so the audio thread reads these lock-free.

    nonisolated(unsafe) private static let routes = allocate(Route(), maxSources * maxChannels)
    nonisolated(unsafe) private static let isSpeech = allocate(false, maxSources)
    nonisolated(unsafe) private static var routedSources = 0
    /// First channel of each left/right output pair.
    nonisolated(unsafe) private static let pairs = allocate(0, 2)
    nonisolated(unsafe) private static var pairCount = 1

    nonisolated(unsafe) static var duckingEnabled = false
    nonisolated(unsafe) static var duckGain: Float = 0.3
    nonisolated(unsafe) static var clarityEnabled = false
    nonisolated(unsafe) static var levelerEnabled = false
    nonisolated(unsafe) static var limiterEnabled = false
    nonisolated(unsafe) static var limiterCeiling: Float = 0.5
    /// -1 off, 0 everything in the left ear, 1 everything in the right ear.
    nonisolated(unsafe) static var oneEar = -1
    nonisolated(unsafe) static var earGainLeft: Float = 1
    nonisolated(unsafe) static var earGainRight: Float = 1
    /// Set by the audio thread when VoiceOver's speech is heard (even while silenced);
    /// cleared by whoever reads it. Used for beeps mode.
    nonisolated(unsafe) static var speechActivity = false

    // Inputs for render, filled by the Splitter's IO block.
    nonisolated(unsafe) static let sourceData = allocate(UnsafePointer<Float>?.none, maxSources)
    nonisolated(unsafe) static let sourceChannels = allocate(1, maxSources)

    // Processing state (audio thread only).
    nonisolated(unsafe) private static var currentDuck: Float = 1
    nonisolated(unsafe) private static var holdFrames = 0
    nonisolated(unsafe) private static var levelerGain: Float = 1
    nonisolated(unsafe) private static let limiterGain = allocate(Float(1), 2)
    nonisolated(unsafe) private static let clarityScratch = allocate(Float(0), maxFrames)
    nonisolated(unsafe) private static let highPass = Biquad()
    nonisolated(unsafe) private static let presence = Biquad()
    nonisolated(unsafe) private static var renderRate: Double = 48000
    nonisolated(unsafe) private static let channelBase = allocate(UnsafeMutablePointer<Float>?.none, maxChannels)
    nonisolated(unsafe) private static let channelStride = allocate(1, maxChannels)

    private static func allocate<T>(_ value: T, _ count: Int) -> UnsafeMutablePointer<T> {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        pointer.initialize(repeating: value, count: count)
        return pointer
    }

    // MARK: Main thread

    static var state = State() { didSet { recompute() } }
    /// Set by the Splitter: one entry per tap, in tap order.
    static var sources: [Source] = [] { didSet { recompute() } }
    /// Set by the Splitter: the first output channel of the speech device when
    /// speech plays on its own device, otherwise nil.
    static var speechDeviceChannel: Int? { didSet { recompute() } }
    /// Set by the Splitter when it starts.
    static var sampleRate: Double = 48000 {
        didSet {
            renderRate = sampleRate
            highPass.setHighPass(frequency: 150, sampleRate: sampleRate)
            presence.setPeaking(frequency: 3000, gainDB: 6, q: 1, sampleRate: sampleRate)
        }
    }

    private enum Ear { case left, right, both }

    private static func recompute() {
        let s = state
        let separateSpeech = speechDeviceChannel.map { $0 + 1 < maxChannels } == true && s.split != nil

        /// Routes a source to one ear or both, on the main device or at `base`.
        func place(_ ear: Ear, stereo: Bool, lean: Bool = false, base: Int = 0) -> [Int: Route] {
            switch ear {
            case .both:
                return stereo
                    ? [base: Route(fromLeft: 1), base + 1: Route(fromRight: 1)]
                    : [base: Route(fromLeft: 0.5, fromRight: 0.5), base + 1: Route(fromLeft: 0.5, fromRight: 0.5)]
            case .left, .right:
                let near = base + (ear == .left ? 0 : 1)
                let far = base + (ear == .left ? 1 : 0)
                guard lean else { return [near: Route(fromLeft: 0.5, fromRight: 0.5)] }
                // Keep the stereo image but push it toward its ear: that ear gets its
                // own channel in full, the other ear a little of its own.
                let own = ear == .left ? Route(fromLeft: 1) : Route(fromRight: 1)
                let other = ear == .left ? Route(fromRight: 0.3) : Route(fromLeft: 0.3)
                return [near: own, far: other]
            }
        }

        let speechEar: Ear = s.split.map { $0 == .left ? Ear.left : .right } ?? .both
        let othersEar: Ear = s.split.map { $0 == .left ? Ear.right : .left } ?? .both

        /// Where other sounds (and apps that follow them) go.
        func placeOthers() -> [Int: Route] {
            if s.split == nil || separateSpeech { return place(.both, stereo: true) }
            switch s.layout {
            case .opposite, .speechBoth: return place(othersEar, stereo: false, lean: s.stereoOthers)
            case .othersBoth: return place(.both, stereo: s.stereoOthers)
            }
        }

        var table = [Route](repeating: Route(), count: maxSources * maxChannels)
        var speechFlags = [Bool](repeating: false, count: maxSources)
        let othersGain = s.quietAll ? 0 : s.othersGain

        for (index, source) in sources.prefix(maxSources).enumerated() {
            var placement: [Int: Route]
            var gain: Float
            switch source {
            case .speech:
                speechFlags[index] = true
                gain = s.speechMuted ? 0 : s.speechGain
                if separateSpeech, let base = speechDeviceChannel {
                    placement = place(.both, stereo: false, base: base)
                } else if s.split == nil || s.layout == .speechBoth {
                    placement = place(.both, stereo: false)
                } else {
                    placement = place(speechEar, stereo: false)
                }
            case .others:
                placement = placeOthers()
                gain = othersGain
            case .calls:
                placement = place(.both, stereo: true)
                gain = othersGain
            case .app(let bundleID):
                let rule = s.appRules.first { $0.bundleID == bundleID } ?? AppRule(name: "", bundleID: bundleID)
                switch rule.ear {
                case .follow: placement = placeOthers()
                case .left: placement = place(.left, stereo: false)
                case .right: placement = place(.right, stereo: false)
                case .both: placement = place(.both, stereo: true)
                }
                gain = rule.muted ? 0 : othersGain * powf(10, Float(rule.volume) / 20)
            }
            for (channel, route) in placement where channel < maxChannels {
                table[index * maxChannels + channel] = Route(fromLeft: route.fromLeft * gain,
                                                             fromRight: route.fromRight * gain)
            }
        }

        for i in 0..<table.count { routes[i] = table[i] }
        for i in 0..<maxSources { isSpeech[i] = speechFlags[i] }
        pairs[0] = 0
        pairs[1] = speechDeviceChannel ?? 0
        pairCount = speechDeviceChannel == nil ? 1 : 2
        routedSources = min(sources.count, maxSources)
    }

    /// The current route from one source to one output channel (for tests).
    static func route(source: Int, channel: Int) -> Route {
        routes[source * maxChannels + channel]
    }

    /// Positive balance makes speech louder than other sounds, negative the reverse.
    /// The quieter side is attenuated and the louder side stays at full volume, so nothing clips.
    static func gains(balance: Int) -> (speech: Float, others: Float) {
        let db = Float(balance)
        return (db < 0 ? powf(10, db / 20) : 1, db > 0 ? powf(10, -db / 20) : 1)
    }

    // MARK: Real time

    /// Mixes one buffer from `sourceData` (filled for `count` sources) into `output`.
    static func render(count: Int, tapFrames: Int, output: UnsafeMutableAudioBufferListPointer) {
        let frames = min(tapFrames, maxFrames)
        let sources = min(count, routedSources)

        // Map every output channel to its memory, interleaved or not, and clear it.
        var totalChannels = 0
        for buffer in output {
            guard let data = buffer.mData else { continue }
            let channels = max(Int(buffer.mNumberChannels), 1)
            let samples = data.assumingMemoryBound(to: Float.self)
            let bufferFrames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            for i in 0..<(bufferFrames * channels) { samples[i] = 0 }
            for c in 0..<channels where totalChannels < maxChannels {
                channelBase[totalChannels] = samples + c
                channelStride[totalChannels] = channels
                totalChannels += 1
            }
        }
        guard frames > 0 else { return }

        // Speech: detect it (for ducking) and apply the clarity boost.
        var peak: Float = 0
        var clarityFor = -1
        for s in 0..<sources where isSpeech[s] {
            guard let data = sourceData[s] else { continue }
            let stride = sourceChannels[s]
            for f in 0..<frames { peak = max(peak, abs(data[f * stride])) }
            if clarityEnabled && clarityFor < 0 {
                clarityFor = s
                for f in 0..<frames { clarityScratch[f] = presence.process(highPass.process(data[f * stride])) }
            }
        }

        // Ducking: lower other sounds while speech plays, hold briefly after it stops.
        if peak > 0.002 {
            holdFrames = Int(renderRate * 0.4)
            speechActivity = true
        } else {
            holdFrames = max(0, holdFrames - frames)
        }
        let duckTarget: Float = duckingEnabled && holdFrames > 0 ? duckGain : 1
        let duckStart = currentDuck
        currentDuck = smooth(currentDuck, toward: duckTarget, frames: frames,
                             seconds: duckTarget < currentDuck ? 0.05 : 0.3)

        // Leveler: turn loud other sounds down (3:1 above -26 dBFS), recover slowly.
        let levelStart = levelerGain
        if levelerEnabled {
            var sum: Float = 0
            var count = 0
            for s in 0..<sources where !isSpeech[s] {
                guard let data = sourceData[s] else { continue }
                let stride = sourceChannels[s]
                for f in 0..<frames { let x = data[f * stride]; sum += x * x }
                count += frames
            }
            let level = 10 * log10f(max(sum / Float(max(count, 1)), 1e-10))
            let threshold: Float = -26
            let target = level > threshold ? powf(10, -(level - threshold) * (2.0 / 3.0) / 20) : 1
            levelerGain = smooth(levelerGain, toward: target, frames: frames,
                                 seconds: target < levelerGain ? 0.2 : 1.5)
        } else {
            levelerGain = 1
        }
        let levelEnd = levelerGain
        let duckEnd = currentDuck

        // Mix.
        for s in 0..<sources {
            guard let data = sourceData[s] else { continue }
            let stride = sourceChannels[s]
            let speech = isSpeech[s]
            for channel in 0..<totalChannels {
                let route = routes[s * maxChannels + channel]
                guard route.fromLeft != 0 || route.fromRight != 0, let out = channelBase[channel] else { continue }
                let outStride = channelStride[channel]
                for f in 0..<frames {
                    let left = s == clarityFor ? clarityScratch[f] : data[f * stride]
                    let right = stride > 1 ? data[f * stride + 1] : left
                    var sample = route.fromLeft * left + route.fromRight * right
                    if !speech {
                        let t = Float(f) / Float(frames)
                        sample *= (duckStart + (duckEnd - duckStart) * t) * (levelStart + (levelEnd - levelStart) * t)
                    }
                    out[f * outStride] += sample
                }
            }
        }

        // Per ear pair: one-ear mix, ear balance, volume limit, and a hard safety clamp.
        let release = 1 - expf(-1 / Float(renderRate * 0.15))
        for p in 0..<pairCount {
            let l = pairs[p], r = pairs[p] + 1
            guard r < totalChannels, let left = channelBase[l], let right = channelBase[r] else { continue }
            let ls = channelStride[l], rs = channelStride[r]
            var gain = limiterGain[p]
            for f in 0..<frames {
                var a = left[f * ls], b = right[f * rs]
                if oneEar >= 0 {
                    let mono = (a + b) * 0.7
                    a = oneEar == 0 ? mono : 0
                    b = oneEar == 1 ? mono : 0
                }
                a *= earGainLeft
                b *= earGainRight
                if limiterEnabled {
                    let level = max(abs(a), abs(b))
                    let target = level > limiterCeiling ? limiterCeiling / level : 1
                    gain = min(target, gain + (1 - gain) * release)
                    a *= gain
                    b *= gain
                }
                left[f * ls] = max(-1, min(1, a))
                right[f * rs] = max(-1, min(1, b))
            }
            limiterGain[p] = gain
        }
    }

    /// Moves `value` toward `target` over roughly `seconds`, for one buffer of `frames`.
    private static func smooth(_ value: Float, toward target: Float, frames: Int, seconds: Double) -> Float {
        value + (target - value) * min(1, Float(Double(frames) / (renderRate * seconds)))
    }
}

/// A standard second-order filter (RBJ audio EQ cookbook).
final class Biquad {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    func setHighPass(frequency: Double, sampleRate: Double, q: Double = 0.707) {
        let w = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        set(b0: (1 + cos(w)) / 2 / a0, b1: -(1 + cos(w)) / a0, b2: (1 + cos(w)) / 2 / a0,
            a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    func setPeaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha / a
        set(b0: (1 + alpha * a) / a0, b1: -2 * cos(w) / a0, b2: (1 - alpha * a) / a0,
            a1: -2 * cos(w) / a0, a2: (1 - alpha / a) / a0)
    }

    private func set(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = Float(b0); self.b1 = Float(b1); self.b2 = Float(b2); self.a1 = Float(a1); self.a2 = Float(a2)
    }

    func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}
