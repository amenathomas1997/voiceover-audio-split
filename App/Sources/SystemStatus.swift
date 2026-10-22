// SystemStatus.swift — one spoken summary of the Mac's state: time, battery,
// network, output device and volume, and the microphone. JAWS has a command
// for each of these; VoiceOver has some, spread across different keys.

import AudioToolbox
import CoreAudio
import Foundation
import IOKit.ps
import Network

enum SystemStatus {
    private static let monitor = NWPathMonitor()
    nonisolated(unsafe) private static var path: NWPath?

    /// Call at launch so the network state is known when asked.
    static func start() {
        monitor.pathUpdateHandler = { path = $0 }
        monitor.start(queue: DispatchQueue(label: "VoiceOverAudioSplit.network"))
    }

    static func summary() -> String {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)
        return [time, battery(), network(), output(), microphone()].compactMap { $0 }.joined(separator: ". ")
    }

    private static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = current * 100 / maximum
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            var text = "Battery \(percent) percent"
            if charging {
                text += ", charging"
            } else if onPower {
                text += ", on power"
            } else if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                text += ", about \(minutes / 60) hours \(minutes % 60) minutes left"
            }
            return text
        }
        return nil
    }

    private static func network() -> String {
        guard let path, path.status == .satisfied else { return "No network connection" }
        if path.usesInterfaceType(.wifi) { return "Connected over Wi-Fi" }
        if path.usesInterfaceType(.wiredEthernet) { return "Connected over Ethernet" }
        if path.usesInterfaceType(.cellular) { return "Connected over a phone hotspot" }
        return "Connected to the network"
    }

    private static func output() -> String? {
        let device = defaultOutputDevice()
        guard let name = readString(device, kAudioObjectPropertyName) else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr else {
            return "Sound playing on \(name)"
        }
        return "Sound playing on \(name) at \(Int((volume * 100).rounded())) percent volume"
    }

    private static func microphone() -> String {
        AudioSystem.isMicMuted ? "Microphone muted" : "Microphone on, using \(AudioSystem.inputDeviceName)"
    }
}

/// Finds formatting problems in text, like JAWS Text Analyzer. Runs on the Mac.
enum TextAnalyzer {
    static func analyze(_ text: String) -> String {
        var problems: [String] = []
        let lines = text.components(separatedBy: "\n")

        func firstLine(where test: (String) -> Bool) -> String {
            lines.firstIndex(where: test).map { ", first on line \($0 + 1)" } ?? ""
        }
        func count(_ pattern: String) -> Int {
            (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(
                in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        }
        func report(_ number: Int, _ singular: String, _ plural: String, line: (String) -> Bool) {
            guard number > 0 else { return }
            problems.append("\(number) \(number == 1 ? singular : plural)\(firstLine(where: line))")
        }
        func matches(_ pattern: String) -> (String) -> Bool {
            { line in line.range(of: pattern, options: .regularExpression) != nil }
        }

        report(count("[^ \\n] {2,}[^ \\n]"), "double space", "double spaces", line: matches("[^ ] {2,}[^ ]"))
        report(count(" [,.;:!?](\\s|$)"), "space before punctuation", "spaces before punctuation",
               line: matches(" [,.;:!?](\\s|$)"))
        report(count("(?i)\\b(\\w+)\\s+\\1\\b"), "repeated word", "repeated words", line: matches("(?i)\\b(\\w+)\\s+\\1\\b"))
        report(lines.filter { $0.hasSuffix(" ") || $0.hasSuffix("\t") }.count,
               "line ending in a space", "lines ending in spaces", line: { $0.hasSuffix(" ") || $0.hasSuffix("\t") })
        report(count("\\n\\s*\\n\\s*\\n"), "run of extra blank lines", "runs of extra blank lines", line: { _ in false })
        report(count("[.!?] {2,}[A-Z]") > 0 && count("[.!?] [A-Z]") > 0 ? 1 : 0,
               "mix of one and two spaces after sentences", "", line: matches("[.!?] {2,}[A-Z]"))
        if lines.contains(where: { $0.hasPrefix("\t") }) && lines.contains(where: { $0.hasPrefix("  ") }) {
            problems.append("indents use both tabs and spaces")
        }

        for (open, close, name) in [("(", ")", "parentheses"), ("[", "]", "square brackets"), ("{", "}", "braces"),
                                    ("\u{201C}", "\u{201D}", "curly quotes")] {
            let opens = text.components(separatedBy: open).count - 1
            let closes = text.components(separatedBy: close).count - 1
            if opens != closes { problems.append("unmatched \(name): \(opens) opening, \(closes) closing") }
        }
        if (text.components(separatedBy: "\"").count - 1) % 2 == 1 { problems.append("an odd number of straight quotes") }

        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let summary = "\(words) words, \(lines.count) lines"
        return problems.isEmpty
            ? "No formatting problems found. \(summary)."
            : "\(problems.count) \(problems.count == 1 ? "problem" : "problems"): "
                + problems.joined(separator: ". ") + ". \(summary)."
    }
}
