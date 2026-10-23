// Lessons.swift — VoiceOver Lessons: a course for someone new to VoiceOver, from
// turning it on to web pages, editing text and getting help. Each lesson explains a
// skill in plain words, then asks you to press the keys. For commands that are safe
// to carry out here, VoiceOver really does them once you get them right, in the
// lesson window's practice area and practice web page. Each lesson ends with a quick
// check, and finished lessons are remembered.
// Keys are caught at the same level as the app's shortcuts, ahead of VoiceOver, but
// only while a lesson runs and its window is in front.

import AppKit
import SwiftUI
import WebKit

/// A key with its modifiers. `vo` means Control and Option held together (or Caps Lock,
/// when it's set as the VO key in VoiceOver Utility).
struct KeyCombo: Hashable {
    let code: Int64
    var vo = true
    var shift = false
    var command = false
    var option = false

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == code, flags.contains(.maskShift) == shift, flags.contains(.maskCommand) == command else { return false }
        if vo { return Self.isVO(flags) }
        return !flags.contains(.maskControl) && flags.contains(.maskAlternate) == option
    }

    static func isVO(_ flags: CGEventFlags) -> Bool {
        flags.contains([.maskControl, .maskAlternate]) || flags.contains(.maskAlphaShift)
    }

    /// "VO Command Shift H", "Option Left Arrow": what someone pressed, in words.
    static func describe(keyCode: Int64, flags: CGEventFlags) -> String {
        var parts: [String] = []
        let vo = isVO(flags)
        if vo { parts.append("VO") }
        if flags.contains(.maskCommand) { parts.append(String(localized: "Command")) }
        if flags.contains(.maskShift) { parts.append(String(localized: "Shift")) }
        if !vo && flags.contains(.maskAlternate) { parts.append(String(localized: "Option")) }
        if !vo && flags.contains(.maskControl) { parts.append(String(localized: "Control")) }
        parts.append(name(of: keyCode))
        return parts.joined(separator: " ")
    }

    static func name(of code: Int64) -> String {
        let special: [Int64: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            115: String(localized: "Home"), 119: String(localized: "End"), 48: String(localized: "Tab"),
            53: String(localized: "Escape"), 51: String(localized: "Delete"),
        ]
        return special[code] ?? Key.named(code)?.name ?? String(localized: "another key")
    }
}

struct LessonStep: Hashable {
    enum Kind: Hashable {
        /// Explanation, then Return to go on.
        case explain(String)
        /// Press these keys. `realKeys`: VoiceOver carries them out once they're right.
        case practice(task: String, keys: String, combo: KeyCombo, tip: String, realKeys: Bool)
    }
    let kind: Kind

    static func say(_ text: String) -> LessonStep { LessonStep(kind: .explain(text)) }
    static func press(_ task: String, _ keys: String, _ combo: KeyCombo, tip: String = "", real: Bool = false) -> LessonStep {
        LessonStep(kind: .practice(task: task, keys: keys, combo: combo, tip: tip, realKeys: real))
    }
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let steps: [LessonStep]

    var practice: [LessonStep] { steps.filter { if case .practice = $0.kind { true } else { false } } }

