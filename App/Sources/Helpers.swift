// Helpers.swift — help for the VoiceOver learning curve and for getting bugs fixed:
//   * VoiceOver commands: a searchable list of VoiceOver's own keyboard commands
//     (type "heading" or "rotor" and hear the keys)
//   * Report a bug to Apple: gathers the Mac's details with the user's
//     description into a report for Feedback Assistant or Apple's accessibility email

import AppKit
import CoreAudio
import SwiftUI

// MARK: - VoiceOver commands

struct VoiceOverCommand: Identifiable, Hashable {
    let id = UUID()
    let task: String
    let keys: String
    let group: String
}

enum VoiceOverCommands {
    /// Common commands with the default VoiceOver keys. VO means Control and Option
    /// held together (or Caps Lock, if set in VoiceOver Utility).
    static let all: [VoiceOverCommand] = [
        // General
        .init(task: String(localized: "Turn VoiceOver on or off"), keys: String(localized: "Command F5"), group: String(localized: "General")),
        .init(task: String(localized: "Stop speaking"), keys: String(localized: "Control"), group: String(localized: "General")),
        .init(task: String(localized: "Open the VoiceOver Help menu"), keys: String(localized: "VO H"), group: String(localized: "General")),
        .init(task: String(localized: "Open the Commands menu, a searchable list of every command"), keys: String(localized: "VO H, then H"), group: String(localized: "General")),
        .init(task: String(localized: "Keyboard Help: hear what any key does without doing it"), keys: String(localized: "VO K, Escape to stop"), group: String(localized: "General")),
        .init(task: String(localized: "Open VoiceOver Utility (settings)"), keys: String(localized: "VO F8"), group: String(localized: "General")),
        .init(task: String(localized: "Lock or unlock the VO keys, so you don't have to hold them"), keys: String(localized: "VO Semicolon"), group: String(localized: "General")),
        // Moving around
        .init(task: String(localized: "Move to the next item"), keys: String(localized: "VO Right Arrow"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Move to the previous item"), keys: String(localized: "VO Left Arrow"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Interact with a group (go inside it)"), keys: String(localized: "VO Shift Down Arrow"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Stop interacting with a group (go back out)"), keys: String(localized: "VO Shift Up Arrow"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Press or activate the item"), keys: String(localized: "VO Space"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Open the rotor (headings, links, landmarks and more)"), keys: String(localized: "VO U"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Item Chooser: a searchable list of items in the window"), keys: String(localized: "VO I"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Find text"), keys: String(localized: "VO F"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Go to the top of the window"), keys: String(localized: "VO Home (VO Fn Left Arrow on laptops)"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Go to the bottom of the window"), keys: String(localized: "VO End (VO Fn Right Arrow on laptops)"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Go to the menu bar"), keys: String(localized: "VO M"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Go to the menu extras (icons at the right of the menu bar)"), keys: String(localized: "VO M, twice"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Go to the Dock"), keys: String(localized: "VO D"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Application Chooser: switch between open apps"), keys: String(localized: "VO F1, twice"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Window Chooser: switch between an app's windows"), keys: String(localized: "VO F2, twice"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Move the VoiceOver cursor to the keyboard focus"), keys: String(localized: "VO Shift F4"), group: String(localized: "Moving around")),
        .init(task: String(localized: "Move the keyboard focus to the VoiceOver cursor"), keys: String(localized: "VO Command F4"), group: String(localized: "Moving around")),
        // Reading
        .init(task: String(localized: "Read everything from the VoiceOver cursor onward"), keys: String(localized: "VO A"), group: String(localized: "Reading")),
        .init(task: String(localized: "Read the current word"), keys: String(localized: "VO W"), group: String(localized: "Reading")),
        .init(task: String(localized: "Read the current line"), keys: String(localized: "VO L"), group: String(localized: "Reading")),
        .init(task: String(localized: "Read the current paragraph"), keys: String(localized: "VO P"), group: String(localized: "Reading")),
        .init(task: String(localized: "Describe the item in the VoiceOver cursor"), keys: String(localized: "VO F3"), group: String(localized: "Reading")),
        .init(task: String(localized: "Copy the last thing VoiceOver said to the clipboard"), keys: String(localized: "VO Shift C"), group: String(localized: "Reading")),
        // Web
        .init(task: String(localized: "Next heading"), keys: String(localized: "VO Command H (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Next link"), keys: String(localized: "VO Command L (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Next form control, such as a text field or button"), keys: String(localized: "VO Command J (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Next table"), keys: String(localized: "VO Command T (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Next list"), keys: String(localized: "VO Command X (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Next graphic"), keys: String(localized: "VO Command G (add Shift for previous)"), group: String(localized: "Web")),
        .init(task: String(localized: "Turn Quick Nav on or off (arrow keys move by item)"), keys: String(localized: "Left Arrow and Right Arrow together"), group: String(localized: "Web")),
        .init(task: String(localized: "Turn single-key Quick Nav on or off (H for headings and so on)"), keys: String(localized: "VO Q"), group: String(localized: "Web")),
    ]

    static func search(_ query: String) -> [VoiceOverCommand] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { command in
            let text = "\(command.task) \(command.keys) \(command.group)".lowercased()
            return words.allSatisfy(text.contains)
        }
    }
}

struct VoiceOverCommandsView: View {
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [VoiceOverCommand] { VoiceOverCommands.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(String(localized: "Search, for example heading, rotor or menu"), text: $query)
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { Announcer.say(String(localized: "\(first.task): \(first.keys)")) }
                }
            Text(results.isEmpty ? String(localized: "No matching commands") : String(localized: "\(results.count) commands"))
                .font(.caption)
                .accessibilityAddTraits(.updatesFrequently)
            List(results) { command in
                Text("\(command.task): \(command.keys)")
                    .accessibilityLabel("\(command.task). \(command.keys). \(command.group).")
            }
            Text(String(localized: "VO means Control and Option held together. These are VoiceOver's default keys. VoiceOver's own Commands menu (VO H, then H) lists every command, including any you have changed."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 600, height: 560)
        .onAppear { searchFocused = true }
    }
}

// MARK: - Bug report

enum BugReport {
    /// The Mac's details to include in a report.
    static var details: String {
        var model = [CChar](repeating: 0, count: 256)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let info = Bundle.main.infoDictionary ?? [:]
        return """
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Mac model: \(String(cString: model))
        VoiceOver running: \(NSWorkspace.shared.isVoiceOverEnabled ? "yes" : "no")
        Sound output: \(readString(defaultOutputDevice(), kAudioObjectPropertyName) ?? "unknown")
        Reported with VoiceOver Audio Split \(info["CFBundleShortVersionString"] as? String ?? "") \
        (\(info["CFBundleVersion"] as? String ?? ""))
        """
    }

