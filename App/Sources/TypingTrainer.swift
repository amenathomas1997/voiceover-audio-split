// TypingTrainer.swift — a talking typing tutor, in the spirit of Talking Typer and
// TypingClub: lessons add a few keys at a time, starting on the home row. Each key
// is named with its finger and row; a correct key plays a tone, a wrong one says
// what was pressed and what to type. Lessons end with accuracy and words per
// minute, and the best speed for each is kept. There's also a one-minute speed test.
// Finger hints are for the US English (QWERTY) layout, and words are in English.
// Keys are read at the hardware level, ahead of VoiceOver, so Quick Nav can stay on.

import AppKit
import SwiftUI

struct TypingLesson: Identifiable, Hashable {
    let id: String
    let title: String
    /// Keys this lesson adds.
    let keys: String
    var kind = Kind.keys

    enum Kind { case keys, capitals, numbers, punctuation, words, sentences }

    static let all: [TypingLesson] = [
        TypingLesson(id: "asdf", title: String(localized: "Home row, left hand: A S D F"), keys: "asdf"),
        TypingLesson(id: "jkl", title: String(localized: "Home row, right hand: J K L Semicolon"), keys: "jkl;"),
        TypingLesson(id: "gh", title: String(localized: "G and H"), keys: "gh"),
        TypingLesson(id: "ei", title: String(localized: "E and I"), keys: "ei"),
        TypingLesson(id: "ru", title: String(localized: "R and U"), keys: "ru"),
        TypingLesson(id: "ty", title: String(localized: "T and Y"), keys: "ty"),
        TypingLesson(id: "wo", title: String(localized: "W and O"), keys: "wo"),
        TypingLesson(id: "qp", title: String(localized: "Q and P"), keys: "qp"),
        TypingLesson(id: "cm", title: String(localized: "C, M and Comma"), keys: "cm,"),
        TypingLesson(id: "vbn", title: String(localized: "V, B and N"), keys: "vbn"),
        TypingLesson(id: "xz", title: String(localized: "X, Z, Period and Slash"), keys: "xz./"),
        TypingLesson(id: "caps", title: String(localized: "Capital letters with Shift"), keys: "", kind: .capitals),
        TypingLesson(id: "numbers", title: String(localized: "Numbers"), keys: "1234567890", kind: .numbers),
        TypingLesson(id: "punctuation", title: String(localized: "Punctuation: apostrophe, hyphen, question mark and more"), keys: "'-?!:", kind: .punctuation),
        TypingLesson(id: "words", title: String(localized: "Words"), keys: "", kind: .words),
        TypingLesson(id: "sentences", title: String(localized: "Sentences"), keys: "", kind: .sentences),
    ]

    /// Every letter key taught up to and including this lesson.
    var allowed: Set<Character> {
        let index = Self.all.firstIndex(of: self) ?? 0
        return Set(Self.all.prefix(index + 1).flatMap(\.keys).filter { $0.isLetter || ";,./".contains($0) })
    }

    /// The things to type: the new keys alone first, then mixes, then real words.
    func items(count: Int = 20) -> [String] {
        let letters = Array(allowed.filter(\.isLetter))
        let words = TypingWords.common.filter { $0.allSatisfy(allowed.contains) }
        switch kind {
        case .keys:
            let new = Array(keys)
            var items = (new + new).map(String.init)
            let newLetters = new.filter(\.isLetter)
            while items.count < 12 {
                items.append(String((0..<3).map { _ in Bool.random() ? (newLetters.randomElement() ?? new[0]) : (letters.randomElement() ?? new[0]) }))
            }
            let practice = words.filter { word in newLetters.contains { word.contains($0) } }
            items += (practice.isEmpty ? words : practice).shuffled().prefix(count - items.count)
            while items.count < count { items.append(String((0..<4).map { _ in letters.randomElement() ?? new[0] })) }
            return items
        case .capitals:
            return TypingWords.common.shuffled().prefix(count).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        case .numbers:
            return Array(keys).map(String.init) + (0..<(count - 10)).map { _ in String(Int.random(in: 10...9999)) }
        case .punctuation:
            let marks = ["don't", "it's", "well-known", "ready?", "yes!", "note:", "we're", "up-to-date", "why?", "stop!"]
            return marks.shuffled() + TypingWords.common.shuffled().prefix(count - marks.count).map { $0 + [".", ",", "?", "!"].randomElement()! }
        case .words:
            return Array(TypingWords.common.shuffled().prefix(count))
        case .sentences:
            return Array(TypingWords.sentences.shuffled().prefix(6))
        }
    }
}

