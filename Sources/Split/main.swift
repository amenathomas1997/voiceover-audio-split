// VOAudioSplit — JAWS-style audio splitting for VoiceOver.
//
// Puts VoiceOver speech in one ear and every other sound on the Mac in the
// other ear. Uses Core Audio process taps (macOS 14.2+):
//   * tap 1: mono mixdown of the speech processes (VoiceOver + speech synth)
//   * tap 2: mono mixdown of everything else
// Both taps mute the original audio while tapped, and the mixed result is
// played through the current default output device. If this app quits or
// crashes, the taps go away and audio returns to normal automatically.
//
// Usage:
//   VOAudioSplit left    speech in left ear, other sounds in right ear
//   VOAudioSplit right   speech in right ear, other sounds in left ear
//   VOAudioSplit         use the last side saved in the settings folder
//   VOAudioSplit --list  print the audio processes Core Audio can see
//
// Settings live in ~/Library/Application Support/VOAudioSplit/:
//   mode     off | left | right   (written here on launch, by the scripts on change)
//   side     left | right         (last side used; what a login launch restores)
//   balance  decibels; positive makes speech louder than other sounds,
//            negative makes other sounds louder. Re-read on SIGHUP.

import AppKit
import CoreAudio
import Foundation

// MARK: - Core Audio property helpers

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readValue<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T) -> T {
    var addr = address(selector)
    var result = value
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result)
    return status == noErr ? result : value
}

