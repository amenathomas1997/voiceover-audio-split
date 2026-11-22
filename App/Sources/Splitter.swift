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

/// Core Audio property listeners that can really be taken away again.
///
/// The block form (`AudioObjectAddPropertyListenerBlock`) can't be removed from Swift:
/// every call wraps the closure in a new block, so `AudioObjectRemovePropertyListenerBlock`
/// matches nothing, and still reports success. Each rebuild of the split then left its
/// device listeners behind, still firing, for as long as the app ran. This uses the
/// function form, which removes by function and context; the context is a number, not a
/// pointer, so a call that arrives late finds nothing rather than freed memory.
enum AudioListeners {
    struct Token {
        fileprivate let id: Int
        fileprivate let object: AudioObjectID
        fileprivate let address: AudioObjectPropertyAddress
    }

    private static let handlers = OSAllocatedUnfairLock(initialState: (next: 1, byID: [Int: () -> Void]()))

    private static let proc: AudioObjectPropertyListenerProc = { _, _, _, context in
        let id = Int(bitPattern: context)
        // Run on the main thread, and only if it's still wanted by then.
        DispatchQueue.main.async {
            handlers.withLockUnchecked { $0.byID[id] }?()
        }
        return noErr
    }

    /// Calls `handler` on the main thread when the property changes, until the token is removed.
    static func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, handler: @escaping () -> Void) -> Token? {
        let id = handlers.withLockUnchecked { state -> Int in
            let id = state.next
            state.next += 1
            state.byID[id] = handler
            return id
        }
        var address = address
        guard AudioObjectAddPropertyListener(object, &address, proc, UnsafeMutableRawPointer(bitPattern: id)) == noErr else {
            handlers.withLockUnchecked { $0.byID[id] = nil }
            return nil
        }
        return Token(id: id, object: object, address: address)
    }

    static func remove(_ token: Token) {
        var address = token.address
        AudioObjectRemovePropertyListener(token.object, &address, proc, UnsafeMutableRawPointer(bitPattern: token.id))
        handlers.withLockUnchecked { $0.byID[token.id] = nil }
    }

    /// How many are in place (for the tests).
    static var count: Int { handlers.withLockUnchecked { $0.byID.count } }
}

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

/// The two channels a device plays stereo on, counted from 0. Usually its first two; an
/// audio interface with more outputs can be set to another pair in Audio MIDI Setup.
func stereoChannels(_ device: AudioDeviceID) -> (left: Int, right: Int) {
    var addr = address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioObjectPropertyScopeOutput)
    var pair: [UInt32] = [1, 2]
    var size = UInt32(MemoryLayout<UInt32>.size * 2)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &pair) == noErr else { return (0, 1) }
    return validStereo(left: Int(pair[0]), right: Int(pair[1]), channels: outputChannelCount(device))
}

