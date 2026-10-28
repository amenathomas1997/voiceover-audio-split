// Practice.swift — VoiceOver practice: the app names a task, such as "go to the
// next heading", and you press the VoiceOver keys for it. While practicing, the
// keys are caught here, so nothing on screen moves. Learn mode says the keys
// along with the task; quiz mode doesn't, and keeps score.

import AppKit
import SwiftUI

struct Drill: Hashable {
    let task: String
    let keys: String
    let keyCode: Int64
    var shift = false
    var command = false

    /// The most useful VoiceOver keys, with VO meaning Control and Option.
    static let all: [Drill] = [
        Drill(task: String(localized: "Move to the next item"), keys: String(localized: "VO Right Arrow"), keyCode: 124),
        Drill(task: String(localized: "Move to the previous item"), keys: String(localized: "VO Left Arrow"), keyCode: 123),
        Drill(task: String(localized: "Read everything from here"), keys: String(localized: "VO A"), keyCode: 0),
        Drill(task: String(localized: "Interact with a group, such as a table or web area"), keys: String(localized: "VO Shift Down Arrow"), keyCode: 125, shift: true),
        Drill(task: String(localized: "Stop interacting with a group"), keys: String(localized: "VO Shift Up Arrow"), keyCode: 126, shift: true),
        Drill(task: String(localized: "Press or activate the item"), keys: String(localized: "VO Space"), keyCode: 49),
        Drill(task: String(localized: "Open the rotor"), keys: String(localized: "VO U"), keyCode: 32),
        Drill(task: String(localized: "Go to the next heading"), keys: String(localized: "VO Command H"), keyCode: 4, command: true),
        Drill(task: String(localized: "Go to the next link"), keys: String(localized: "VO Command L"), keyCode: 37, command: true),
        Drill(task: String(localized: "Go to the next form control"), keys: String(localized: "VO Command J"), keyCode: 38, command: true),
        Drill(task: String(localized: "Go to the next table"), keys: String(localized: "VO Command T"), keyCode: 17, command: true),
        Drill(task: String(localized: "Open the menu bar"), keys: String(localized: "VO M"), keyCode: 46),
        Drill(task: String(localized: "Open the shortcut menu for the item"), keys: String(localized: "VO Shift M"), keyCode: 46, shift: true),
        Drill(task: String(localized: "Open the item chooser to jump to anything by name"), keys: String(localized: "VO I"), keyCode: 34),
        Drill(task: String(localized: "Find text"), keys: String(localized: "VO F"), keyCode: 3),
        Drill(task: String(localized: "Open VoiceOver help"), keys: String(localized: "VO H"), keyCode: 4),
        Drill(task: String(localized: "Turn keyboard help on, to hear what keys do"), keys: String(localized: "VO K"), keyCode: 40),
        Drill(task: String(localized: "Repeat the last thing VoiceOver said"), keys: String(localized: "VO Z"), keyCode: 6),
        Drill(task: String(localized: "Copy the last thing VoiceOver said"), keys: String(localized: "VO Shift C"), keyCode: 8, shift: true),
        Drill(task: String(localized: "Hear where the item is in its window"), keys: String(localized: "VO Shift Command N"), keyCode: 45, shift: true, command: true),
    ]

    /// Whether a key press with these modifiers is this drill's keys. Letters are matched
    /// by the letter typed, so French and German keyboards work.
    func matches(keyCode: Int64, flags: CGEventFlags, letter: Character? = nil) -> Bool {
        KeyCombo(code: self.keyCode, shift: shift, command: command).matches(keyCode: keyCode, flags: flags, letter: letter)
    }
}

final class PracticeModel: ObservableObject {
    static let shared = PracticeModel()

    @Published var running = false
    @Published var learnMode = Preferences.shared.practiceLearnMode { didSet { Preferences.shared.practiceLearnMode = learnMode } }
    @Published var round = 0
    @Published var score = 0
    @Published var current: Drill?
    @Published var lastResult = ""
    let rounds = 10
    private var queue: [Drill] = []
    private var firstTry = true
    /// Counts starts and stops, so a delayed step from an earlier run is ignored.
    private var session = 0
    /// The practice window: keys are only taken while it's in front.
    weak var window: NSWindow?

