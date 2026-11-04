// ResourceMonitor.swift — like NVDA's Resource Monitor add-on: how busy the processor is,
// how much memory and disk space are left, the battery, how long the Mac has been on and
// what version of macOS it runs, the network, and which apps are using the processor
// most. One command speaks a summary; a digit pressed right after it (1 to 7) gives one
// part in full, and each part can also be asked for by voice. A window shows them all,
// refreshed every few seconds. Everything is read from the Mac itself; nothing is sent.

import AppKit
import Darwin
import IOKit
import Network
import SwiftUI

enum ResourceMonitor {
    /// The parts, in the order of the digits that pick them.
    enum Detail: Int, CaseIterable, Identifiable {
        case processor = 1, memory, disks, battery, system, network, processes
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .processor: String(localized: "Processor")
            case .memory: String(localized: "Memory")
            case .disks: String(localized: "Disk space")
            case .battery: String(localized: "Battery")
            case .system: String(localized: "System")
            case .network: String(localized: "Network")
            case .processes: String(localized: "Busiest apps")
            }
        }
    }

    /// How long the processor is watched before it's reported.
    static let sampleSeconds = 0.7
    /// Digits pressed within this long after the summary pick a part.
    static let digitSeconds: TimeInterval = 8

    // MARK: Spoken

    /// The short version: processor, memory, the startup disk, the battery and the uptime.
    static func summary() async -> String {
        var parts: [String] = []
        if let cpu = await processorUsage() { parts.append(String(localized: "Processor \(percent(cpu.overall)) percent busy")) }
        if let memory = memory() {
            parts.append(String(localized: "Memory \(bytes(memory.used, .memory)) of \(bytes(memory.total, .memory)) used") + pressureNote(memory.pressure))
        }
        if let disk = volumes().first(where: \.isStartup) ?? volumes().first {
            parts.append(String(localized: "\(bytes(disk.free, .file)) free on \(disk.name)"))
        }
        if let battery = SystemStatus.battery() { parts.append(battery) }
        parts.append(String(localized: "On for \(uptimeWords(ProcessInfo.processInfo.systemUptime))"))
        return parts.joined(separator: ". ") + "."
    }

    /// One part in full.
    static func detail(_ detail: Detail) async -> String {
        switch detail {
        case .processor:
            guard let cpu = await processorUsage() else { return String(localized: "The processor's use couldn't be read.") }
            let busiest = cpu.cores.max() ?? 0
            let heat = thermalWords()
            return String(localized: "Processor \(percent(cpu.overall)) percent busy across \(cpu.cores.count) cores; the busiest core is at \(percent(busiest)) percent. \(heat)")
        case .memory:
            guard let memory = memory() else { return String(localized: "The memory use couldn't be read.") }
            var text = String(localized: "Memory: \(bytes(memory.used, .memory)) used of \(bytes(memory.total, .memory)), \(bytes(memory.total - min(memory.used, memory.total), .memory)) free.")
            text += " " + pressureSentence(memory.pressure)
            if memory.swapUsed > 0 { text += " " + String(localized: "\(bytes(memory.swapUsed, .memory)) of swap is in use.") }
            return text
        case .disks:
            let disks = volumes()
            guard !disks.isEmpty else { return String(localized: "No disks were found.") }
            return disks.map { String(localized: "\($0.name): \(bytes($0.free, .file)) free of \(bytes($0.total, .file)), \(percent($0.usedFraction)) percent used") }
                .joined(separator: ". ") + "."
        case .battery:
            guard let battery = SystemStatus.battery() else { return String(localized: "This Mac has no battery.") }
            let health = batteryHealth().map { " " + $0 } ?? ""
            return battery + "." + health
        case .system:
            let uptime = uptimeWords(ProcessInfo.processInfo.systemUptime)
            return String(localized: "\(macOSVersion()) on \(hardwareWords()). On for \(uptime).")
        case .network:
            return networkWords()
        case .processes:
            let apps = await busiestProcesses()
            guard !apps.isEmpty else { return String(localized: "The processor use of other apps couldn't be read.") }
            let list = apps.prefix(5).map { String(localized: "\($0.name) \(percent($0.cpu)) percent") }
            return String(localized: "Busiest now: ") + ListFormatter.localizedString(byJoining: list) + "."
        }
    }

    /// Speaks the summary, then takes a digit for a part. Pressing nothing changes nothing.
    @MainActor
    static func announce() {
        Tones.play(.status)
        Task { @MainActor in
            let text = await summary()
            Announcer.say(text + " " + String(localized: "Press 1 to 7 for processor, memory, disks, battery, system, network or busiest apps."))
            listenForDigit()
        }
    }

    @MainActor
    static func announce(_ detail: Detail) {
        Tones.play(.status)
        Task { @MainActor in Announcer.say(await self.detail(detail)) }
    }

    /// For a few seconds, a digit on its own picks a part; any other key passes through and
    /// ends the wait. Not while a lesson or practice is watching the keys.
    @MainActor
    private static func listenForDigit() {
        guard Hotkeys.keyObserver == nil else { return }
        let until = Date().addingTimeInterval(digitSeconds)
        let observer: (Int64, CGEventFlags, NSEvent?) -> Bool = { keyCode, flags, _ in
            // Only a plain digit: Command-1 and the like belong to the app in front.
            let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            guard Date() < until, plain, let number = Key.presetDigits[keyCode], let detail = Detail(rawValue: number) else {
                DispatchQueue.main.async { if Hotkeys.keyObserver != nil { Hotkeys.keyObserver = nil } }
                return false
            }
            DispatchQueue.main.async {
                Hotkeys.keyObserver = nil
                announce(detail)
            }
            return true
        }
        Hotkeys.keyObserver = observer
        DispatchQueue.main.asyncAfter(deadline: .now() + digitSeconds + 0.1) {
            // Only this wait is cleared, not a lesson that started meanwhile.
            if Date() >= until, Hotkeys.keyObserver != nil, waitingForDigit { Hotkeys.keyObserver = nil }
            waitingForDigit = false
        }
        waitingForDigit = true
    }
    nonisolated(unsafe) private static var waitingForDigit = false

    // MARK: Processor

    /// Busy and total ticks for each core since boot.
    private static func cpuTicks() -> [(busy: UInt64, total: UInt64)]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            let base = core * states
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)]), idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            return (user + system + nice, user + system + nice + idle)
        }
    }

    /// How busy the processor was over the sample: overall and per core, 0 to 1.
    static func processorUsage() async -> (overall: Double, cores: [Double])? {
        guard let before = cpuTicks() else { return nil }
        try? await Task.sleep(for: .milliseconds(Int(sampleSeconds * 1000)))
        guard let after = cpuTicks(), after.count == before.count else { return nil }
        let cores = zip(before, after).map { a, b -> Double in
            let total = b.total &- a.total
            return total == 0 ? 0 : Double(b.busy &- a.busy) / Double(total)
        }
        guard !cores.isEmpty else { return nil }
        return (cores.reduce(0, +) / Double(cores.count), cores)
    }

    static func thermalWords() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: String(localized: "The Mac is running cool.")
        case .fair: String(localized: "The Mac is a little warm.")
        case .serious: String(localized: "The Mac is hot, and may slow down.")
        case .critical: String(localized: "The Mac is very hot and is slowing down to cool off.")
        @unknown default: ""
        }
    }

    // MARK: Memory

    struct Memory {
        let total: UInt64
        let used: UInt64
        /// 1 normal, 2 warning, 4 critical (the kernel's memory pressure level).
        let pressure: Int32
        let swapUsed: UInt64
    }

    static func memory() -> Memory? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        // What Activity Monitor calls memory used: app memory, wired memory and compressed memory.
        let app = UInt64(max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count)))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        var pressure: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        return Memory(total: ProcessInfo.processInfo.physicalMemory, used: used, pressure: pressure, swapUsed: swap.xsu_used)
    }

    private static func pressureNote(_ level: Int32) -> String {
        level >= 4 ? String(localized: ", memory pressure critical") : level >= 2 ? String(localized: ", memory pressure high") : ""
    }

    private static func pressureSentence(_ level: Int32) -> String {
        level >= 4 ? String(localized: "Memory pressure is critical: closing some apps would help.")
            : level >= 2 ? String(localized: "Memory pressure is high.") : String(localized: "Memory pressure is normal.")
    }

    // MARK: Disks

    struct Volume {
        let name: String
        let free: UInt64
        let total: UInt64
        let isStartup: Bool
        var usedFraction: Double { total == 0 ? 0 : Double(total - min(free, total)) / Double(total) }
    }

    /// Mounted disks the user can see, the startup disk first.
    static func volumes() -> [Volume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                         .volumeTotalCapacityKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var result: [Volume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let name = values.volumeName ?? url.lastPathComponent
            result.append(Volume(name: name, free: UInt64(max(0, free)), total: UInt64(total), isStartup: values.volumeIsRootFileSystem ?? false))
        }
        return result.sorted { $0.isStartup && !$1.isStartup }
    }

    // MARK: Battery, system, network

    /// "The battery's health is good", when macOS says.
    static func batteryHealth() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let health = description[kIOPSBatteryHealthKey] as? String else { continue }
            switch health {
            case kIOPSGoodValue: return String(localized: "The battery's health is good.")
            case kIOPSFairValue: return String(localized: "The battery's health is fair.")
            case kIOPSPoorValue: return String(localized: "The battery's health is poor; it may need a service.")
            default: return nil
            }
        }
        return nil
    }

    /// "3 days, 4 hours", "12 minutes".
    static func uptimeWords(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 3600 ? [.minute] : seconds < 86400 ? [.hour, .minute] : [.day, .hour]
        return formatter.string(from: max(60, seconds)) ?? ""
    }

    /// "macOS 27.2".
    static func macOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// "a MacBook Pro with an Apple M5 Pro, 14 cores and 24 GB of memory".
    static func hardwareWords() -> String {
        let chip = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.machine") ?? String(localized: "an unknown processor")
        let model = productName() ?? sysctlString("hw.model") ?? "Mac"
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let memory = bytes(ProcessInfo.processInfo.physicalMemory, .memory)
        return String(localized: "\(model) with \(chip), \(cores) cores and \(memory) of memory")
    }

    /// "MacBook Pro (14-inch, M5 Pro)", from the Mac's own description of itself: the
    /// "product" entry of the device tree on Apple silicon, or the platform expert on Intel.
    private static func productName() -> String? {
        for entry in [IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product"),
                      IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))] where entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
            let name = (value as? String) ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespaces)
    }

    static func networkWords() -> String {
        var text = SystemStatus.network()
        if let interface = SystemStatus.currentPath?.availableInterfaces.first,
           let address = ipv4Address(of: interface.name) {
            text += ". " + String(localized: "This Mac's address is \(address), on \(interface.name).")
        }
        return text + (text.hasSuffix(".") ? "" : ".")
    }

    /// The IPv4 address of a network interface, such as en0.
    static func ipv4Address(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == interface,
                  let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    // MARK: Processes

    struct Process {
        let name: String
        /// Share of one core, 0 to 1.
        let cpu: Double
    }

    /// Processor time used so far by each process, in seconds.
    private static func processTimes() -> [pid_t: Double] {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let scale = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let count = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)) / MemoryLayout<pid_t>.size
        guard count > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: count + 16)
        let filled = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))) / MemoryLayout<pid_t>.size
        var times: [pid_t: Double] = [:]
        for pid in pids.prefix(filled) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            if ok == 0 { times[pid] = Double(info.ri_user_time + info.ri_system_time) * scale }
        }
        return times
    }

    /// The apps and processes using the processor most, over the sample, busiest first.
    static func busiestProcesses() async -> [Process] {
        let before = processTimes()
        guard !before.isEmpty else { return [] }
        try? await Task.sleep(for: .milliseconds(Int(sampleSeconds * 1000)))
        let after = processTimes()
        var shares: [(pid_t, Double)] = []
        for (pid, time) in after {
            guard let earlier = before[pid] else { continue }
            let share = (time - earlier) / sampleSeconds
            if share >= 0.005 { shares.append((pid, share)) }
        }
        return shares.sorted { $0.1 > $1.1 }.prefix(8).map { Process(name: processName($0.0), cpu: $0.1) }
    }

    private static func processName(_ pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
        return pid == getpid() ? String(localized: "VoiceOver Audio Split") : String(localized: "a system process")
    }

    // MARK: Words

    static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    /// "23.9 GB", "946 GB", "2 TB": one decimal at most, in the units Finder uses for files
    /// (1000 to the unit) or Activity Monitor for memory (1024).
    static func bytes(_ count: UInt64, _ style: ByteCountFormatter.CountStyle) -> String {
        let step = style == .memory ? 1024.0 : 1000.0
        var value = Double(count) / (step * step)
        var unit = UnitInformationStorage.megabytes
        if value >= step * step { value /= step * step; unit = .terabytes } else if value >= step { value /= step; unit = .gigabytes }
        let digits = value >= 100 || unit == .megabytes ? 0 : 1
        return Measurement(value: value, unit: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...digits))))
    }
}

