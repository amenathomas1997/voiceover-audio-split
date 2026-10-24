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

    static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = current * 100 / maximum
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            if charging { return String(localized: "Battery \(percent) percent, charging") }
            if onPower { return String(localized: "Battery \(percent) percent, on power") }
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                return String(localized: "Battery \(percent) percent, about \(minutes / 60) hours \(minutes % 60) minutes left")
            }
            return String(localized: "Battery \(percent) percent")
        }
        return nil
    }

    private static func network() -> String {
        guard let path, path.status == .satisfied else { return String(localized: "No network connection") }
        if path.usesInterfaceType(.wifi) { return String(localized: "Connected over Wi-Fi") }
        if path.usesInterfaceType(.wiredEthernet) { return String(localized: "Connected over Ethernet") }
        if path.usesInterfaceType(.cellular) { return String(localized: "Connected over a phone hotspot") }
        return String(localized: "Connected to the network")
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
            return String(localized: "Sound playing on \(name)")
        }
        return String(localized: "Sound playing on \(name) at \(Int((volume * 100).rounded())) percent volume")
    }

    private static func microphone() -> String {
        AudioSystem.isMicMuted ? String(localized: "Microphone muted") : String(localized: "Microphone on, using \(AudioSystem.inputDeviceName)")
    }
}

/// Finds formatting problems in text, like JAWS Text Analyzer. Runs on the Mac.
enum TextAnalyzer {
    /// A summary of every formatting problem, for speaking.
    static func analyze(_ text: String) -> String {
        let problems = sentenceProblems(text) + wholeTextProblems(text)
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lines = text.components(separatedBy: "\n").count
        let summary = String(localized: "\(words) words, \(lines) lines")
        guard !problems.isEmpty else { return String(localized: "No formatting problems found. \(summary).") }
        let list = problems.joined(separator: ". ")
        return problems.count == 1 ? String(localized: "1 problem: \(list). \(summary).")
                                   : String(localized: "\(problems.count) problems: \(list). \(summary).")
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }

    /// ", first on line 3", or nothing if no line matches.
    private static func firstLine(_ text: String, where test: (String) -> Bool) -> String {
        text.components(separatedBy: "\n").firstIndex(where: test).map { String(localized: ", first on line \($0 + 1)") } ?? ""
    }

    private static func matches(_ pattern: String) -> (String) -> Bool {
        { line in line.range(of: pattern, options: .regularExpression) != nil }
    }

    /// Problems that occur inside sentences, counted across the text.
    static func sentenceProblems(_ text: String) -> [String] {
        var problems: [String] = []
        func add(_ number: Int, _ one: String, _ many: String, _ line: (String) -> Bool) {
            guard number > 0 else { return }
            problems.append((number == 1 ? one : many) + firstLine(text, where: line))
        }
        let doubles = count("[^ \\n] {2,}[^ \\n]", in: text)
        add(doubles, String(localized: "1 double space"), String(localized: "\(doubles) double spaces"), matches("[^ ] {2,}[^ ]"))
        let before = count(" [,.;:!?](\\s|$)", in: text)
        add(before, String(localized: "1 space before punctuation"), String(localized: "\(before) spaces before punctuation"),
            matches(" [,.;:!?](\\s|$)"))
        let repeated = count("(?i)\\b(\\w+)\\s+\\1\\b", in: text)
        add(repeated, String(localized: "1 repeated word"), String(localized: "\(repeated) repeated words"),
            matches("(?i)\\b(\\w+)\\s+\\1\\b"))
        return problems
    }

    /// Problems about the text as a whole rather than one sentence.
    static func wholeTextProblems(_ text: String) -> [String] {
        var problems: [String] = []
        let lines = text.components(separatedBy: "\n")
        let trailing = lines.filter { $0.hasSuffix(" ") || $0.hasSuffix("\t") }.count
        if trailing > 0 {
            problems.append((trailing == 1 ? String(localized: "1 line ending in a space")
                                           : String(localized: "\(trailing) lines ending in spaces"))
                            + firstLine(text) { $0.hasSuffix(" ") || $0.hasSuffix("\t") })
        }
        let blanks = count("\\n\\s*\\n\\s*\\n", in: text)
        if blanks > 0 {
            problems.append(blanks == 1 ? String(localized: "1 run of extra blank lines")
                                        : String(localized: "\(blanks) runs of extra blank lines"))
        }
        if count("[.!?] {2,}[A-Z]", in: text) > 0 && count("[.!?] [A-Z]", in: text) > 0 {
            problems.append(String(localized: "mix of one and two spaces after sentences") + firstLine(text, where: matches("[.!?] {2,}[A-Z]")))
        }
        if lines.contains(where: { $0.hasPrefix("\t") }) && lines.contains(where: { $0.hasPrefix("  ") }) {
            problems.append(String(localized: "indents use both tabs and spaces"))
        }
        let pairs: [(String, String, String)] = [
            ("(", ")", String(localized: "unmatched parentheses")), ("[", "]", String(localized: "unmatched square brackets")),
            ("{", "}", String(localized: "unmatched braces")), ("\u{201C}", "\u{201D}", String(localized: "unmatched curly quotes")),
        ]
        for (open, close, name) in pairs {
            let opens = text.components(separatedBy: open).count - 1
            let closes = text.components(separatedBy: close).count - 1
            if opens != closes { problems.append(String(localized: "\(name): \(opens) opening, \(closes) closing")) }
        }
        if (text.components(separatedBy: "\"").count - 1) % 2 == 1 {
            problems.append(String(localized: "an odd number of straight quotes"))
        }
        return problems
    }
}
