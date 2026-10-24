// Splitter.swift — captures VoiceOver speech, other sounds, call apps and apps
// with their own settings separately, and plays them back through the Mixer.
//
// Uses Core Audio process taps (macOS 14.2+), one per Mixer source:
//   * speech: mono mixdown of VoiceOver + speech synth (plus call apps when
//             they are set to go with speech)
//   * other sounds: stereo mixdown of everything not captured by another tap
//   * calls: call apps kept in both ears
//   * one tap per app with its own volume, mute or ear
// The taps mute the original audio while tapped, and the mix is played through
// a private aggregate device: the default output, plus the speech device when
// speech plays on its own device. When capture stops (or the app quits), the
// taps go away and audio returns to normal.

import AppKit
import CoreAudio
import Foundation
import os

// MARK: - Core Audio property helpers

func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readValue<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   default value: T) -> T {
    var addr = address(selector)
    var result = value
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result)
    return status == noErr ? result : value
}

func readArray<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   of _: T.Type) -> [T] {
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

let logger = Logger(subsystem: "com.fullcircleat.VoiceOverAudioSplit", category: "audio")

func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}

// MARK: - Processes

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
    process.bundleID == "com.apple.VoiceOver"
        || process.bundleID.hasPrefix("com.apple.speech.")
        || process.bundleID.contains("SpeechSynthesis")
}

// MARK: - Devices

struct OutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

func defaultOutputDevice() -> AudioDeviceID {
    readValue(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
              default: AudioDeviceID(kAudioObjectUnknown))
}

func outputChannelCount(_ device: AudioDeviceID) -> Int {
    channelCount(device, scope: kAudioObjectPropertyScopeOutput)
}

func channelCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

/// Real output devices (speakers, headphones, AirPods…). Virtual devices such as
/// ZoomAudioDevice and aggregate devices (including our own) are left out: nothing
/// you can hear plays through them, so switching to one would make the Mac go silent.
func outputDevices() -> [OutputDevice] {
    readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, of: AudioDeviceID.self)
        .compactMap { device in
            let transport = readValue(device, kAudioDevicePropertyTransportType, default: UInt32(0))
            guard transport != kAudioDeviceTransportTypeVirtual, transport != kAudioDeviceTransportTypeAggregate,
                  outputChannelCount(device) > 0,
                  let uid = readString(device, kAudioDevicePropertyDeviceUID), !uid.hasPrefix("VOAudioSplit"),
                  let name = readString(device, kAudioObjectPropertyName) else { return nil }
            return OutputDevice(id: device, uid: uid, name: name)
        }
}

func deviceName(uid: String) -> String? {
    outputDevices().first { $0.uid == uid }?.name
}

// MARK: - Splitter

struct SplitConfiguration: Equatable {
    /// Output device UID for speech; nil plays speech on the same device as other sounds.
    var speechDeviceUID: String?
    var callMode: CallMode
    var callAppPrefixes: [String]
    /// Bundle IDs of apps with their own volume, mute or ear; each gets its own tap.
    var appRuleIDs: [String]
}

/// Whether an audio process belongs to the app with this bundle ID. Helper
/// processes often share the app's prefix (com.google.Chrome.helper), or were
/// started by the app (us.zoom.xos starts us.zoom.caphost). Safari's audio
/// comes from the shared WebKit process.
func belongs(_ process: AudioProcess, to bundleID: String, appPIDs: Set<pid_t> = []) -> Bool {
    if !process.bundleID.isEmpty && process.bundleID.hasPrefix(bundleID) { return true }
    if bundleID == "com.apple.Safari" && process.bundleID.hasPrefix("com.apple.WebKit") { return true }
    var pid = process.pid
    for _ in 0..<4 where pid > 1 {
        if appPIDs.contains(pid) { return true }
        pid = parentPID(of: pid)
    }
    return false
}

/// Process IDs of the running copies of an app.
func pids(of bundleID: String) -> Set<pid_t> {
    Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
}

private func parentPID(of pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
    return info.kp_eproc.e_ppid
}

final class Splitter {
    /// Posted on the main thread when capture can't start, so the user is told.
    static let failed = Notification.Name("VoiceOverAudioSplit.splitFailed")

    private let configuration: SplitConfiguration
    private let queue = DispatchQueue(label: "VOAudioSplit.io", qos: .userInteractive)