// MARK: - Window

/// Every part at once. Nothing changes under the VoiceOver cursor unless asked: Refresh
/// reads everything again, and updating by itself is off until it's turned on. The
/// readings are taken off the main thread, so the window stays responsive.
final class ResourceMonitorModel: ObservableObject {
    @Published var rows: [(detail: ResourceMonitor.Detail, text: String)] = ResourceMonitor.Detail.allCases.map { ($0, "") }
    @Published var autoUpdate = false { didSet { autoUpdate ? startUpdating() : stopUpdating() } }
    @Published private(set) var isRefreshing = false
    @Published private(set) var updatedAt: Date?
    private var task: Task<Void, Never>?
    private var updating: Task<Void, Never>?

    /// Reads every part again, and says so when done.
    @MainActor
    func refresh(announce: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        task = Task { @MainActor [weak self] in
            let texts = await Task.detached(priority: .userInitiated) { () -> [(ResourceMonitor.Detail, String)] in
                var result: [(ResourceMonitor.Detail, String)] = []
                for detail in ResourceMonitor.Detail.allCases { result.append((detail, await ResourceMonitor.detail(detail))) }
                return result
            }.value
            guard let self, !Task.isCancelled else { return }
            // Only rows whose words changed are touched, so VoiceOver isn't interrupted for nothing.
            for (detail, text) in texts {
                if let index = rows.firstIndex(where: { $0.detail == detail }), rows[index].text != text { rows[index].text = text }
            }
            updatedAt = Date()
            isRefreshing = false
            if announce { Announcer.say(String(localized: "Updated.")) }
        }
    }