    static let all: [Lesson] = [
        Lesson(id: "start", title: String(localized: "1. Getting started: the VO keys"),
               summary: String(localized: "Turning VoiceOver on and off, the VO keys, stopping speech, and keyboard help."), steps: [
            .say(String(localized: "Welcome. VoiceOver is the screen reader built into your Mac. It reads what's on the screen and lets you do everything from the keyboard. Command F5 turns it on and off. On a Mac with Touch ID, you can also hold Command and press Touch ID three times quickly.")),
            .say(String(localized: "Most VoiceOver commands use the VO keys: Control and Option, held down together. In these lessons, VO always means hold Control and Option. If you've set Caps Lock as your VO key in VoiceOver Utility, you can hold Caps Lock instead.")),
            .say(String(localized: "To stop VoiceOver talking, press Control on its own. You can do that at any time, for example during a long passage.")),
            .press(String(localized: "Turn on keyboard help, to explore keys safely"), String(localized: "VO K"), KeyCombo(code: 40),
                   tip: String(localized: "In keyboard help, every key is described instead of done. Press Escape to leave it.")),
            .press(String(localized: "Open the VoiceOver help menu"), String(localized: "VO H"), KeyCombo(code: 4),
                   tip: String(localized: "It lists VoiceOver's commands and has the VoiceOver Getting Started guide.")),
        ]),
        Lesson(id: "moving", title: String(localized: "2. Moving around and pressing things"),
               summary: String(localized: "The VoiceOver cursor, moving item by item, groups, and activating."), steps: [
            .say(String(localized: "VoiceOver has its own cursor, the VoiceOver cursor. It moves from item to item: buttons, text, checkboxes and more. VO Right Arrow moves to the next item, and VO Left Arrow to the previous one. This window's practice area has a few items to move through.")),
            .press(String(localized: "Move to the next item"), String(localized: "VO Right Arrow"), KeyCombo(code: 124), real: true),
            .press(String(localized: "Move to the previous item"), String(localized: "VO Left Arrow"), KeyCombo(code: 123), real: true),
            .say(String(localized: "Some items hold others, such as a toolbar, a list, a table or a web page. These are groups. To go inside a group, interact with it: VO Shift Down Arrow. To come back out, VO Shift Up Arrow. VoiceOver says in and out as you go.")),
            .press(String(localized: "Go inside a group"), String(localized: "VO Shift Down Arrow"), KeyCombo(code: 125, shift: true), real: true),
            .press(String(localized: "Come back out of the group"), String(localized: "VO Shift Up Arrow"), KeyCombo(code: 126, shift: true), real: true),
            .say(String(localized: "To press a button, check a box or follow a link, use VO Space. It does what a click does.")),
            .press(String(localized: "Press the item in the VoiceOver cursor"), String(localized: "VO Space"), KeyCombo(code: 49),
                   tip: String(localized: "Try it for real on the Play button in the practice area.")),
            .say(String(localized: "To jump to the top or bottom of a window, use VO Home and VO End. On a laptop keyboard, add Fn: VO Fn Left Arrow is Home, and VO Fn Right Arrow is End.")),
            .press(String(localized: "Go to the top of the window"), String(localized: "VO Home, or VO Fn Left Arrow"), KeyCombo(code: 115), real: true),
        ]),
        Lesson(id: "reading", title: String(localized: "3. Reading text"),
               summary: String(localized: "Reading everything, lines, sentences, paragraphs, words and characters."), steps: [
            .say(String(localized: "When the VoiceOver cursor is on text, you can read it in pieces of different sizes. VO A reads everything from the cursor onward. Press Control to stop it.")),
            .press(String(localized: "Read everything from here"), String(localized: "VO A"), KeyCombo(code: 0), real: true),
            .say(String(localized: "For smaller pieces: VO L reads the line, VO S the sentence, VO P the paragraph, VO W the word and VO C the character. Press VO W twice to hear the word spelled, and VO C twice to hear the letter phonetically, like alpha or bravo.")),
            .press(String(localized: "Read the current line"), String(localized: "VO L"), KeyCombo(code: 37), real: true),
            .press(String(localized: "Read the current paragraph"), String(localized: "VO P"), KeyCombo(code: 35), real: true),
            .press(String(localized: "Read the current word"), String(localized: "VO W"), KeyCombo(code: 13), real: true),
            .press(String(localized: "Read the current character"), String(localized: "VO C"), KeyCombo(code: 8), real: true),
            .say(String(localized: "Missed something? VO Z says the last thing again, and VO Shift C copies it to the clipboard.")),
            .press(String(localized: "Repeat the last thing VoiceOver said"), String(localized: "VO Z"), KeyCombo(code: 6), real: true),
            .press(String(localized: "Copy the last thing VoiceOver said"), String(localized: "VO Shift C"), KeyCombo(code: 8, shift: true), real: true),
        ]),
        Lesson(id: "apps", title: String(localized: "4. Menus, the Dock and switching apps"),
               summary: String(localized: "The menu bar, menu extras, the Dock, shortcut menus, and moving between apps and windows."), steps: [
            .say(String(localized: "Every app has a menu bar at the top of the screen. VO M moves there. Left and Right Arrow choose a menu, Down Arrow opens it, Up and Down Arrow choose a command, Return uses it, and Escape closes the menu.")),
            .press(String(localized: "Go to the menu bar"), String(localized: "VO M"), KeyCombo(code: 46)),
            .say(String(localized: "Press VO M twice quickly for the menu extras: the icons at the right of the menu bar, such as Wi-Fi, sound, battery and this app's headphones. VO D goes to the Dock, where your apps are kept.")),
            .press(String(localized: "Go to the Dock"), String(localized: "VO D"), KeyCombo(code: 2)),
            .say(String(localized: "VO Shift M opens the shortcut menu for the item in the VoiceOver cursor. It's like a right-click.")),
            .press(String(localized: "Open the shortcut menu"), String(localized: "VO Shift M"), KeyCombo(code: 46, shift: true)),
            .say(String(localized: "To switch apps, hold Command and press Tab; each Tab moves to the next app, and letting go switches. Command Grave Accent switches between the windows of one app. VO F1 twice lists the open apps, and VO F2 twice lists the windows.")),
            .press(String(localized: "Switch to another app"), String(localized: "Command Tab"), KeyCombo(code: 48, vo: false, command: true)),
            .press(String(localized: "Switch to another window of this app"), String(localized: "Command Grave Accent"), KeyCombo(code: 50, vo: false, command: true)),
        ]),
        Lesson(id: "finding", title: String(localized: "5. Finding things: the rotor and item chooser"),
               summary: String(localized: "Jumping to headings, links and more with the rotor, the item chooser and find."), steps: [
            .say(String(localized: "The rotor is a quick way to jump around. Press VO U. Left and Right Arrow change the list, such as headings, links, form controls or windows. Up and Down Arrow choose an item, and Return goes there. Type a few letters to narrow the list, and press Escape to close it.")),
            .press(String(localized: "Open the rotor"), String(localized: "VO U"), KeyCombo(code: 32)),
            .say(String(localized: "The item chooser lists everything in the window. Press VO I, type part of a name, and press Return to go there.")),
            .press(String(localized: "Open the item chooser"), String(localized: "VO I"), KeyCombo(code: 34)),
            .say(String(localized: "To find text, press VO F, type what you're looking for, and press Return.")),
            .press(String(localized: "Find text"), String(localized: "VO F"), KeyCombo(code: 3)),
        ]),
        Lesson(id: "web", title: String(localized: "6. Web pages"),
               summary: String(localized: "Jumping by heading, link, form control and table, on a practice web page."), steps: [
            .say(String(localized: "Web pages can be long, so VoiceOver has keys that jump by kind of item. VO Command H goes to the next heading, VO Command L to the next link, VO Command J to the next form control, such as a text field or button, and VO Command T to the next table. Add Shift to go back: VO Command Shift H is the previous heading.")),
            .say(String(localized: "There's a practice web page at the bottom of this window. Move the VoiceOver cursor to it with VO Right Arrow, then go inside with VO Shift Down Arrow. When you're in it, press Return to go on.")),
            .press(String(localized: "Go to the next heading"), String(localized: "VO Command H"), KeyCombo(code: 4, command: true), real: true),
            .press(String(localized: "Go to the next link"), String(localized: "VO Command L"), KeyCombo(code: 37, command: true), real: true),
            .press(String(localized: "Go to the next form control"), String(localized: "VO Command J"), KeyCombo(code: 38, command: true), real: true),
            .press(String(localized: "Go to the next table"), String(localized: "VO Command T"), KeyCombo(code: 17, command: true), real: true),
            .press(String(localized: "Go back to the previous heading"), String(localized: "VO Command Shift H"), KeyCombo(code: 4, shift: true, command: true), real: true),
            .say(String(localized: "Inside a table, hold VO and use the arrow keys to move from cell to cell; VoiceOver reads the column heading as you go. On real websites, the rotor's headings list (VO U) is often the fastest way to get an overview.")),
        ]),
        Lesson(id: "quicknav", title: String(localized: "7. Quick Nav"),
               summary: String(localized: "Moving with the arrow keys alone, and single letters on web pages."), steps: [
            .say(String(localized: "Quick Nav lets you move with the arrow keys alone, without holding VO. Press Left Arrow and Right Arrow together to turn it on or off. With Quick Nav on, Left and Right Arrow move to the previous or next item, and Up and Down Arrow move by the kind of item chosen in the rotor.")),
            .say(String(localized: "Single-key Quick Nav goes further on web pages: H for the next heading, L for the next link, T for the next table, and Shift with the letter to go back. VO Q turns it on or off.")),
            .press(String(localized: "Turn single-key Quick Nav on or off"), String(localized: "VO Q"), KeyCombo(code: 12)),
            .say(String(localized: "Remember to turn Quick Nav off before typing, or letters move you around instead of typing. When you're in a text field, VoiceOver usually types normally anyway.")),
        ]),
        Lesson(id: "text", title: String(localized: "8. Typing and editing text"),
               summary: String(localized: "Moving the text cursor, selecting, copying, pasting and undoing."), steps: [
            .say(String(localized: "For this lesson, go to the practice text field in this window and type a sentence or two, so there's text to move through. Press Return when you're ready.")),
            .say(String(localized: "In a text field, the arrow keys move the text cursor, and VoiceOver reads as you go: Left and Right Arrow by letter, Up and Down Arrow by line. Option Left and Right Arrow move by word. Command Left and Right Arrow go to the start or end of the line, and Command Up and Down Arrow to the start or end of the text.")),
            .press(String(localized: "Move back one word"), String(localized: "Option Left Arrow"), KeyCombo(code: 123, vo: false, option: true), real: true),
            .press(String(localized: "Go to the end of the line"), String(localized: "Command Right Arrow"), KeyCombo(code: 124, vo: false, command: true), real: true),
            .press(String(localized: "Go to the start of the text"), String(localized: "Command Up Arrow"), KeyCombo(code: 126, vo: false, command: true), real: true),
            .say(String(localized: "Add Shift to select as you move: Shift Option Right Arrow selects the next word. Then Command C copies, Command X cuts, Command V pastes, and Command Z undoes. VoiceOver says what's selected.")),
            .press(String(localized: "Select the next word"), String(localized: "Shift Option Right Arrow"), KeyCombo(code: 124, vo: false, shift: true, option: true), real: true),
            .press(String(localized: "Copy"), String(localized: "Command C"), KeyCombo(code: 8, vo: false, command: true), real: true),
            .press(String(localized: "Undo"), String(localized: "Command Z"), KeyCombo(code: 6, vo: false, command: true), real: true),
            .say(String(localized: "The practice area has a text field to try all of this for real. VO L reads the line you're on, and VO F3 describes the field.")),
        ]),
        Lesson(id: "help", title: String(localized: "9. Getting help and staying in control"),
               summary: String(localized: "Bringing the VoiceOver cursor and keyboard focus together, describing things, locking the VO keys, and VoiceOver Utility."), steps: [
            .say(String(localized: "The VoiceOver cursor and the keyboard focus can end up in different places. VO Shift F4 brings the VoiceOver cursor to the keyboard focus. VO Command F4 brings the keyboard focus to the VoiceOver cursor. On a laptop, hold Fn as well for the F keys.")),
            .press(String(localized: "Move the VoiceOver cursor to the keyboard focus"), String(localized: "VO Shift F4"), KeyCombo(code: 118, shift: true), real: true),
            .press(String(localized: "Move the keyboard focus to the VoiceOver cursor"), String(localized: "VO Command F4"), KeyCombo(code: 118, command: true), real: true),
            .say(String(localized: "To find out where you are: VO F3 describes the item in the VoiceOver cursor, VO F2 the window, and VO F1 the app.")),
            .press(String(localized: "Describe the item in the VoiceOver cursor"), String(localized: "VO F3"), KeyCombo(code: 99), real: true),
            .press(String(localized: "Describe the window"), String(localized: "VO F2"), KeyCombo(code: 120), real: true),
            .say(String(localized: "Tired of holding VO? VO Semicolon locks the VO keys, so every key acts as if you're holding them. Press it again to unlock.")),
            .press(String(localized: "Lock or unlock the VO keys"), String(localized: "VO Semicolon"), KeyCombo(code: 41)),
            .say(String(localized: "VO F8 opens VoiceOver Utility, where you change voices, speaking rate, how much is said and much more. VO H, then H again, opens the Commands menu with every command, and you can type to search it. If VoiceOver ever stops responding, this app's Restart VoiceOver command fixes it.")),
            .press(String(localized: "Open VoiceOver Utility"), String(localized: "VO F8"), KeyCombo(code: 100)),
        ]),
    ]

