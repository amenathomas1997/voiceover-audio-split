// Sensors.swift — says when another app starts or stops using the camera or the
// microphone. Sighted people see a green or orange light; this says it, and for
// the microphone it names the app. This app's own camera and microphone use
// (scanning, the microphone check) is left out. Checked once a second.

import AppKit
import AVFoundation
import CoreAudio

enum SensorWatch {
    private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.sensors")
    nonisolated(unsafe) private static var cameraOn = false
    nonisolated(unsafe) private static var micApps: Set<String> = []

    /// Starts or stops watching to match the settings.
    static func update() {
        let wanted = Preferences.shared.announceCamera || Preferences.shared.announceMicrophone
        if wanted && timer == nil {
            cameraOn = cameraInUse()
            micApps = Set(appsUsingMicrophone())
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
            timer.setEventHandler { check() }
            timer.resume()
            self.timer = timer
        } else if !wanted, let running = timer {
            running.cancel()
            timer = nil
        }
    }

    private static func check() {
        let camera = cameraInUse()
        let apps = Set(appsUsingMicrophone())
        var messages: [String] = []
        let preferences = Preferences.shared
        if camera != cameraOn {
            cameraOn = camera
            if preferences.announceCamera {
                messages.append(camera ? String(localized: "Camera on") : String(localized: "Camera off"))
            }
        }
        if apps != micApps {
            let started = apps.subtracting(micApps).sorted(), stopped = micApps.subtracting(apps).sorted()
            micApps = apps
            if preferences.announceMicrophone {
                messages += started.map { String(localized: "\($0) is using the microphone") }
                messages += stopped.map { String(localized: "\($0) stopped using the microphone") }
            }
        }
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async {
            Tones.play(.status)
            Announcer.say(messages.joined(separator: ". "))
        }
    }

    /// Speaks the summary; reading the devices can take a moment, so not on the main thread.
    static func queueSummary() {
        queue.async { let text = summary(); DispatchQueue.main.async { Announcer.say(text) } }
    }

    /// A spoken summary, for the command.
    static func summary() -> String {
        let camera = cameraInUse() ? String(localized: "The camera is in use.") : String(localized: "The camera is not in use.")
        let apps = appsUsingMicrophone()
        let mic = apps.isEmpty ? String(localized: "No app is using the microphone.")
                               : String(localized: "Using the microphone: \(ListFormatter.localizedString(byJoining: apps)).")
        return camera + " " + mic
    }

    /// Whether another app has any camera on, including an iPhone through Continuity Camera.
    static func cameraInUse() -> Bool {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.contains { $0.isInUseByAnotherApplication }
    }

    /// Names of the apps recording from any microphone, not counting this app.
    static func appsUsingMicrophone() -> [String] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var names = Set<String>()
        for process in processes {
            guard read(process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1,
                  let pid = read(process, kAudioProcessPropertyPID, as: pid_t.self), pid != me else { continue }
            names.insert(appName(pid: pid, bundleID: bundleID(of: process)))
        }
        return names.sorted()
    }

    /// The app's name; helper processes (com.google.Chrome.helper) are named after their app.
    private static func appName(pid: pid_t, bundleID: String?) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, let name = app.localizedName {
            return name
        }
        if let bundleID, let owner = NSWorkspace.shared.runningApplications
            .filter({ $0.activationPolicy == .regular && $0.bundleIdentifier.map { bundleID.hasPrefix($0) } == true })
            .max(by: { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }), let name = owner.localizedName {
            return name
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID ?? String(localized: "An app")
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let text = value?.takeRetainedValue() as String?, !text.isEmpty else { return nil }
        return text
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