/// Finger, row and name for each key, for the US layout.
enum KeyHints {
    private static let fingers: [Character: (hand: Int, finger: Int, row: Int)] = {
        // hand: 0 left, 1 right; finger: 0 pinky … 3 index, 4 thumb; row: 0 numbers, 1 top, 2 home, 3 bottom.
        var map: [Character: (Int, Int, Int)] = [:]
        let rows: [(String, Int)] = [("1234567890-", 0), ("qwertyuiop", 1), ("asdfghjkl;'", 2), ("zxcvbnm,./", 3)]
        let fingerForColumn = [0, 1, 2, 3, 3, 3, 3, 2, 1, 0, 0]
        for (keys, row) in rows {
            for (column, key) in keys.enumerated() {
                map[key] = (column < 5 ? 0 : 1, fingerForColumn[min(column, 10)], row)
            }
        }
        map[" "] = (1, 4, 4)
        return map
    }()

    static func name(_ character: Character) -> String {
        switch character {
        case " ": String(localized: "space")
        case ";": String(localized: "semicolon")
        case ",": String(localized: "comma")
        case ".": String(localized: "period")
        case "/": String(localized: "slash")
        case "'": String(localized: "apostrophe")
        case "-": String(localized: "hyphen")
        case "?": String(localized: "question mark")
        case "!": String(localized: "exclamation mark")
        case ":": String(localized: "colon")
        default: character.isUppercase ? String(localized: "capital \(String(character))") : String(character)
        }
    }

    /// NATO spelling alphabet, to tell letters such as M and N apart.
    static func phonetic(_ character: Character) -> String? {
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo", "lima", "mike",
                     "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "x-ray", "yankee", "zulu"]
        guard let ascii = character.lowercased().first?.asciiValue, (97...122).contains(ascii) else { return nil }
        return words[Int(ascii) - 97]
    }

    /// "Left index finger, home row. It has a bump."
    static func hint(_ character: Character) -> String {
        let base = character.lowercased().first ?? character
        let shifted: [Character: Character] = ["?": "/", "!": "1", ":": ";", "\"": "'"]
        guard let place = fingers[shifted[character] ?? base] else { return "" }
        if place.finger == 4 { return String(localized: "Either thumb.") }
        let hand = place.hand == 0 ? String(localized: "Left") : String(localized: "Right")
        let finger = [String(localized: "pinky"), String(localized: "ring finger"), String(localized: "middle finger"), String(localized: "index finger")][place.finger]
        let row = [String(localized: "number row"), String(localized: "top row"), String(localized: "home row"), String(localized: "bottom row")][place.row]
        var text = String(localized: "\(hand) \(finger), \(row).")
        if base == "f" || base == "j" { text += " " + String(localized: "It has a bump.") }
        if character.isUppercase || shifted[character] != nil {
            text += " " + (place.hand == 0 ? String(localized: "Hold Shift with your right pinky.") : String(localized: "Hold Shift with your left pinky."))
        }
        return text
    }
}

final class TypingTrainer: ObservableObject {
    static let shared = TypingTrainer()

    @Published var running = false
    @Published var lesson: TypingLesson?
    @Published var current = ""
    @Published var typed = ""
    @Published var itemNumber = 0
    @Published var itemCount = 0
    @Published var result = ""
    @Published var sayEachKey = Preferences.shared.typingSayEachKey { didSet { Preferences.shared.typingSayEachKey = sayEachKey } }
    @Published var speedTest = false
    private var items: [String] = []
    private var correct = 0
    private var errors = 0
    private var started = Date()
    private var deadline: Date?
    /// Counts starts and stops, so a delayed step from an earlier lesson is ignored.
    private var session = 0
    /// The trainer's window: keys are only taken while it's the one in front, so typing
    /// in the command palette or Settings during a lesson still works.
    weak var window: NSWindow?
    /// Hints are given the first time a key comes up in a lesson, and after a mistake.
    private var hinted = Set<Character>()