    /// The last lesson: a mixed review of everything, without the keys being said.
    static let review = Lesson(id: "review", title: String(localized: "10. Review: everything so far"),
                               summary: String(localized: "A mixed quiz from all the lessons."), steps: [])
    static var course: [Lesson] { all + [review] }
}

final class LessonRunner: ObservableObject {
    static let shared = LessonRunner()

    enum Phase: Equatable { case idle, explaining, checking, done }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var lesson: Lesson?
    @Published private(set) var stepNumber = 0
    @Published private(set) var stepCount = 0
    /// What's being said now, also shown on screen and on braille displays.
    @Published private(set) var text = ""
    @Published private(set) var score = ""

    /// The lesson window: keys are only taken while it's in front.
    weak var window: NSWindow?

    private var steps: [LessonStep] = []
    private var index = 0
    private var checkRight = 0
    private var firstTry = true
    private var session = 0

    // MARK: Running

    func start(_ lesson: Lesson) {
        PracticeModel.shared.stop()
        TypingTrainer.shared.stop()
        self.lesson = lesson
        session += 1
        index = 0
        checkRight = 0
        if lesson.id == Lesson.review.id {
            steps = Array(Lesson.all.flatMap(\.practice).shuffled().prefix(12))
            phase = .checking
        } else {
            steps = lesson.steps
            phase = .explaining
        }
        stepCount = steps.count
        Hotkeys.keyObserver = { [weak self] keyCode, flags, _ in self?.handle(keyCode, flags) ?? false }
        let intro = String(localized: "\(lesson.title). Press Return to go on, R to hear something again, and Escape to stop.")
        say(intro)
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard self?.session == thisSession else { return }
            self?.present()
        }
    }

    func stop() {
        guard phase != .idle && phase != .done else { return }
        Hotkeys.keyObserver = nil
        session += 1
        phase = .idle
        say(String(localized: "Lesson stopped. You can pick it up again any time."))
    }

    private var current: LessonStep? { index < steps.count ? steps[index] : nil }

    private func present() {
        guard let step = current else { return lessonPartDone() }
        stepNumber = index + 1
        firstTry = true
        switch step.kind {
        case .explain(let words):
            say(words)
        case .practice(let task, let keys, _, let tip, _):
            if phase == .checking {
                say(String(localized: "\(stepNumber). \(task)?"))
            } else {
                say([String(localized: "Try it: \(task). Press \(keys)."), tip].filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
    }

    private func advance(after seconds: Double) {
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.session == thisSession else { return }
            self.index += 1
            self.present()
        }
    }

    /// The lesson's steps are done: on to its quick check, or finished.
    private func lessonPartDone() {
        guard let lesson else { return }
        if phase == .explaining && !lesson.practice.isEmpty {
            phase = .checking
            steps = lesson.practice.shuffled()
            stepCount = steps.count
            index = 0
            checkRight = 0
            say(String(localized: "Quick check. I'll say a task without the keys; press them. Press R if you want to hear it again."))
            advance(after: 4.5, resettingTo: 0)
            return
        }
        finish()
    }

    private func advance(after seconds: Double, resettingTo start: Int) {
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.session == thisSession else { return }
            self.index = start
            self.present()
        }
    }

    private func finish() {
        guard let lesson else { return }
        Hotkeys.keyObserver = nil
        session += 1
        phase = .done
        score = String(localized: "\(checkRight) of \(steps.count) right first time")
        var done = Preferences.shared.lessonsDone
        if !done.contains(lesson.id) { done.append(lesson.id) }
        Preferences.shared.lessonsDone = done
        let course = Lesson.course
        let next = course.firstIndex(of: lesson).flatMap { $0 + 1 < course.count ? course[$0 + 1] : nil }
        Tones.play(.device)
        say(String(localized: "Lesson finished. \(score).") + " "
            + (next.map { String(localized: "Next: \($0.title).") } ?? String(localized: "That's the whole course. Well done!")))
    }

    // MARK: Keys

    /// Return, R and Escape steer the lesson; while practicing, the answer is checked.
    /// Everything else goes through, so VoiceOver works normally during explanations.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags) -> Bool {
        guard NSApp.isActive, window == nil || NSApp.keyWindow === window else { return false }
        let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty && !flags.contains(.maskAlphaShift)
        if keyCode == Key.escape && plain {
            DispatchQueue.main.async { self.stop() }
            return true
        }
        // Typing in the practice text field: letters go to the field; Return still steers the lesson.
        if plain && keyCode != 36 && NSApp.keyWindow?.firstResponder is NSTextView { return false }
        if plain && keyCode == 15 { // R
            DispatchQueue.main.async { self.repeatCurrent() }
            return true
        }
        guard let step = current else { return false }
        switch step.kind {
        case .explain:
            guard plain && keyCode == 36 else { return false } // Return
            DispatchQueue.main.async { self.index += 1; self.present() }
            return true
        case .practice(let task, let keys, let combo, _, let real):
            if plain && keyCode == 36 {
                DispatchQueue.main.async { self.say(String(localized: "\(task): press \(keys).")) }
                return true
            }
            // Only judge real attempts: something held with the key, or the keys asked for.
            let attempt = KeyCombo.isVO(flags) || flags.contains(.maskCommand) || flags.contains(.maskAlternate) || combo.matches(keyCode: keyCode, flags: flags)
            guard attempt else { return false }
            if combo.matches(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async { self.right(real: real && self.phase == .explaining) }
                // Let VoiceOver really do it, where that's safe.
                return !(real && phase == .explaining)
            }
            let pressed = KeyCombo.describe(keyCode: keyCode, flags: flags)
            DispatchQueue.main.async { self.wrong(pressed: pressed, task: task, keys: keys) }
            return true
        }
    }

    private func right(real: Bool) {
        guard current != nil else { return }
        if firstTry && phase == .checking { checkRight += 1 }
        Tones.play(.louder)
        if real {
            // VoiceOver is speaking the result; give it time.
            advance(after: 3)
        } else {
            say(String(localized: "Right."))
            advance(after: 1.2)
        }
    }

    private func wrong(pressed: String, task: String, keys: String) {
        firstTry = false
        Tones.play(.quieter)
        say(String(localized: "That was \(pressed). \(task): press \(keys)."))
    }

    func repeatCurrent() {
        guard let step = current else { return say(text) }
        switch step.kind {
        case .explain(let words): say(words)
        case .practice(let task, let keys, _, let tip, _):
            say(phase == .checking ? String(localized: "\(task)? The keys are \(keys).")
                                   : [String(localized: "\(task): press \(keys)."), tip].filter { !$0.isEmpty }.joined(separator: " "))
        }
    }

    private func say(_ words: String) {
        text = words
        Announcer.say(words)
    }
}