/// Core Audio counts channels from 1; anything odd falls back to the first two.
func validStereo(left: Int, right: Int, channels: Int) -> (left: Int, right: Int) {
    guard left >= 1, right >= 1, left != right, left <= channels, right <= channels else { return (0, 1) }
    return (left - 1, right - 1)
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

final class Splitter: @unchecked Sendable {
    /// Posted on the main thread when capture can't start, so the user is told.
    static let failed = Notification.Name("VoiceOverAudioSplit.splitFailed")

    /// Everything that builds or takes apart the audio runs here, one job at a time, for
    /// every Splitter: a new one starts only once the old one has finished stopping.
    /// It isn't the main thread, because building can block for most of a minute while the
    /// output device is asleep (a wireless headset with the Mac locked), and the main thread
    /// carries the keyboard shortcuts.
    private static let control = DispatchQueue(label: "VOAudioSplit.control", qos: .userInitiated)

    private let configuration: SplitConfiguration
    private let queue = DispatchQueue(label: "VOAudioSplit.io", qos: .userInteractive)

    // Everything from here on is used on the control queue only.

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
    private var listeners: [AudioListeners.Token] = []

    init(configuration: SplitConfiguration) { self.configuration = configuration }

    #if DEBUG
    /// For the self-check: build on this output instead of the Mac's current one.
    nonisolated(unsafe) static var checkOutput: AudioDeviceID?
    #endif

    /// Starts capturing. Returns at once; the audio is built in turn, off the main thread.
    func start() {
        Splitter.control.async { self.begin() }
    }

    private func begin() {
        failedPlan = nil
        running = true
        rebuildIfNeeded()
        // Sound captured across a sleep doesn't always come back, and nothing may change to
        // prompt a rebuild. A few seconds after waking, see whether sound is still passing
        // through; only if it has stopped, build afresh.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Splitter.control.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.running, self.aggregate != kAudioObjectUnknown else { return }
                let before = Splitter.renders
                Splitter.control.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.running, self.aggregate != kAudioObjectUnknown, Splitter.renders == before else { return }
                    log("No sound passed through after waking; building the audio again.")
                    self.scheduleRebuild(force: true)
                }
            }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDevices] {
            if let token = AudioListeners.add(system, address(selector), handler: { [weak self] in
                Splitter.control.async { self?.scheduleRebuild() }
            }) {
                listeners.append(token)
            }
        }
    }

    private var pendingRebuild: DispatchWorkItem?
    private var pendingForce = false
    private var running = false
    private var wakeObserver: Any?
    /// Tries left for the setup that just failed.
    private var retries = 0
    /// The last setup that couldn't be built.
    private var failedPlan: Plan?

    /// Process and device lists change in bursts (connecting AirPods fires several
    /// changes in a second): wait for them to settle, then rebuild once.
    private func scheduleRebuild(force: Bool = false) {
        guard running else { return }
        pendingRebuild?.cancel()
        // A forced rebuild (the device changed shape) isn't lost to an ordinary one right after it.
        pendingForce = pendingForce || force
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            if self.pendingForce { self.built = nil; self.failedPlan = nil }
            self.pendingForce = false
            self.rebuildIfNeeded()
        }
        pendingRebuild = work
        Splitter.control.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Listeners on the output device itself: its channel count or sample rate can change
    /// without it changing (AirPods switch to a mono, lower-rate mode during calls).
    private var deviceListeners: [AudioListeners.Token] = []

    /// Rebuilds only on a real change: building can itself make the device report a
    /// change, which mustn't start a loop.
    private func watchDevice(_ device: AudioObjectID) {
        func shape() -> (Int, Float64, Int, Int) {
            let stereo = stereoChannels(device)
            return (outputChannelCount(device), readValue(device, kAudioDevicePropertyNominalSampleRate, default: Float64(0)),
                    stereo.left, stereo.right)
        }
        let builtShape = shape()
        for selector in [kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyNominalSampleRate,
                         kAudioDevicePropertyPreferredChannelsForStereo] {
            let addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeWildcard,
                                                  mElement: kAudioObjectPropertyElementMain)
            if let token = AudioListeners.add(device, addr, handler: { [weak self] in
                Splitter.control.async {
                    if shape() != builtShape { self?.scheduleRebuild(force: true) }
                }
            }) {
                deviceListeners.append(token)
            }
        }
    }

    private func unwatchDevices() {
        deviceListeners.forEach(AudioListeners.remove)
        deviceListeners.removeAll()
    }

    /// Stops capturing and returns audio to normal. Returns at once; the work is done in
    /// turn, and `done` is called (on the control queue) when sound is back to normal.
    func stop(then done: (() -> Void)? = nil) {
        Splitter.control.async {
            self.end()
            done?()
        }
    }

    /// For quitting: gives the taps a moment to go, so sound is back to normal before the
    /// app leaves. (If it takes longer, they go with the app anyway.)
    func stopAndWait(seconds: Double) {
        let finished = DispatchSemaphore(value: 0)
        stop { finished.signal() }
        _ = finished.wait(timeout: .now() + seconds)
    }

    private func end() {
        pendingRebuild?.cancel()
        pendingRebuild = nil
        running = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        listeners.forEach(AudioListeners.remove)
        listeners.removeAll()
        teardown()
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

        var output = defaultOutputDevice()
        #if DEBUG
        if let device = Splitter.checkOutput { output = device }
        #endif
        let speechDevice = configuration.speechDeviceUID
            .flatMap { uid in outputDevices().first { $0.uid == uid }?.id }
            .flatMap { $0 == output ? nil : $0 }
        return Plan(speech: speech, calls: calls, apps: apps, excluded: excluded, output: output,
                    speechDevice: speechDevice)
    }

    private func rebuildIfNeeded() {
        guard running else { return }
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
            let began = Date()
            try build(plan)
            failedPlan = nil
            retries = 0
            let took = Date().timeIntervalSince(began)
            log("Audio active: \(plan.apps.count) app(s) with their own settings\(plan.speechDevice != nil ? ", two devices" : "")\(took > 2 ? String(format: ", after %.0f seconds", took) : "").")
        } catch {
            log("Could not start audio: \(error)")
            teardown()
            failedPlan = plan
            DispatchQueue.main.async { NotificationCenter.default.post(name: Splitter.failed, object: nil) }
            // The same setup often works a moment later (a device still reconnecting after
            // waking). Left alone, it wasn't tried again until something else changed, which
            // could be never: two more tries, 3 and 15 seconds on.
            guard retries < 2 else { return }
            retries += 1
            Splitter.control.asyncAfter(deadline: .now() + (retries == 1 ? 3 : 15)) { [weak self] in
                guard let self, self.running, self.failedPlan == plan else { return }
                self.failedPlan = nil
                self.rebuildIfNeeded()
            }
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

    /// The Mixer's settings belong to the main thread. Building waits for them to be in
    /// place before sound starts; taking apart doesn't wait, so quitting can't be held up.
    private static func onMain(wait: Bool, _ work: @escaping () -> Void) {
        if Thread.isMainThread { return work() }
        wait ? DispatchQueue.main.sync(execute: work) : DispatchQueue.main.async(execute: work)
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

        // A device mid-switch can report a rate of 0, which would turn every filter's output
        // into something that isn't a number.
        let rate = readValue(aggregate, kAudioDevicePropertyNominalSampleRate, default: Float64(48000))
        let mainChannels = outputChannelCount(plan.output)
        // Stereo usually plays on a device's first two channels, but an audio interface can
        // be set to another pair (in Audio MIDI Setup): the ears go where the Mac sends them.
        let mainStereo = stereoChannels(plan.output)
        let speechStereo = subDevices.count > 1 ? plan.speechDevice.map(stereoChannels) : nil
        Splitter.onMain(wait: true) {
            Mixer.sampleRate = rate > 0 ? rate : 48000
            Mixer.mainChannels = mainChannels
            Mixer.mainStereo = mainStereo
            Mixer.speechStereo = speechStereo ?? (0, 1)
            Mixer.speechDeviceChannel = speechStereo != nil ? mainChannels : nil
            Mixer.sources = sources
        }
        watchDevice(plan.output)
        if let speechDevice = plan.speechDevice { watchDevice(speechDevice) }

        let tapCount = sources.count
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, output, _ in
            Splitter.render(input: input, output: output, tapCount: tapCount)
        }, "create IO proc")
        try check(AudioDeviceStart(aggregate, ioProc), "start audio")
    }

    /// Counts every pass of sound through the app, so a stall can be noticed. Written on the
    /// audio thread and only compared for change elsewhere, so an exact value doesn't matter.
    nonisolated(unsafe) private(set) static var renders: UInt64 = 0

    /// Real-time render: the last `tapCount` input buffers are the taps, in source
    /// order (any input streams of the output hardware itself, such as an AirPods
    /// mic, come first).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>, tapCount: Int) {
        renders &+= 1
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
        // Nothing is captured until the next build sets these again. (In order with that
        // build's own settings, which also go through the main thread.)
        Splitter.onMain(wait: false) {
            Mixer.sources = []
            Mixer.speechDeviceChannel = nil
        }
    }
}

struct SplitError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw SplitError("\(what) failed (OSStatus \(status))") }
}
