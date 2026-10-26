// AudioSystem.swift — Mac-wide audio controls that don't need capture:
// switching the output device, muting the microphones, and finding out which
// apps are making sound.

import AppKit
import CoreAudio

enum AudioSystem {
    // MARK: - Output device

    /// The device the user picked with the shortcut, held for a short time.
    /// AirPods automatic switching can take the sound back a second or two after
    /// a switch (for example while a call app is using audio); within this window
    /// the choice is put back, a few times at most.
    private static var held: (device: AudioDeviceID, from: AudioDeviceID, until: Date, restores: Int)?
    private static var watchingOutput = false

    /// Switches to the next output device and returns its name.
    static func nextOutputDevice() -> String? {
        let devices = outputDevices()
        guard !devices.isEmpty else { return nil }
        // Step on from the device the user last picked, even if macOS has just taken it back.
        let current = held.map { $0.until > Date() ? $0.device : defaultOutputDevice() } ?? defaultOutputDevice()
        let index = devices.firstIndex { $0.id == current }.map { ($0 + 1) % devices.count } ?? 0
        let next = devices[index]
        let from = defaultOutputDevice()
        guard setDefaultOutput(next.id) else { return nil }
        held = (next.id, from, Date().addingTimeInterval(20), 0)
        watchOutput()
        return next.name
    }

    /// The output device in use now.
    static var currentOutputDevice: AudioDeviceID { defaultOutputDevice() }

    /// Stops holding the chosen output device.
    static func releaseHold() {
        held = nil
    }

    /// Sets both the main output and the alert-sound output.
    @discardableResult
    static func setDefaultOutput(_ device: AudioDeviceID) -> Bool {
        var id = device
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        var systemAddr = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &systemAddr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if status != noErr { log("Could not switch output device (OSStatus \(status))") }
        return status == noErr
    }

    private static func watchOutput() {
        guard !watchingOutput else { return }
        watchingOutput = true
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            guard let choice = held, choice.until > Date() else { return }
            let current = defaultOutputDevice()
            guard current != choice.device, outputDevices().contains(where: { $0.id == choice.device }),
                  outputDevices().contains(where: { $0.id == current }) else { return }
            // Only undo the Bluetooth device that was switched away from taking the sound back
            // on its own. Speakers or headphones chosen in Control Center, plugged in, or
            // newly connected, are the user's choice.
            let transport: UInt32 = readValue(current, kAudioDevicePropertyTransportType, default: UInt32(0))
            guard current == choice.from,
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else {
                held = nil
                return
            }
            let taker = outputDevices().first { $0.id == current }?.name ?? "Another device"
            if choice.restores < 8 {
                held?.restores += 1
                log("Output taken back by \(taker); restoring the chosen device.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { setDefaultOutput(choice.device) }
            } else {
                held = nil
                log("Output keeps being taken back by \(taker); giving up.")
                Announcer.say(String(localized: "\(taker) keeps taking the sound back. To stop this, open \(taker) in System Settings and set Connect to This Mac to When Last Connected to This Mac."))
            }
        }
    }

    // MARK: - Microphone

    enum MicResult { case muted, unmuted, unsupported }