func readArray<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, of _: T.Type) -> [T] {
    var addr = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<T>.stride
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { pointer.deallocate() }
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

struct AudioProcess {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String
}

func audioProcesses() -> [AudioProcess] {
    readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
        .map { object in
            AudioProcess(object: object,
                         pid: readValue(object, kAudioProcessPropertyPID, default: pid_t(-1)),
                         bundleID: readString(object, kAudioProcessPropertyBundleID) ?? "")
        }
}

/// Processes whose audio counts as "screen reader speech".
func isSpeechProcess(_ process: AudioProcess) -> Bool {
    if process.bundleID == "com.apple.VoiceOver" { return true }
    if process.bundleID.hasPrefix("com.apple.speech.") { return true }
    if process.bundleID.contains("SpeechSynthesis") { return true }
    // Fall back to the executable path for processes without a bundle ID.
    let path = processPath(process.pid)
    return path.hasSuffix("/VoiceOver") || path.contains("SpeechSynthesisServerXPC")
}

func processPath(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : ""
}

func defaultOutputDevice() -> AudioDeviceID {
    readValue(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
              default: AudioDeviceID(kAudioObjectUnknown))
}

// MARK: - Settings

let settingsFolder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/VOAudioSplit")

func readSetting(_ name: String) -> String? {
    let url = settingsFolder.appendingPathComponent(name)
    return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func writeSetting(_ name: String, _ value: String) {
    try? FileManager.default.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
    try? (value + "\n").write(to: settingsFolder.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

/// Linear gains read by the real-time render block. Plain Float stores are
/// effectively atomic on Apple hardware, so the audio thread reads them lock-free.
enum Gains {
    nonisolated(unsafe) static var speech: Float = 1
    nonisolated(unsafe) static var others: Float = 1

    /// Loads `balance` and turns it into gains: the quieter side is attenuated,
    /// the louder side stays at full volume so nothing ever clips.
    static func load() {
        let balance = Float(readSetting("balance") ?? "") ?? 0
        speech = balance < 0 ? powf(10, balance / 20) : 1
        others = balance > 0 ? powf(10, -balance / 20) : 1
        log("Balance \(balance) dB (speech gain \(speech), other sounds gain \(others)).")
    }
}

// MARK: - Splitter

final class Splitter {
    enum Side: String { case left, right }

    let speechSide: Side
    private let queue = DispatchQueue(label: "VOAudioSplit.io", qos: .userInteractive)

    private var speechTap = AudioObjectID(kAudioObjectUnknown)
    private var othersTap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    /// What the current graph was built for, so we only rebuild on real changes.
    private var builtSpeechObjects: Set<AudioObjectID> = []
    private var builtExcludedObjects: Set<AudioObjectID> = []
    private var builtOutputDevice = AudioDeviceID(kAudioObjectUnknown)

    init(speechSide: Side) { self.speechSide = speechSide }

    func start() {
        rebuildIfNeeded()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { [weak self] _, _ in
                // Debounce: process lists change in bursts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.rebuildIfNeeded() }
            }
        }
    }

    func rebuildIfNeeded() {
        let processes = audioProcesses()
        let speech = Set(processes.filter(isSpeechProcess).map(\.object))
        let me = processes.filter { $0.pid == getpid() }.map(\.object)
        let excluded = speech.union(me)
        let output = defaultOutputDevice()

        // Never tap our own output: that would feed back.
        if speech == builtSpeechObjects && excluded == builtExcludedObjects && output == builtOutputDevice
            && aggregate != kAudioObjectUnknown {
            return
        }
        // The aggregate device we create shows up as the "default" briefly on some systems; ignore it.
        if output == aggregate { return }

        teardown()
        guard !speech.isEmpty else {
            log("No VoiceOver speech process found yet; waiting for VoiceOver to speak.")
            builtSpeechObjects = speech
            builtExcludedObjects = excluded
            builtOutputDevice = output
            return
        }
        do {
            try build(speech: Array(speech), excluded: Array(excluded), output: output)
            builtSpeechObjects = speech
            builtExcludedObjects = excluded
            builtOutputDevice = output
            log("Split active: speech \(speechSide.rawValue), other sounds \(speechSide == .left ? "right" : "left").")
        } catch {
            log("Could not start audio split: \(error)")
            teardown()
        }
    }

    private func build(speech: [AudioObjectID], excluded: [AudioObjectID], output: AudioDeviceID) throws {
        guard let outputUID = readString(output, kAudioDevicePropertyDeviceUID) else {
            throw SplitError("no default output device")
        }

        let speechDescription = CATapDescription(monoMixdownOfProcesses: speech)
        speechDescription.name = "VOAudioSplit speech"
        speechDescription.isPrivate = true
        speechDescription.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(speechDescription, &speechTap), "create speech tap")

        let othersDescription = CATapDescription(monoGlobalTapButExcludeProcesses: excluded)
        othersDescription.name = "VOAudioSplit other sounds"
        othersDescription.isPrivate = true
        othersDescription.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(othersDescription, &othersTap), "create other-sounds tap")

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VOAudioSplit",
            kAudioAggregateDeviceUIDKey: "VOAudioSplit-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            // Order matters: the IOProc reads speech first, other sounds second.
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: speechDescription.uuid.uuidString, kAudioSubTapDriftCompensationKey: true],
                [kAudioSubTapUIDKey: othersDescription.uuid.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "create aggregate device")

        let speechOnLeft = speechSide == .left
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, output, _ in
            Splitter.render(input: input, output: output, speechOnLeft: speechOnLeft)
        }, "create IO proc")
        try check(AudioDeviceStart(aggregate, ioProc), "start audio")
    }

    /// Real-time render: the last two input buffers are the two mono taps
    /// (any input streams of the output hardware itself come first).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               speechOnLeft: Bool) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        var speech: UnsafePointer<Float>?
        var others: UnsafePointer<Float>?
        var tapFrames = Int.max
        if inputs.count >= 2 {
            for (index, slot) in [(inputs.count - 2, 0), (inputs.count - 1, 1)] {
                let buffer = inputs[index]
                guard let data = buffer.mData else { continue }
                let channels = max(Int(buffer.mNumberChannels), 1)
                tapFrames = min(tapFrames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels)
                let samples = UnsafePointer(data.assumingMemoryBound(to: Float.self))
                if slot == 0 { speech = samples } else { others = samples }
            }
        }

        // Walk output channels across all buffers (interleaved or not).
        var channel = 0
        for buffer in outputs {
            guard let data = buffer.mData else { continue }
            let channels = max(Int(buffer.mNumberChannels), 1)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            let out = data.assumingMemoryBound(to: Float.self)
            for c in 0..<channels {
                let source: UnsafePointer<Float>?
                let isSpeech = (channel + c == 0) == speechOnLeft
                switch channel + c {
                case 0, 1: source = isSpeech ? speech : others
                default: source = nil
                }
                let gain = isSpeech ? Gains.speech : Gains.others
                for frame in 0..<frames {
                    out[frame * channels + c] = (source != nil && frame < tapFrames) ? source![frame] * gain : 0
                }
            }
            channel += channels
        }
    }

    func teardown() {
        if aggregate != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if speechTap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(speechTap) }
        if othersTap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(othersTap) }
        ioProc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        speechTap = AudioObjectID(kAudioObjectUnknown)
        othersTap = AudioObjectID(kAudioObjectUnknown)
    }
}

struct SplitError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw SplitError("\(what) failed (OSStatus \(status))") }
}

func log(_ message: String) {
    FileHandle.standardError.write(("VOAudioSplit: " + message + "\n").data(using: .utf8)!)
}

// MARK: - Entry point

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--list") {
    for process in audioProcesses() {
        let marker = isSpeechProcess(process) ? "SPEECH" : "      "
        print("\(marker)  pid \(process.pid)  \(process.bundleID.isEmpty ? processPath(process.pid) : process.bundleID)")
    }
    exit(0)
}

let side = arguments.compactMap(Splitter.Side.init(rawValue:)).first
    ?? readSetting("side").flatMap(Splitter.Side.init(rawValue:))
    ?? .left
writeSetting("mode", side.rawValue)
writeSetting("side", side.rawValue)
Gains.load()
let splitter = Splitter(speechSide: side)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { splitter.start() }
    func applicationWillTerminate(_ notification: Notification) { splitter.teardown() }
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { splitter.teardown(); exit(0) }
    source.resume()
    signalSources.append(source)
}
signal(SIGHUP, SIG_IGN)
let reloadSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
reloadSource.setEventHandler { Gains.load() }
reloadSource.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
