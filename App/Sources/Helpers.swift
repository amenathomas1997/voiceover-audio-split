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
        .init(task: "Turn VoiceOver on or off", keys: "Command F5", group: "General"),
        .init(task: "Stop speaking", keys: "Control", group: "General"),
        .init(task: "Open the VoiceOver Help menu", keys: "VO H", group: "General"),
        .init(task: "Open the Commands menu, a searchable list of every command", keys: "VO H, then H", group: "General"),
        .init(task: "Keyboard Help: hear what any key does without doing it", keys: "VO K, Escape to stop", group: "General"),
        .init(task: "Open VoiceOver Utility (settings)", keys: "VO F8", group: "General"),
        .init(task: "Lock or unlock the VO keys, so you don't have to hold them", keys: "VO Semicolon", group: "General"),
        // Moving around
        .init(task: "Move to the next item", keys: "VO Right Arrow", group: "Moving around"),
        .init(task: "Move to the previous item", keys: "VO Left Arrow", group: "Moving around"),
        .init(task: "Interact with a group (go inside it)", keys: "VO Shift Down Arrow", group: "Moving around"),
        .init(task: "Stop interacting with a group (go back out)", keys: "VO Shift Up Arrow", group: "Moving around"),
        .init(task: "Press or activate the item", keys: "VO Space", group: "Moving around"),
        .init(task: "Open the rotor (headings, links, landmarks and more)", keys: "VO U", group: "Moving around"),
        .init(task: "Item Chooser: a searchable list of items in the window", keys: "VO I", group: "Moving around"),
        .init(task: "Find text", keys: "VO F", group: "Moving around"),
        .init(task: "Go to the top of the window", keys: "VO Home (VO Fn Left Arrow on laptops)", group: "Moving around"),
        .init(task: "Go to the bottom of the window", keys: "VO End (VO Fn Right Arrow on laptops)", group: "Moving around"),
        .init(task: "Go to the menu bar", keys: "VO M", group: "Moving around"),
        .init(task: "Go to the menu extras (icons at the right of the menu bar)", keys: "VO M, twice", group: "Moving around"),
        .init(task: "Go to the Dock", keys: "VO D", group: "Moving around"),
        .init(task: "Application Chooser: switch between open apps", keys: "VO F1, twice", group: "Moving around"),
        .init(task: "Window Chooser: switch between an app's windows", keys: "VO F2, twice", group: "Moving around"),
        .init(task: "Move the VoiceOver cursor to the keyboard focus", keys: "VO Shift F4", group: "Moving around"),
        .init(task: "Move the keyboard focus to the VoiceOver cursor", keys: "VO Command F4", group: "Moving around"),
        // Reading
        .init(task: "Read everything from the VoiceOver cursor onward", keys: "VO A", group: "Reading"),
        .init(task: "Read the current word", keys: "VO W", group: "Reading"),
        .init(task: "Read the current line", keys: "VO L", group: "Reading"),
        .init(task: "Read the current paragraph", keys: "VO P", group: "Reading"),
        .init(task: "Describe the item in the VoiceOver cursor", keys: "VO F3", group: "Reading"),
        .init(task: "Copy the last thing VoiceOver said to the clipboard", keys: "VO Shift C", group: "Reading"),
        // Web
        .init(task: "Next heading", keys: "VO Command H (add Shift for previous)", group: "Web"),
        .init(task: "Next link", keys: "VO Command L (add Shift for previous)", group: "Web"),
        .init(task: "Next form control, such as a text field or button", keys: "VO Command J (add Shift for previous)", group: "Web"),
        .init(task: "Next table", keys: "VO Command T (add Shift for previous)", group: "Web"),
        .init(task: "Next list", keys: "VO Command X (add Shift for previous)", group: "Web"),
        .init(task: "Next graphic", keys: "VO Command G (add Shift for previous)", group: "Web"),
        .init(task: "Turn Quick Nav on or off (arrow keys move by item)", keys: "Left Arrow and Right Arrow together", group: "Web"),
        .init(task: "Turn single-key Quick Nav on or off (H for headings and so on)", keys: "VO Q", group: "Web"),
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
            TextField("Search, for example heading, rotor or menu", text: $query)
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { Announcer.say("\(first.task): \(first.keys)") }
                }
            Text(results.isEmpty ? "No matching commands" : "\(results.count) commands")
                .font(.caption)
                .accessibilityAddTraits(.updatesFrequently)
            List(results) { command in
                Text("\(command.task): \(command.keys)")
                    .accessibilityLabel("\(command.task). \(command.keys). \(command.group).")
            }
            Text("VO means Control and Option held together. These are VoiceOver's default keys. VoiceOver's own Commands menu (VO H, then H) lists every command, including any you have changed.")
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
            Section("What happened?") {
                TextField("For example: VoiceOver stops reading Safari search results", text: $summary, axis: .vertical)
            }
            Section("Steps to make it happen again") {
                TextField("1. Open Safari. 2. Search for something. 3. ...", text: $steps, axis: .vertical)
            }
            Section("What should have happened?") {
                TextField("Expected result", text: $expected, axis: .vertical)
            }
            Section("Details added automatically") {
                Text(BugReport.details).textSelection(.enabled)
            }
            Section {
                Button("Copy Report and Open Feedback Assistant") {
                    copy()
                    NSWorkspace.shared.open(URL(string: "applefeedback://")!)
                    Announcer.say("Report copied. In Feedback Assistant, start a new report and paste it.")
                }
                .disabled(summary.isEmpty)
                Button("Email to Apple Accessibility") {
                    var mail = URLComponents(string: "mailto:accessibility@apple.com")!
                    mail.queryItems = [.init(name: "subject", value: "VoiceOver bug: \(summary.prefix(80))"),
                                       .init(name: "body", value: report)]
                    if let url = mail.url { NSWorkspace.shared.open(url) }
                }
                .disabled(summary.isEmpty)
                Button("Copy Report") {
                    copy()
                    Announcer.say("Report copied")
                }
                .disabled(summary.isEmpty)
                Text("Feedback Assistant reports reach Apple's engineers directly. Apple's accessibility team also reads email to accessibility@apple.com. You can also share the bug with the community on AppleVis.")
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
