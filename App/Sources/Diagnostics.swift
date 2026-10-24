// Diagnostics.swift — help for fixing problems:
//   * Diagnostics report: the app's recent log, version, Mac details and
//     settings in one text file the user can attach to a bug report. Saved only
//     where the user chooses; never sent automatically. The API key is never included.
//   * Performance: how much processor time and memory the app is using now and
//     on average since it started, to check it's light enough to leave on all day.

import AppKit
import OSLog

enum Diagnostics {
    static func report(log: String? = nil) -> String {
        let settings = (try? SettingsTransfer.exportData()).flatMap { String(data: $0, encoding: .utf8) } ?? "unavailable"
        return """
        VoiceOver Audio Split diagnostics report
        Created: \(Date().formatted(date: .abbreviated, time: .standard))

        \(BugReport.details)
        \(Performance.summary())
        Audio capture running: \(Mixer.sources.isEmpty ? "no" : "yes, \(Mixer.sources.count) sources")
        Keyboard shortcuts allowed: \(Hotkeys.isTrusted ? "yes" : "no")

        Recent log (last hour):
        \(log ?? recentLog())

        Settings (no API key or personal files):
        \(settings)
        """
    }

    /// This app's own log entries from the last hour.
    private static func recentLog() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return "unavailable" }
        let start = store.position(date: Date().addingTimeInterval(-3600))
        let entries = (try? store.getEntries(at: start, matching: NSPredicate(
            format: "subsystem == %@", "com.fullcircleat.VoiceOverAudioSplit"))) ?? AnySequence([])
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map {
            "\($0.date.formatted(date: .omitted, time: .standard)) \($0.composedMessage)"
        }
        return lines.isEmpty ? "(no entries)" : lines.suffix(400).joined(separator: "\n")
    }

    @MainActor
    static func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "VoiceOver Audio Split diagnostics.txt")
        panel.allowedContentTypes = [.plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Announcer.say(String(localized: "Saving"))
        // Reading the log can take a moment: not on the main thread.
        Task.detached(priority: .userInitiated) {
            let log = recentLog()
            await MainActor.run {
                do {
                    try report(log: log).write(to: url, atomically: true, encoding: .utf8)
                    Announcer.say(String(localized: "Diagnostics saved. Attach \(url.lastPathComponent) to your bug report."))
                } catch {
                    Announcer.say(String(localized: "Couldn't save the diagnostics report"))
                }
            }
        }
    }
}

enum Performance {
    private static let launch = Date()

    /// Total processor time this app has used, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Memory in use, in megabytes (the same "memory footprint" Activity Monitor shows).
    static func memoryMegabytes() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Average share of one processor core since launch, as a percentage.
    static func averagePercent() -> Double {
        let elapsed = max(Date().timeIntervalSince(launch), 1)
        return cpuSeconds() / elapsed * 100
    }

    static func summary() -> String {
        String(format: "Processor: %.1f%% of one core on average since launch. Memory: %.0f MB.",
               averagePercent(), memoryMegabytes())
    }

    /// Measures the next two seconds as well, then speaks the result.
    static func announce() {
        let startCPU = cpuSeconds()
        Announcer.say(String(localized: "Measuring for two seconds"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let now = (cpuSeconds() - startCPU) / 2 * 100
            let audio = Mixer.sources.isEmpty ? String(localized: "Audio capture is off.") : String(localized: "Audio capture is on.")
            let average = String(format: "%.1f", averagePercent())
            Announcer.say(String(localized: "Using \(Int(now.rounded())) percent of one processor core now, \(average) percent on average since it started, and \(Int(memoryMegabytes().rounded())) megabytes of memory. \(audio)"))
        }
    }
}