// MARK: - Window

struct LessonsView: View {
    @ObservedObject var runner = LessonRunner.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var played = ""
    @State private var notes = ""
    @State private var subscribed = false

    var body: some View {
        Form {
            if runner.phase == .idle || runner.phase == .done {
                Section(String(localized: "VoiceOver Lessons")) {
                    Text(String(localized: "A course for learning VoiceOver from the beginning. Each lesson explains a skill, then you try the keys; for safe commands, VoiceOver really does them. Start with lesson 1, or pick any lesson."))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Lesson.course) { lesson in
                        let done = preferences.lessonsDone.contains(lesson.id)
                        Button(done ? String(localized: "\(lesson.title), done") : lesson.title) { runner.start(lesson) }
                            .accessibilityHint(lesson.summary)
                    }
                    if !runner.score.isEmpty { Text(runner.text) }
                }
            } else {
                Section(runner.lesson?.title ?? "") {
                    Text(runner.phase == .checking ? String(localized: "Quick check, \(runner.stepNumber) of \(runner.stepCount)")
                                                   : String(localized: "Step \(runner.stepNumber) of \(runner.stepCount)"))
                    Text(runner.text).font(.title3)
                    HStack {
                        Button(String(localized: "Say It Again")) { runner.repeatCurrent() }
                        Button(String(localized: "Stop Lesson")) { runner.stop() }
                    }
                    Text(String(localized: "Return goes on, R repeats, Escape stops."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Practice area")) {
                Text(String(localized: "Practice area")).font(.headline).accessibilityAddTraits(.isHeader)
                Text(String(localized: "This is a short paragraph to practice reading. It has three sentences. Try reading it by line, by sentence and by word."))
                HStack {
                    Button(String(localized: "Play")) { played = String(localized: "You pressed Play."); Announcer.say(played) }
                    Button(String(localized: "Pause")) { played = String(localized: "You pressed Pause."); Announcer.say(played) }
                    Toggle(String(localized: "Subscribe"), isOn: $subscribed)
                }
                if !played.isEmpty { Text(played) }
                TextField(String(localized: "Practice text field"), text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(String(localized: "Practice web page")) {
                PracticeWebPage()
                    .frame(height: 320)
                    .accessibilityLabel(String(localized: "Practice web page"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 760)
    }
}

/// A small web page with headings, links, a form and a table, for lesson 6.
struct PracticeWebPage: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.loadHTMLString(Self.html, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static var html: String {
        let t = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        return """
        <!doctype html><html lang="\(Locale.current.language.languageCode?.identifier ?? "en")"><head><meta charset="utf-8">
        <style>body{font:16px -apple-system,sans-serif;margin:16px;line-height:1.5}table{border-collapse:collapse}td,th{border:1px solid #999;padding:4px 8px}</style></head><body>
        <h1>\(t(String(localized: "Practice web page")))</h1>
        <p>\(t(String(localized: "Use the VoiceOver keys to jump between headings, links, form controls and the table.")))</p>
        <h2>\(t(String(localized: "Links")))</h2>
        <p><a href="#weather">\(t(String(localized: "Today's weather")))</a> · <a href="#news">\(t(String(localized: "Local news")))</a></p>
        <h2>\(t(String(localized: "A short form")))</h2>
        <form onsubmit="return false"><label>\(t(String(localized: "Your name"))) <input type="text"></label>
        <label><input type="checkbox"> \(t(String(localized: "Send me updates")))</label> <button>\(t(String(localized: "Send")))</button></form>
        <h2>\(t(String(localized: "Opening hours")))</h2>
        <table><tr><th>\(t(String(localized: "Day")))</th><th>\(t(String(localized: "Opens")))</th><th>\(t(String(localized: "Closes")))</th></tr>
        <tr><td>\(t(String(localized: "Monday")))</td><td>9:00</td><td>17:00</td></tr>
        <tr><td>\(t(String(localized: "Saturday")))</td><td>10:00</td><td>14:00</td></tr></table>
        <h2 id="weather">\(t(String(localized: "Today's weather")))</h2><p>\(t(String(localized: "Sunny and mild.")))</p>
        <h2 id="news">\(t(String(localized: "Local news")))</h2><p>\(t(String(localized: "The library has a new audiobook collection.")))</p>
        </body></html>
        """
    }
}