    func start() {
        queue = Array(Drill.all.shuffled().prefix(rounds))
        round = 0
        score = 0
        running = true
        lastResult = ""
        current = nil
        session += 1
        let thisSession = session
        TypingTrainer.shared.stop()
        LessonRunner.shared.stop()
        Hotkeys.keyObserver = { [weak self] keyCode, flags, event in
            self?.handle(keyCode, flags, letter: KeyCombo.letter(typedBy: event)) ?? false
        }
        let mode = learnMode ? String(localized: "Learn mode: I'll say the keys too.") : String(localized: "Quiz mode.")
        Announcer.say(String(localized: "VoiceOver practice. \(mode) Press Escape to stop."))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard self?.session == thisSession else { return }
            self?.next()
        }
    }

    func stop() {
        // Only release the keys if practice holds them; the typing trainer may be using them.
        guard running else { return }
        Hotkeys.keyObserver = nil
        session += 1
        running = false
        // The task being asked when it stopped wasn't answered.
        let asked = round - (current == nil ? 0 : 1)
        current = nil
        Announcer.say(String(localized: "Practice stopped. \(score) right out of \(asked)."))
    }

    private func next() {
        guard running else { return }
        guard !queue.isEmpty else { return finish() }
        let drill = queue.removeFirst()
        current = drill
        round += 1
        firstTry = true
        Announcer.say(prompt(for: drill))
    }

    private func prompt(for drill: Drill) -> String {
        learnMode ? String(localized: "\(round). \(drill.task): \(drill.keys)") : String(localized: "\(round). \(drill.task)")
    }

    private func finish() {
        Hotkeys.keyObserver = nil
        running = false
        current = nil
        let verdict = score == rounds ? String(localized: "Perfect!") : score >= rounds * 7 / 10 ? String(localized: "Well done.") : String(localized: "Keep practicing.")
        lastResult = String(localized: "\(score) right out of \(rounds). \(verdict)")
        Tones.play(.device)
        Announcer.say(String(localized: "Finished. \(lastResult)"))
    }

    /// Takes Escape and anything pressed with VO; other keys go through as usual.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags, letter: Character?) -> Bool {
        // In another app, VoiceOver works as usual.
        guard NSApp.isActive, window == nil || NSApp.keyWindow === window else { return false }
        if keyCode == Key.escape {
            DispatchQueue.main.async { self.stop() }
            return true
        }
        // While practice runs, every VO key is taken, also between tasks, so nothing moves.
        guard KeyCombo.isVO(flags), running else { return false }
        DispatchQueue.main.async {
            // Between tasks (or after a quick second press) there's nothing to answer.
            guard self.running, let drill = self.current else { return }
            if drill.matches(keyCode: keyCode, flags: flags, letter: letter) {
                if self.firstTry { self.score += 1 }
                self.current = nil
                self.lastResult = String(localized: "Right: \(drill.keys)")
                Tones.play(.louder)
                Announcer.say(String(localized: "Right."))
                let thisSession = self.session
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard self.session == thisSession else { return }
                    self.next()
                }
            } else {
                self.firstTry = false
                Tones.play(.quieter)
                let answer = self.learnMode ? drill.keys : String(localized: "Try again.")
                self.lastResult = String(localized: "Not quite. \(drill.task): \(drill.keys)")
                Announcer.say(String(localized: "Not quite. \(answer)"))
            }
        }
        return true
    }
}

struct PracticeView: View {
    @ObservedObject var model = PracticeModel.shared

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Mode"), selection: $model.learnMode) {
                    Text(String(localized: "Learn: hear the keys with each task")).tag(true)
                    Text(String(localized: "Quiz: hear only the task, and keep score")).tag(false)
                }
                .disabled(model.running)
                if model.running {
                    Button(String(localized: "Stop Practice")) { model.stop() }
                } else {
                    Button(String(localized: "Start Practice")) { model.start() }
                }
                Text(String(localized: "\(model.rounds) tasks. While practicing, VoiceOver keys are caught here, so nothing moves. Press Escape to stop."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Progress")) {
                if let drill = model.current {
                    Text(String(localized: "Task \(model.round) of \(model.rounds): \(drill.task)"))
                }
                Text(String(localized: "Score: \(model.score)"))
                if !model.lastResult.isEmpty { Text(model.lastResult) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .onDisappear { model.stop() }
    }
}
