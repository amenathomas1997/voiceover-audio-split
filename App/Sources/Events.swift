// Events.swift — speaks things VoiceOver stays silent about, each one optional:
//   * a download finished (and a key to open the latest download)
//   * a sound device connected or disconnected (AirPods, headphones…)
//   * the network dropped or came back
//   * the battery is low, or charging started or stopped
//   * the screen locked
// Plus a talking clock that chimes and says the time on the hour, half hour or quarter hour.

import AppKit
import CoreAudio
import IOKit.ps
import Network

enum SystemEvents {
    private static var started = false
    private static var downloadsWatcher: DispatchSourceFileSystemObject?
    private static var knownDownloads = Set<String>()
    private static var knownDevices = Set<String>()
    private static let networkMonitor = NWPathMonitor()
    private static var networkOnline: Bool?
    private static var batteryState: (percent: Int, charging: Bool)?
    private static var clockTimer: Timer?

    /// The real ~/Downloads. Inside the sandbox the usual lookup returns a folder in the
    /// app's container, which only links to Downloads if the container was made after
    /// the Downloads permission was added; the permission covers the real folder.
    static var downloadsFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Downloads", isDirectory: true)
    }

    static func start() {
        guard !started else { return }
        started = true
        watchDownloads()
        watchDevices()
        watchNetwork()
        watchBattery()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in
            if Preferences.shared.announceLock { Announcer.say(String(localized: "Screen locked")) }
        }
        updateClock()
    }

    // MARK: Downloads

    /// Files still being downloaded by Safari, Chrome and Firefox.
    static func isPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return name.hasPrefix(".") || lower.hasSuffix(".download") || lower.hasSuffix(".crdownload")
            || lower.hasSuffix(".part") || lower.hasSuffix(".partial")
    }

    private static func finishedDownloads() -> Set<String> {
        guard let folder = downloadsFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        // Firefox makes an empty file with the final name beside "name.part" while downloading.
        let all = Set(names)
        return Set(names.filter { name in
            !isPartial(name) && !all.contains(name + ".part")
                && ((try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)[.size] as? Int) ?? 1) != 0
        })
    }

    private static func watchDownloads() {
        guard let folder = downloadsFolder else { return }
        knownDownloads = finishedDownloads()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return log("Can't watch the Downloads folder.") }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        watcher.setEventHandler {
            // Browsers rename the partial file when the download completes; wait a moment for it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let current = finishedDownloads()
                let new = current.subtracting(knownDownloads)
                knownDownloads = current
                guard Preferences.shared.announceDownloads, !new.isEmpty else { return }
                Tones.play(.status)
                Announcer.say(new.count == 1 ? String(localized: "Download finished: \(new.first!)") : String(localized: "\(new.count) downloads finished"))
            }
        }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        downloadsWatcher = watcher
    }

    /// The most recently added finished file in Downloads.
    static func latestDownload() -> URL? {
        guard let folder = downloadsFolder else { return nil }
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { !isPartial($0.lastPathComponent) }.max { a, b in
            func date(_ url: URL) -> Date {
                let values = try? url.resourceValues(forKeys: Set(keys))
                return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
            }
            return date(a) < date(b)
        }
    }

    static func openLatestDownload() {
        guard let file = latestDownload() else { return Announcer.say(String(localized: "No downloads found")) }
        Announcer.say(String(localized: "Opening \(file.lastPathComponent)"))
        NSWorkspace.shared.open(file)
    }

    // MARK: Devices

    private static func watchDevices() {
        knownDevices = Set(outputDevices().map(\.name))
        var addr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            // Device lists change in bursts while a device connects.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let current = Set(outputDevices().map(\.name))
                let added = current.subtracting(knownDevices), removed = knownDevices.subtracting(current)
                knownDevices = current
                guard Preferences.shared.announceDevices else { return }
                for name in added { Announcer.say(String(localized: "\(name) connected")) }
                for name in removed { Announcer.say(String(localized: "\(name) disconnected")) }
            }
        }
    }

    // MARK: Network

    private static func watchNetwork() {
        networkMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                defer { networkOnline = online }
                guard let previous = networkOnline, previous != online, Preferences.shared.announceNetwork else { return }
                Announcer.say(online ? String(localized: "Network connection back") : String(localized: "Network connection lost"))
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "VoiceOverAudioSplit.events-network"))
    }

    // MARK: Battery

    private static func watchBattery() {
        let source = IOPSNotificationCreateRunLoopSource({ _ in SystemEvents.batteryChanged() }, nil)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source.takeRetainedValue(), .defaultMode) }
        batteryState = readBattery()
    }

    private static func readBattery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (current * 100 / maximum, description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    /// The low-battery levels that are announced.
    static let lowLevels = [20, 10, 5]

    private static func batteryChanged() {
        guard let now = readBattery() else { return }
        let before = batteryState
        batteryState = now
        guard Preferences.shared.announceBattery, let before else { return }
        if now.charging != before.charging {
            Announcer.say(now.charging ? String(localized: "Charging, \(now.percent) percent") : String(localized: "Not charging, \(now.percent) percent"))
        } else if !now.charging, let level = lowLevels.last(where: { before.percent > $0 && now.percent <= $0 }) {
            Tones.play(.quieter)
            Announcer.say(String(localized: "Battery low: \(level) percent"))
        }
    }

    // MARK: Talking clock

    /// Schedules the next announcement on the chosen boundary (every 15, 30 or 60 minutes).
    static func updateClock() {
        clockTimer?.invalidate()
        clockTimer = nil
        let interval = Preferences.shared.clockInterval
        guard interval > 0, let next = nextClockTime(after: Date(), every: interval) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { _ in
            Tones.play(.preset)
            Announcer.say(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
            updateClock()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    /// The next time on an exact boundary of `minutes`, for example 10:30 for every 30 minutes.
    static func nextClockTime(after date: Date, every minutes: Int, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = parts.minute, let hourStart = calendar.date(from: DateComponents(
            year: parts.year, month: parts.month, day: parts.day, hour: parts.hour)) else { return nil }
        let nextMinute = (minute / minutes + 1) * minutes
        return calendar.date(byAdding: .minute, value: nextMinute, to: hourStart)
    }
}