    static func text(summary: String, steps: String, expected: String) -> String {
        """
        \(summary)

        Steps to reproduce:
        \(steps)

        What I expected:
        \(expected)

        \(details)
        """
    }
}

struct BugReportView: View {
    @State private var summary = ""
    @State private var steps = ""
    @State private var expected = ""

    private var report: String { BugReport.text(summary: summary, steps: steps, expected: expected) }

    var body: some View {
        Form {
            Section(String(localized: "What happened?")) {
                TextField(String(localized: "For example: VoiceOver stops reading Safari search results"), text: $summary, axis: .vertical)
            }
            Section(String(localized: "Steps to make it happen again")) {
                TextField("1. Open Safari. 2. Search for something. 3. ...", text: $steps, axis: .vertical)
            }
            Section(String(localized: "What should have happened?")) {
                TextField(String(localized: "Expected result"), text: $expected, axis: .vertical)
            }
            Section(String(localized: "Details added automatically")) {
                Text(BugReport.details).textSelection(.enabled)
            }
            Section {
                Button(String(localized: "Copy Report and Open Feedback Assistant")) {
                    copy()
                    NSWorkspace.shared.open(URL(string: "applefeedback://")!)
                    Announcer.say(String(localized: "Report copied. In Feedback Assistant, start a new report and paste it."))
                }
                .disabled(summary.isEmpty)
                Button(String(localized: "Email to Apple Accessibility")) {
                    var mail = URLComponents(string: "mailto:accessibility@apple.com")!
                    mail.queryItems = [.init(name: "subject", value: "VoiceOver bug: \(summary.prefix(80))"),
                                       .init(name: "body", value: report)]
                    if let url = mail.url { NSWorkspace.shared.open(url) }
                }
                .disabled(summary.isEmpty)
                Button(String(localized: "Copy Report")) {
                    copy()
                    Announcer.say(String(localized: "Report copied"))
                }
                .disabled(summary.isEmpty)
                Text(String(localized: "Feedback Assistant reports reach Apple's engineers directly. Apple's accessibility team also reads email to accessibility@apple.com. You can also share the bug with the community on AppleVis."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 640)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