    private func startUpdating() {
        updating?.cancel()
        updating = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func stopUpdating() {
        updating?.cancel()
        updating = nil
    }

    func stop() {
        stopUpdating()
        task?.cancel()
        task = nil
    }

    var asText: String { rows.map { "\($0.detail.title): \($0.text)" }.joined(separator: "\n") }
}

struct ResourceMonitorView: View {
    @StateObject private var model = ResourceMonitorModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.rows, id: \.detail) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.detail.title).font(.headline)
                    Text(row.text.isEmpty ? String(localized: "Reading…") : row.text)
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 2)
            }
            HStack {
                Button(String(localized: "Refresh")) { model.refresh(announce: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRefreshing)
                Toggle(String(localized: "Update every 5 seconds"), isOn: $model.autoUpdate)
                Spacer()
                Button(String(localized: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.asText, forType: .string)
                    Announcer.say(String(localized: "Copied"))
                }
                Button(String(localized: "Speak All")) { Announcer.say(model.asText) }
            }
            .padding([.horizontal, .bottom])
            if let date = model.updatedAt {
                Text(String(localized: "Updated at \(date.formatted(date: .omitted, time: .standard)). Press Return to refresh."))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom])
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { model.refresh() }
        .onDisappear { model.stop() }
    }
}