    private var taps: [AudioObjectID] = []
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    /// What the current graph was built for, so we only rebuild on real changes.
    private struct Plan: Equatable {
        var speech: Set<AudioObjectID>
        var calls: Set<AudioObjectID>
        /// Bundle ID and processes for each app with its own rule that is playing.
        var apps: [String: Set<AudioObjectID>]
        var excluded: Set<AudioObjectID>
        var output: AudioDeviceID
        var speechDevice: AudioDeviceID?
    }
    private var built: Plan?
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    init(configuration: SplitConfiguration) { self.configuration = configuration }

    func start() {
        failedPlan = nil
        rebuildIfNeeded()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDevices] {
            var addr = address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRebuild() }
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            listeners.append((selector, block))
        }
    }

    private var pendingRebuild: DispatchWorkItem?
    private var pendingForce = false
    /// The last setup that couldn't be built.
    private var failedPlan: Plan?

    /// Process and device lists change in bursts (connecting AirPods fires several
    /// changes in a second): wait for them to settle, then rebuild once.
    private func scheduleRebuild(force: Bool = false) {
        pendingRebuild?.cancel()
        // A forced rebuild (the device changed shape) isn't lost to an ordinary one right after it.
        pendingForce = pendingForce || force
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingForce { self.built = nil; self.failedPlan = nil }
            self.pendingForce = false
            self.rebuildIfNeeded()
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Listeners on the output device itself: its channel count or sample rate can change
    /// without it changing (AirPods switch to a mono, lower-rate mode during calls).
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    /// Rebuilds only on a real change: building can itself make the device report a
    /// change, which mustn't start a loop.
    private func watchDevice(_ device: AudioObjectID) {
        func shape() -> (Int, Float64) {
            (outputChannelCount(device), readValue(device, kAudioDevicePropertyNominalSampleRate, default: Float64(0)))
        }
        let builtShape = shape()
        for selector in [kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyNominalSampleRate] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeWildcard,
                                                  mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                if shape() != builtShape { self?.scheduleRebuild(force: true) }
            }
            if AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block) == noErr {
                deviceListeners.append((device, selector, block))
            }
        }
    }

    private func unwatchDevices() {
        for (device, selector, block) in deviceListeners {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeWildcard,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
    }

    /// Stops capturing and returns audio to normal.
    func stop() {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (selector, block) in listeners {
            var addr = address(selector)
            AudioObjectRemovePropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        }
        listeners.removeAll()
        teardown()
        Mixer.sources = []
        Mixer.speechDeviceChannel = nil
    }

    private func plan() -> Plan {
        let processes = audioProcesses()
        var apps: [String: Set<AudioObjectID>] = [:]
        // A process in two apps' taps would be heard twice: the first rule that matches it wins.
        var claimed = Set<AudioObjectID>()
        // Leave room for the speech, other-sounds and calls taps.
        for bundleID in configuration.appRuleIDs.prefix(Mixer.maxSources - 3) {
            let appPIDs = pids(of: bundleID)
            let matches = Set(processes.filter { belongs($0, to: bundleID, appPIDs: appPIDs) && !isSpeechProcess($0) }.map(\.object))
                .subtracting(claimed)
            if !matches.isEmpty { apps[bundleID] = matches }
            claimed.formUnion(matches)
        }
        let inApps = apps.values.reduce(into: Set<AudioObjectID>()) { $0.formUnion($1) }

        // Call apps are listed by prefix; collect the running apps they cover.
        let callPIDs = Set(NSWorkspace.shared.runningApplications.filter { app in
            configuration.callAppPrefixes.contains { app.bundleIdentifier?.hasPrefix($0) == true }
        }.map(\.processIdentifier))
        var calls = Set(processes.filter { candidate in
            configuration.callAppPrefixes.contains { belongs(candidate, to: $0, appPIDs: callPIDs) }
        }.map(\.object)).subtracting(inApps)
        let speech = Set(processes.filter(isSpeechProcess).map(\.object))
        // Calls set to go with speech get their own tap, so silencing VoiceOver doesn't silence the call.
        if configuration.callMode == .split { calls = [] }

        // Never tap our own output (tones, the mix itself): that would feed back.
        let me = Set(processes.filter { $0.pid == getpid() }.map(\.object))
        let excluded = speech.union(me).union(calls).union(inApps)

        let output = defaultOutputDevice()
        let speechDevice = configuration.speechDeviceUID
            .flatMap { uid in outputDevices().first { $0.uid == uid }?.id }
            .flatMap { $0 == output ? nil : $0 }
        return Plan(speech: speech, calls: calls, apps: apps, excluded: excluded, output: output,
                    speechDevice: speechDevice)
    }

    func rebuildIfNeeded() {
        let plan = plan()
        if plan == built && aggregate != kAudioObjectUnknown { return }
        // The same setup just failed: wait for something to change rather than retry in a loop.
        if plan == failedPlan { return }
        // Our aggregate device can briefly show up as the default; ignore it.
        if plan.output == aggregate { return }

        teardown()
        built = plan
        guard !plan.speech.isEmpty else {
            log("No VoiceOver speech process found yet; waiting for VoiceOver to speak.")
            return
        }
        do {
            try build(plan)
            failedPlan = nil
            log("Audio active: \(plan.apps.count) app(s) with their own settings\(plan.speechDevice != nil ? ", two devices" : "").")
        } catch {
            log("Could not start audio: \(error)")
            teardown()
            failedPlan = plan
            NotificationCenter.default.post(name: Splitter.failed, object: nil)
        }
    }

    private func makeTap(_ description: CATapDescription, name: String) throws -> String {
        description.name = "VOAudioSplit \(name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create \(name) tap")
        taps.append(tap)
        return description.uuid.uuidString
    }

    private func build(_ plan: Plan) throws {
        guard let outputUID = readString(plan.output, kAudioDevicePropertyDeviceUID) else {
            throw SplitError("no default output device")
        }

        // Tap order is source order: the IOProc reads the taps' buffers in this order.
        var sources: [Mixer.Source] = [.speech, .others]
        var tapUIDs = [
            try makeTap(CATapDescription(monoMixdownOfProcesses: Array(plan.speech)), name: "speech"),
            try makeTap(CATapDescription(stereoGlobalTapButExcludeProcesses: Array(plan.excluded)), name: "other sounds"),
        ]
        if !plan.calls.isEmpty {
            tapUIDs.append(try makeTap(CATapDescription(stereoMixdownOfProcesses: Array(plan.calls)), name: "calls"))
            sources.append(configuration.callMode == .withSpeech ? .callsWithSpeech : .calls)
        }
        for (bundleID, objects) in plan.apps.sorted(by: { $0.key < $1.key }) {
            tapUIDs.append(try makeTap(CATapDescription(stereoMixdownOfProcesses: Array(objects)), name: bundleID))
            sources.append(.app(bundleID))
        }

        // Main device first, so its channels come first in the output buffers.
        var subDevices: [[String: Any]] = [[kAudioSubDeviceUIDKey: outputUID]]
        if let speechDevice = plan.speechDevice, let speechUID = readString(speechDevice, kAudioDevicePropertyDeviceUID) {
            subDevices.append([kAudioSubDeviceUIDKey: speechUID, kAudioSubDeviceDriftCompensationKey: true])
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VOAudioSplit",
            kAudioAggregateDeviceUIDKey: "VOAudioSplit-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: tapUIDs.map {
                [kAudioSubTapUIDKey: $0, kAudioSubTapDriftCompensationKey: true]
            },
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "create aggregate device")

        Mixer.sampleRate = readValue(aggregate, kAudioDevicePropertyNominalSampleRate, default: Float64(48000))
        Mixer.mainChannels = outputChannelCount(plan.output)
        Mixer.speechDeviceChannel = subDevices.count > 1 ? outputChannelCount(plan.output) : nil
        Mixer.sources = sources
        watchDevice(plan.output)
        if let speechDevice = plan.speechDevice { watchDevice(speechDevice) }

        let tapCount = sources.count
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, output, _ in
            Splitter.render(input: input, output: output, tapCount: tapCount)
        }, "create IO proc")
        try check(AudioDeviceStart(aggregate, ioProc), "start audio")
    }

    /// Real-time render: the last `tapCount` input buffers are the taps, in source
    /// order (any input streams of the output hardware itself, such as an AirPods
    /// mic, come first).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>, tapCount: Int) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let count = min(tapCount, inputs.count, Mixer.maxSources)
        var frames = Int.max
        for i in 0..<count {
            let buffer = inputs[inputs.count - count + i]
            let channels = max(Int(buffer.mNumberChannels), 1)
            Mixer.sourceData[i] = buffer.mData.map { UnsafePointer($0.assumingMemoryBound(to: Float.self)) }
            Mixer.sourceChannels[i] = channels
            frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels)
        }
        Mixer.render(count: count, tapFrames: count > 0 ? frames : 0, output: UnsafeMutableAudioBufferListPointer(output))
    }

    private func teardown() {
        unwatchDevices()
        // Nothing is captured until the next build sets these again.
        Mixer.sources = []
        Mixer.speechDeviceChannel = nil
        if aggregate != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        for tap in taps { AudioHardwareDestroyProcessTap(tap) }
        taps.removeAll()
        ioProc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
    }
}

struct SplitError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw SplitError("\(what) failed (OSStatus \(status))") }
}