    func start(_ lesson: TypingLesson) {
        speedTest = false
        begin(lesson, items: lesson.items(), intro: String(localized: "\(lesson.title). Type each thing I say. Press Escape to stop."))
    }

    func startSpeedTest() {
        speedTest = true
        let lesson = TypingLesson(id: "speed", title: String(localized: "One-minute speed test"), keys: "", kind: .words)
        begin(lesson, items: Array(TypingWords.common.shuffled().prefix(80)).map { $0 + " " },
              intro: String(localized: "One-minute speed test. Type each word and a space. The minute starts with the first word."))
    }

    private func begin(_ lesson: TypingLesson, items: [String], intro: String) {
        PracticeModel.shared.stop()
        LessonRunner.shared.stop()
        self.lesson = lesson
        self.items = items
        itemCount = speedTest ? 0 : items.count
        itemNumber = 0
        correct = 0
        errors = 0
        hinted = []
        result = ""
        current = ""
        typed = ""
        running = true
        deadline = nil
        session += 1
        let thisSession = session
        Hotkeys.keyObserver = { [weak self] keyCode, flags, event in self?.handle(keyCode, flags, event?.characters ?? "") ?? false }
        Announcer.say(intro)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.running, self.session == thisSession else { return }
            self.started = Date()
            if self.speedTest {
                // The minute ends on time, even in the middle of a word.
                let end = Date().addingTimeInterval(60)
                self.deadline = end
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    guard self.running, self.session == thisSession, self.deadline == end else { return }
                    self.finish()
                }
            }
            self.next()
        }
    }

    func stop() {
        guard running else { return }
        Hotkeys.keyObserver = nil
        running = false
        session += 1
        current = ""
        typed = ""
        Announcer.say(String(localized: "Typing practice stopped. \(summary())"))
    }

    private func next() {
        guard running else { return }
        if let deadline, Date() >= deadline { return finish() }
        guard itemNumber < items.count else { return finish() }
        current = items[itemNumber]
        typed = ""
        itemNumber += 1
        Announcer.say(prompt(for: current))
    }

    /// "f, foxtrot. Left index finger, home row." or "Type sad: s, a, d."
    func prompt(for item: String) -> String {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 1, let key = trimmed.first {
            var text = KeyHints.name(key)
            if let word = KeyHints.phonetic(key) { text += ", " + word }
            if !hinted.contains(key) {
                hinted.insert(key)
                text += ". " + KeyHints.hint(key)
            }
            return text
        }
        if speedTest || trimmed.contains(" ") { return trimmed }
        let spelled = trimmed.map(KeyHints.name).joined(separator: ", ")
        return String(localized: "\(trimmed): \(spelled)")
    }

    /// Takes plain and shifted typing and Escape; anything with Command, Control or Option passes through.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags, _ characters: String) -> Bool {
        guard NSApp.isActive, window == nil || NSApp.keyWindow === window else { return false }
        if keyCode == Key.escape {
            DispatchQueue.main.async { self.stop() }
            return true
        }
        // Tab, Delete and the arrows move around the window as usual, and Caps Lock held is VoiceOver's.
        let moving: Set<Int64> = [48, 51, 117, 123, 124, 125, 126]
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty, !KeyCombo.capsLockHeld,
              !moving.contains(keyCode), let character = characters.first, !current.isEmpty else { return false }
        DispatchQueue.main.async { self.type(character) }
        return true
    }

    private func type(_ character: Character) {
        guard running, typed.count < current.count else { return }
        let expected = current[current.index(current.startIndex, offsetBy: typed.count)]
        if character == expected {
            correct += 1
            typed.append(character)
            Tones.playTyping(correct: true)
            if sayEachKey { Announcer.say(KeyHints.name(character)) }
            if typed == current {
                let thisSession = session
                DispatchQueue.main.asyncAfter(deadline: .now() + (speedTest ? 0.05 : 0.5)) {
                    guard self.session == thisSession else { return }
                    self.next()
                }
            }
        } else if character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " " {
            errors += 1
            Tones.playTyping(correct: false)
            Announcer.say(String(localized: "That was \(KeyHints.name(character)). Type \(KeyHints.name(expected)). \(KeyHints.hint(expected))"))
        }
    }

    private var minutes: Double { max(Date().timeIntervalSince(started), 1) / 60 }
    var accuracy: Int { correct + errors == 0 ? 100 : correct * 100 / (correct + errors) }
    /// Standard words per minute: five typed characters count as one word.
    var wordsPerMinute: Int { Int((Double(correct) / 5 / minutes).rounded()) }

    private func summary() -> String {
        String(localized: "\(wordsPerMinute) words per minute, \(accuracy) percent accurate.")
    }

    private func finish() {
        Hotkeys.keyObserver = nil
        running = false
        current = ""
        guard let lesson else { return }
        var text = String(localized: "Finished. \(summary())")
        let preferences = Preferences.shared
        if wordsPerMinute > preferences.typingBest[lesson.id] ?? 0 && accuracy >= 80 {
            preferences.typingBest[lesson.id] = wordsPerMinute
            text += " " + String(localized: "That's your best for this lesson.")
        }
        if accuracy < 90 && !speedTest { text += " " + String(localized: "Try it again slowly; accuracy comes before speed.") }
        result = text
        Tones.play(.device)
        Announcer.say(text)
    }
}

