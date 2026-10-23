// Palette.swift — ways to find and learn the app's many commands:
//   * Command palette: type a few letters of anything ("louder", "scan",
//     "battery") and press Return to run it; it also lists presets and the
//     user's own commands
//   * Input help: shortcuts say what they do instead of doing it (like NVDA's
//     input help), to learn the keys safely
//   * Tutorial: short practice lessons that notice when each step is done

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the Controller after it runs a command; the object is the Command.
    static let commandRan = Notification.Name("VoiceOverAudioSplit.commandRan")
}

// MARK: - Command palette

struct PaletteEntry: Identifiable, Hashable {
    enum Action: Hashable {
        case command(Command)
        case preset(UUID)
        case user(UUID)
    }

    let id: String
    let title: String
    let detail: String
    let action: Action

    static func all() -> [PaletteEntry] {
        let preferences = Preferences.shared
        let commands = Command.allCases.filter { $0 != .commandPalette }.map { command in
            PaletteEntry(id: command.rawValue, title: command.title,
                         detail: KeyMap.key(for: command).map { String(localized: "Right Option \($0.name)") } ?? "",
                         action: .command(command))
        }
        let presets = preferences.presets.enumerated().map { index, preset in
            PaletteEntry(id: preset.id.uuidString, title: String(localized: "Preset: \(preset.name)"),
                         detail: index < 9 ? String(localized: "Right Option \(index + 1)") : "", action: .preset(preset.id))
        }
        let users = preferences.userCommands.map { command in
            PaletteEntry(id: command.id.uuidString, title: command.name,
                         detail: command.key.flatMap(Key.named).map { String(localized: "Right Option \($0.name)") } ?? String(localized: "Your command"),
                         action: .user(command.id))
        }
        return commands + presets + users
    }

    /// Entries containing every typed word, in title or keys.
    static func search(_ query: String, in entries: [PaletteEntry] = all()) -> [PaletteEntry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let text = "\(entry.title) \(entry.detail)".lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    func run() {
        switch action {
        case .command(let command): Controller.shared.run(command)
        case .preset(let id):
            if let preset = Preferences.shared.presets.first(where: { $0.id == id }) { Controller.shared.applyPreset(preset) }
        case .user(let id): UserCommands.run(id)
        }
    }
}

struct CommandPaletteView: View {
    var close: () -> Void
    @State private var query = ""
    @State private var selection: PaletteEntry.ID?
    @FocusState private var searchFocused: Bool

    private var results: [PaletteEntry] { PaletteEntry.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Type a command, for example louder, scan or battery"), text: $query)
                .focused($searchFocused)
                .onSubmit { run(results.first { $0.id == selection } ?? results.first) }
            Text(results.isEmpty ? String(localized: "No matching commands") : String(localized: "\(results.count) commands. Press Return to run the first, or choose one below."))
                .font(.caption)
            List(results, selection: $selection) { entry in
                Text(entry.detail.isEmpty ? entry.title : "\(entry.title), \(entry.detail)").tag(entry.id)
            }
            .onKeyPress(.return) {
                run(results.first { $0.id == selection })
                return .handled
            }
        }
        .padding()
        .frame(width: 520, height: 440)
        .onAppear {
            query = ""
            searchFocused = true
        }
    }

    /// Closes the palette first, so commands that act on the front app act on the app
    /// that was in front before the palette opened.
    private func run(_ entry: PaletteEntry?) {
        guard let entry else { return }
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { entry.run() }
    }
}

// MARK: - Input help

enum InputHelp {
    /// Read on the main thread when a shortcut arrives.
    private(set) static var isOn = false

    static func toggle() {
        isOn.toggle()
        Announcer.say(isOn ? String(localized: "Input help on. Press any shortcut to hear what it does. Press the input help key again to stop.")
                           : String(localized: "Input help off"))
    }

    /// Describes a key press instead of running it.
    static func describe(_ title: String, key: String?) {
        Announcer.say(key.map { "\($0): \(title)" } ?? title)
    }
}

// MARK: - Tutorial

struct TutorialLesson {
    let instruction: String
    let command: Command
    let done: String
}