    /// Muting covers every microphone, because macOS can switch the active one at
    /// any moment (for example AirPods automatic switching). Saved, so a restart
    /// keeps you muted.
    private(set) static var isMicMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "micMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "micMuted") }
    }

    /// Volumes of microphones we muted by turning them down, so they can be restored.
    private static var savedVolumes: [String: Float] {
        get { UserDefaults.standard.dictionary(forKey: "savedMicVolumes") as? [String: Float] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "savedMicVolumes") }
    }

    private static var watchingInputs = false

    private static func defaultInputDevice() -> AudioDeviceID {
        readValue(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice,
                  default: AudioDeviceID(kAudioObjectUnknown))
    }

    static var inputDeviceName: String {
        readString(defaultInputDevice(), kAudioObjectPropertyName) ?? "Microphone"
    }

    /// Real microphones, leaving out virtual and aggregate devices.
    private static func inputDevices() -> [AudioDeviceID] {
        readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, of: AudioDeviceID.self)
            .filter { device in
                let transport = readValue(device, kAudioDevicePropertyTransportType, default: UInt32(0))
                return transport != kAudioDeviceTransportTypeVirtual && transport != kAudioDeviceTransportTypeAggregate
                    && channelCount(device, scope: kAudioObjectPropertyScopeInput) > 0
            }
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String {
        readString(device, kAudioDevicePropertyDeviceUID) ?? "\(device)"
    }

    /// Call at launch: keeps microphones muted across restarts and device changes.
    static func start() {
        guard !watchingInputs else { return }
        watchingInputs = true
        if isMicMuted { _ = inputDevices().map { setMuted($0, true) } }
        // A microphone that appears or becomes active while muted gets muted too.
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
                if isMicMuted { _ = inputDevices().map { setMuted($0, true) } }
                // A microphone turned down while muted, and unplugged before unmuting, comes back at its volume.
                else {
                    let saved = savedVolumes
                    for device in inputDevices() where saved[deviceUID(device)] != nil { _ = setMuted(device, false) }
                }
            }
        }
    }

    static func toggleMicrophone() -> MicResult {
        let muting = !isMicMuted
        let results = inputDevices().map { setMuted($0, muting) }
        guard results.contains(true) else { return .unsupported }
        isMicMuted = muting
        return muting ? .muted : .unmuted
    }

    /// Mutes or unmutes one microphone, by its mute switch or, if it has none, by
    /// turning its volume to zero and back. Returns whether it worked.
    private static func setMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var settable: DarwinBoolean = false
        var muteAddr = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        if AudioObjectHasProperty(device, &muteAddr),
           AudioObjectIsPropertySettable(device, &muteAddr, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muted ? 1 : 0
            return AudioObjectSetPropertyData(device, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }

        var volumeAddr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(device, &volumeAddr),
              AudioObjectIsPropertySettable(device, &volumeAddr, &settable) == noErr, settable.boolValue
        else { return false }
        let uid = deviceUID(device)
        var volume: Float
        if muted {
            var current: Float = 1
            var size = UInt32(MemoryLayout<Float>.size)
            AudioObjectGetPropertyData(device, &volumeAddr, 0, nil, &size, &current)
            if current > 0 { savedVolumes[uid] = current }
            volume = 0
        } else {
            volume = savedVolumes[uid] ?? 0.75
            savedVolumes[uid] = nil
        }
        return AudioObjectSetPropertyData(device, &volumeAddr, 0, nil, UInt32(MemoryLayout<Float>.size), &volume) == noErr
    }

    // MARK: - What's playing

    /// Names of the apps currently making sound, not counting VoiceOver or this app.
    static func appsPlaying() -> [String] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var names: [String] = []
        for process in audioProcesses() {
            guard readValue(process.object, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0,
                  process.pid != getpid(), !isSpeechProcess(process) else { continue }
            let name = appName(for: process, among: running)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// The app a sound comes from: the process itself if it is an app, otherwise
    /// the app whose bundle ID it extends (us.zoom.caphost → zoom.us).
    private static func appName(for process: AudioProcess, among apps: [NSRunningApplication]) -> String {
        if let app = apps.first(where: { $0.processIdentifier == process.pid }), let name = app.localizedName {
            return name
        }
        if process.bundleID.hasPrefix("com.apple.WebKit") { return "a web page" }
        let parts = process.bundleID.split(separator: ".")
        for length in stride(from: parts.count - 1, through: 2, by: -1) {
            let prefix = parts.prefix(length).joined(separator: ".")
            if let app = apps.first(where: { $0.bundleIdentifier?.hasPrefix(prefix) == true }), let name = app.localizedName {
                return name
            }
        }
        return NSRunningApplication(processIdentifier: process.pid)?.localizedName
            ?? (process.bundleID.isEmpty ? "a system sound" : process.bundleID)
    }
}