enum TypingWords {
    static let common = """
    a add ads all as ask fall fad dad sad lad lass flask salad glad gas has had hall half jag flag hag shall dash \
    sea see fee feed seed deal heal leaf lake like side ride hide life file fine kid lid did aid said sail jail \
    dear hear fear rule sure true user rush dusk run sun fun us due red read ride ruler drug hug rug \
    the that this they then them there these their it its sit fit hit kit tie yet yes yard stay day may say \
    way who how now two wow own row tow word work world would were where wish with wait was water \
    quit quiet quite put pot top pop pipe paper people place play plus up open hope keep stop \
    can come cake much make many most more mom mice come mean music comic come camp \
    very vote voice brave back best bear bring bank been big but bus nice name new not nine never \
    box six fix exit zero zone zip lazy fox next text extra \
    and are about after again also always any because before between both call could each even every first \
    from give good great help here home into just know last left little long look man mind money must name \
    need number other over part right same school should show small sound still such take tell thing think \
    time under very want well what when which while why will work write year your
    """.split(separator: " ").map(String.init)

    static let sentences = [
        "The quick brown fox jumps over the lazy dog.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump!",
        "VoiceOver reads what is on the screen.",
        "Practice a little every day, and speed will come.",
        "My dog likes to sleep in the sun after lunch.",
        "Please send me the notes from the meeting.",
        "Good typing starts with your fingers on the home row.",
        "We will meet at the library at three o'clock.",
        "Keep your eyes off the keys and trust your fingers.",
    ]
}

struct TypingTrainerView: View {
    @ObservedObject var trainer = TypingTrainer.shared
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        Form {
            if trainer.running {
                Section(trainer.lesson?.title ?? "") {
                    if !trainer.current.isEmpty {
                        Text(String(localized: "Type: \(trainer.current.trimmingCharacters(in: .whitespaces))"))
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    }
                    if trainer.itemCount > 0 { Text(String(localized: "\(trainer.itemNumber) of \(trainer.itemCount)")) }
                    Button(String(localized: "Stop")) { trainer.stop() }
                    Text(String(localized: "Just type; there is no text field. Press Escape to stop."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(String(localized: "Lessons")) {
                    ForEach(TypingLesson.all) { lesson in
                        Button(lessonTitle(lesson)) { trainer.start(lesson) }
                    }
                }
                Section(String(localized: "Speed")) {
                    Button(String(localized: "One-minute speed test") + best("speed")) { trainer.startSpeedTest() }
                }
                Section(String(localized: "Options")) {
                    Picker(String(localized: "Sound for each key typed right"), selection: $preferences.typingSound) {
                        ForEach(TypingSound.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button(String(localized: "Hear It")) { Tones.playTyping(correct: true) }
                    Toggle(String(localized: "Say each key I type correctly"), isOn: $trainer.sayEachKey)
                    Text(String(localized: "Finger hints are for the US English keyboard. Lessons build on each other, so start with the first."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !trainer.result.isEmpty {
                    Section(String(localized: "Last result")) { Text(trainer.result) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onDisappear { trainer.stop() }
    }

    private func lessonTitle(_ lesson: TypingLesson) -> String {
        lesson.title + best(lesson.id)
    }

    private func best(_ id: String) -> String {
        preferences.typingBest[id].map { ", " + String(localized: "best \($0) words per minute") } ?? ""
    }
}