final class Tutorial: ObservableObject {
    static let shared = Tutorial()

    static let lessons: [TutorialLesson] = [
        .init(instruction: String(localized: "Hold the right Option key and press Left Arrow, to put VoiceOver in your left ear."),
              command: .speechLeft, done: String(localized: "VoiceOver is in your left ear, and other sounds are in your right ear.")),
        .init(instruction: String(localized: "Hold Right Option and press Up Arrow, to make speech louder than other sounds."),
              command: .speechLouder, done: String(localized: "Speech is louder. Down Arrow does the opposite.")),
        .init(instruction: String(localized: "Hold Right Option and press Space, to hear what's on."),
              command: .status, done: String(localized: "That's the status summary, any time you need it.")),
        .init(instruction: String(localized: "Hold Right Option and press Q, to quiet everything except VoiceOver. Press it again afterwards to bring sound back."),
              command: .quiet, done: String(localized: "Quiet mode works. Remember to press it again to bring sound back.")),
        .init(instruction: String(localized: "Hold Right Option and press L, then release both and press Space on its own. That's the layer key: after L, any command key works on its own."),
              command: .status, done: String(localized: "The layer key works. After L, slash lists every key.")),
        .init(instruction: String(localized: "Hold Right Option and press Return, to open the command palette. Type a word, such as battery, and press Return."),
              command: .commandPalette, done: String(localized: "That's the command palette. It can find and run every command.")),
        .init(instruction: String(localized: "Hold Right Option and press the left Arrow again, to turn the split off."),
              command: .speechLeft, done: String(localized: "The split is off. You've finished the tutorial. Open it again any time from the menu.")),
    ]

    @Published private(set) var index = 0
    @Published private(set) var active = false
    private var observer: NSObjectProtocol?

    var current: TutorialLesson? { active && Self.lessons.indices.contains(index) ? Self.lessons[index] : nil }

    func start() {
        index = 0
        active = true
        observer = observer ?? NotificationCenter.default.addObserver(forName: .commandRan, object: nil, queue: .main) {
            [weak self] note in
            if let command = note.object as? Command { self?.commandRan(command) }
        }
        speakCurrent(prefix: String(localized: "Tutorial. \(Self.lessons.count) short steps. Step 1."))
    }

    func repeatStep() { speakCurrent() }

    func skip() { advance(saying: nil) }

    func stop() {
        active = false
        Announcer.say(String(localized: "Tutorial stopped"))
    }

    private func commandRan(_ command: Command) {
        guard let lesson = current, lesson.command == command else { return }
        // Let the command's own announcement come first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.advance(saying: String(localized: "Well done. \(lesson.done)")) }
    }

    private func advance(saying message: String?) {
        index += 1
        if index >= Self.lessons.count {
            active = false
            if let message { Announcer.say(message) }
            return
        }
        speakCurrent(prefix: [message, String(localized: "Step \(index + 1).")].compactMap { $0 }.joined(separator: " "))
    }

    private func speakCurrent(prefix: String? = nil) {
        guard let lesson = current else { return }
        Announcer.say([prefix, lesson.instruction].compactMap { $0 }.joined(separator: " "))
    }
}

struct TutorialView: View {
    @ObservedObject var tutorial = Tutorial.shared

    var body: some View {
        Form {
            Section {
                if let lesson = tutorial.current {
                    Text(String(localized: "Step \(tutorial.index + 1) of \(Tutorial.lessons.count)"))
                    Text(lesson.instruction)
                } else {
                    Text(String(localized: "Practice the main shortcuts in \(Tutorial.lessons.count) short steps. Each step is spoken; do it, and the tutorial notices and moves on. You can switch to other apps while you practice."))
                }
            }
            Section {
                if tutorial.active {
                    Button(String(localized: "Repeat Step")) { tutorial.repeatStep() }
                    Button(String(localized: "Skip Step")) { tutorial.skip() }
                    Button(String(localized: "Stop Tutorial")) { tutorial.stop() }
                } else {
                    Button("Start Tutorial") { tutorial.start() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 320)
    }
}
