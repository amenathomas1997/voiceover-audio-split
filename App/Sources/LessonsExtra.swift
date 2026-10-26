// LessonsExtra.swift — VoiceOver Lessons for trainers: lessons a trainer writes
// (.voalesson files, described in docs/CUSTOM-LESSONS.md), key names in words
// ("VO Shift Down Arrow"), and students, so several learners can share one Mac,
// each with their own progress and session reports. Everything stays on the Mac.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Key names

extension KeyCombo {
    /// Key names a lesson file can use, lowercased: US keyboard letters, digits, and named keys.
    static let keyNames: [String: Int64] = {
        var names: [String: Int64] = [:]
        let letters: [(String, Int64)] = [
            ("a", 0), ("b", 11), ("c", 8), ("d", 2), ("e", 14), ("f", 3), ("g", 5), ("h", 4), ("i", 34),
            ("j", 38), ("k", 40), ("l", 37), ("m", 46), ("n", 45), ("o", 31), ("p", 35), ("q", 12), ("r", 15),
            ("s", 1), ("t", 17), ("u", 32), ("v", 9), ("w", 13), ("x", 7), ("y", 16), ("z", 6),
            ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
        ]
        for (name, code) in letters { names[name] = code }
        let functionKeys: [Int64] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in functionKeys.enumerated() { names["f\(index + 1)"] = code }
        let named: [([String], Int64)] = [
            (["left arrow", "left"], 123), (["right arrow", "right"], 124),
            (["up arrow", "up"], 126), (["down arrow", "down"], 125),
            (["space", "spacebar", "space bar"], 49), (["return", "enter"], 36), (["tab"], 48),
            (["escape", "esc"], 53), (["delete", "backspace"], 51), (["forward delete"], 117),
            (["home"], 115), (["end"], 119), (["page up"], 116), (["page down"], 121),
            (["equals", "equal", "plus", "="], 24), (["minus", "hyphen", "-"], 27),
            (["left bracket", "["], 33), (["right bracket", "]"], 30),
            (["semicolon", ";"], 41), (["apostrophe", "quote", "'"], 39),
            (["comma", ","], 43), (["period", "full stop", "."], 47),
            (["slash", "/"], 44), (["backslash", "\\"], 42),
            (["grave accent", "grave", "backtick", "`"], 50),
        ]
        for (spellings, code) in named { for name in spellings { names[name] = code } }
        return names
    }()

    /// Reads keys written in words, the way the lessons say them: "VO Shift Down Arrow",
    /// "Option Command V", "Control Tab". Modifiers come first, then one key. "VO" (or
    /// "Control Option") means the VO keys. Nil if it isn't keys this can read.
    static func parse(_ text: String) -> KeyCombo? {
        let words = text.lowercased().split { $0 == " " || $0 == "\t" || $0 == "+" }.map(String.init)
        var vo = false, shift = false, command = false, option = false, control = false
        var rest: [String] = []
        for word in words {
            // Modifiers only before the key: "H Command" isn't keys.
            if !rest.isEmpty { rest.append(word); continue }
            switch word {
            case "vo": vo = true
            case "shift": shift = true
            case "command", "cmd": command = true
            case "option", "opt", "alt": option = true
            case "control", "ctrl": control = true
            default: rest.append(word)
            }
        }
        guard !rest.isEmpty, let code = keyNames[rest.joined(separator: " ")] else { return nil }
        // Control and Option held together are the VO keys.
        if control && option { vo = true }
        if vo { return KeyCombo(code: code, vo: true, shift: shift, command: command) }
        return KeyCombo(code: code, vo: false, shift: shift, command: command, option: option, control: control)
    }

    /// A key that steers a lesson when pressed on its own (Return, Escape, R, B, H, S), so it can't be practiced.
    var steersLessons: Bool {
        guard !vo, !shift, !command, !option, !control else { return false }
        return code == 36 || code == Key.escape || ["r", "b", "h", "s"].contains(letter)
    }
}

// MARK: - Lesson files

/// A lesson a trainer wrote, with its goals, recap and trainer notes.
struct CustomLesson: Identifiable, Hashable {
    let lesson: Lesson
    let goals: String
    let recap: String
    let trainer: String
    /// Where it's kept, in the app's lessons folder (nil before it's imported).
    var file: URL?

    var id: String { lesson.id }
    var guide: LessonGuide.Entry { LessonGuide.Entry(goals: goals, recap: recap, trainer: trainer) }
}

/// The .voalesson format: JSON describing one lesson. See docs/CUSTOM-LESSONS.md.
enum LessonFile {
    static let fileExtension = "voalesson"
    static let formatVersion = 1
    static var contentType: UTType { UTType(filenameExtension: fileExtension, conformingTo: .json) ?? .json }

    /// Why a file can't be used, in words to say to the trainer.
    struct Problem: LocalizedError, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static let topFields: Set<String> = ["format", "title", "summary", "goals", "recap", "trainerNotes", "steps"]
    static let stepFields: [String: Set<String>] = [
        "explain": ["kind", "text"],
        "practice": ["kind", "task", "keys", "tip"],
        "question": ["kind", "prompt", "options", "answer", "why"],
        "mission": ["kind", "task", "check", "tip"],
    ]
    static let maxSteps = 200

    /// Reads and checks a lesson file. Every problem says where it is ("Step 3: …").
    static func parse(_ data: Data, id: String) throws -> CustomLesson {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = ((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String) ?? ""
            throw Problem([String(localized: "This file isn't a lesson file: its text isn't valid JSON."), detail]
                .filter { !$0.isEmpty }.joined(separator: " "))
        }
        guard let top = json as? [String: Any] else {
            throw Problem(String(localized: "This file isn't a lesson file: it must hold one lesson, between curly braces."))
        }
        if let unknown = top.keys.sorted().first(where: { !topFields.contains($0) }) {
            throw Problem(String(localized: "Unknown field '\(unknown)'. A lesson can have: format, title, summary, goals, recap, trainerNotes and steps."))
        }
        if let format = top["format"] {
            guard let version = integer(format), version == formatVersion else {
                throw Problem(String(localized: "This lesson is format \(String(describing: format)); this version of the app reads format \(formatVersion)."))
            }
        }
        let title = try text(top, "title", step: nil, required: true)
        guard title.count <= 120 else { throw Problem(String(localized: "The title is too long: keep it under 120 characters.")) }
        let summary = try text(top, "summary", step: nil, required: false)
        let goals = try text(top, "goals", step: nil, required: false)
        let recap = try text(top, "recap", step: nil, required: false)
        let trainer = try text(top, "trainerNotes", step: nil, required: false)
        guard let rawSteps = top["steps"] else { throw Problem(String(localized: "The lesson has no steps: add a 'steps' list.")) }
        guard let list = rawSteps as? [Any], !list.isEmpty else {
            throw Problem(String(localized: "'steps' must be a list of steps, between square brackets, with at least one step."))
        }
        guard list.count <= maxSteps else { throw Problem(String(localized: "The lesson has \(list.count) steps; the most is \(maxSteps).")) }

        var steps: [LessonStep] = []
        var practiced: [KeyCombo: Int] = [:]
        for (index, raw) in list.enumerated() {
            let number = index + 1
            guard let step = raw as? [String: Any] else {
                throw problem(number, String(localized: "each step must be between curly braces, with a kind."))
            }
            guard let kindValue = step["kind"] else {
                throw problem(number, String(localized: "'kind' is missing. Use explain, practice, question or mission."))
            }
            guard let kind = kindValue as? String, let allowed = stepFields[kind] else {
                throw problem(number, String(localized: "unknown kind '\(String(describing: kindValue))'. Use explain, practice, question or mission."))
            }
            if let unknown = step.keys.sorted().first(where: { !allowed.contains($0) }) {
                let fields = allowed.subtracting(["kind"]).sorted().joined(separator: ", ")
                throw problem(number, String(localized: "unknown field '\(unknown)'. A \(kind) step can have: \(fields)."))
            }
            switch kind {
            case "explain":
                steps.append(.say(try text(step, "text", step: number, required: true)))
            case "practice":
                let task = try text(step, "task", step: number, required: true)
                let keys = try text(step, "keys", step: number, required: true)
                let tip = try text(step, "tip", step: number, required: false)
                guard let combo = KeyCombo.parse(keys) else {
                    throw problem(number, String(localized: "unknown key name '\(keys)'. Write any held keys first (VO, Command, Shift, Option, Control), then one key, such as H, Down Arrow or F8."))
                }
                if combo.steersLessons {
                    throw problem(number, String(localized: "'\(keys)' on its own steers the lesson (Return goes on, R repeats, B goes back, H gives a hint, S skips, Escape stops), so it can't be practiced. Add a key held with it, such as VO or Command."))
                }
                if let earlier = practiced[combo] {
                    throw problem(number, String(localized: "the keys '\(keys)' are already practiced in step \(earlier). Each practice step in a lesson needs different keys, so the quick check can tell them apart."))
                }
                practiced[combo] = number
                steps.append(.press(task, keys, combo, tip: tip))
            case "question":
                let prompt = try text(step, "prompt", step: number, required: true)
                let why = try text(step, "why", step: number, required: true)
                guard let rawOptions = step["options"] else { throw problem(number, String(localized: "'options' is missing.")) }
                guard let options = rawOptions as? [Any] else {
                    throw problem(number, String(localized: "'options' must be a list of answers, between square brackets."))
                }
                guard (2...4).contains(options.count) else {
                    throw problem(number, String(localized: "a question needs 2, 3 or 4 options, answered with the number keys; this one has \(options.count)."))
                }
                var answers: [String] = []
                for (optionIndex, option) in options.enumerated() {
                    guard let words = (option as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
                        throw problem(number, String(localized: "option \(optionIndex + 1) must be some text, in quotes."))
                    }
                    answers.append(words)
                }
                guard let rawAnswer = step["answer"] else {
                    throw problem(number, String(localized: "'answer' is missing: give the number of the right option, starting at 1."))
                }
                guard let answer = integer(rawAnswer), (1...answers.count).contains(answer) else {
                    throw problem(number, String(localized: "'answer' must be the number of the right option, from 1 to \(answers.count)."))
                }
                steps.append(.ask(prompt, answers, answer: answer - 1, why: why))
            default: // mission
                let task = try text(step, "task", step: number, required: true)
                let tip = try text(step, "tip", step: number, required: false)
                let check = try text(step, "check", step: number, required: true)
                guard let mission = mission(check) else {
                    throw problem(number, String(localized: "'check' must be yourWord, or the bundle ID of the app that should be in front, such as com.apple.Safari."))
                }
                steps.append(.doIt(task, mission, tip: tip))
            }
        }
        let lesson = Lesson(id: id, title: title,
                            summary: summary.isEmpty ? String(localized: "A lesson from your trainer.") : summary, steps: steps)
        return CustomLesson(lesson: lesson, goals: goals, recap: recap, trainer: trainer)
    }

    /// "yourWord" (Return says it's done) or an app's bundle ID (done when that app is in front).
    static func mission(_ check: String) -> Mission? {
        if check.lowercased() == "yourword" { return .yourWord }
        let parts = check.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return .frontApp(check)
    }

    private static func problem(_ step: Int, _ message: String) -> Problem {
        Problem(String(localized: "Step \(step): \(message)"))
    }

    /// A text field, trimmed. Missing optional fields are empty.
    private static func text(_ object: [String: Any], _ key: String, step: Int?, required: Bool) throws -> String {
        func fail(_ message: String) -> Problem { step.map { problem($0, message) } ?? Problem(message.prefix(1).uppercased() + message.dropFirst()) }
        guard let value = object[key] else {
            if required { throw fail(String(localized: "'\(key)' is missing.")) }
            return ""
        }
        guard let words = value as? String else { throw fail(String(localized: "'\(key)' must be text, in quotes.")) }
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if required && trimmed.isEmpty { throw fail(String(localized: "'\(key)' is empty.")) }
        return trimmed
    }

    /// A whole number from JSON (not true or false, which JSON also stores as numbers here).
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double == double.rounded() ? Int(double) : nil
    }

    /// A short lesson showing every kind of step, for trainers to start from.
    static let sample = """
    {
      "format": 1,
      "title": "Our library's website",
      "summary": "Finding opening hours and searching the catalogue.",
      "goals": "going to the library's website, jumping to its headings, and searching the catalogue.",
      "recap": "Command L goes to the address field. VO Command H jumps by heading, and VO U opens the rotor.",
      "trainerNotes": "Open the library's site in Safari before starting. Let the learner find the opening hours on their own.",
      "steps": [
        { "kind": "explain", "text": "In this lesson you'll use the library's website. Open Safari with Spotlight: Command Space, type Safari, and press Return." },
        { "kind": "mission", "task": "Open Safari, for real.", "check": "com.apple.Safari", "tip": "Come back to the lessons with Command Tab when you hear Done." },
        { "kind": "practice", "task": "Go to the address field", "keys": "Command L" },
        { "kind": "practice", "task": "Go to the next heading", "keys": "VO Command H", "tip": "Headings are like the titles of a newspaper's articles." },
        { "kind": "practice", "task": "Open the rotor", "keys": "VO U" },
        { "kind": "question", "prompt": "Where are the opening hours usually found?", "options": ["Under a heading such as Visit or Hours", "In the address field", "In the Dock"], "answer": 1, "why": "Most websites put opening hours under their own heading, so VO Command H finds them quickly." },
        { "kind": "mission", "task": "Now for real: find the library's opening hours, and press Return here when you've heard them.", "check": "yourWord" }
      ]
    }

    """
}

/// Lessons a trainer imported, kept as .voalesson files in the app's own folder.
final class CustomLessons: ObservableObject {
    static let shared = CustomLessons(directory: defaultDirectory)

    /// Application Support (inside the app's sandbox container), in a Lessons folder.
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Lessons", isDirectory: true)
    }

    let directory: URL
    @Published private(set) var lessons: [CustomLesson] = []
    /// Files in the folder that couldn't be read, with why.
    @Published private(set) var unreadable: [String] = []

    init(directory: URL) {
        self.directory = directory
        reload()
    }

    func guide(for id: String) -> LessonGuide.Entry? { lessons.first { $0.id == id }?.guide }

    /// Reads every lesson file in the folder.
    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var found: [CustomLesson] = [], problems: [String] = []
        for file in files where file.pathExtension.lowercased() == LessonFile.fileExtension {
            do {
                var lesson = try LessonFile.parse(Data(contentsOf: file), id: Self.id(for: file))
                lesson.file = file
                found.append(lesson)
            } catch {
                problems.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        lessons = found.sorted { $0.lesson.title.localizedStandardCompare($1.lesson.title) == .orderedAscending }
        unreadable = problems.sorted()
    }

    static func id(for file: URL) -> String { "custom." + file.deletingPathExtension().lastPathComponent }

    /// "Our library's website" → "our-library-s-website": a file name that stays the same,
    /// so importing a new version of a lesson replaces it and keeps the student's progress.
    static func fileName(for title: String) -> String {
        var name = ""
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII { name.unicodeScalars.append(scalar) }
            else if !name.isEmpty && !name.hasSuffix("-") { name += "-" }
        }
        while name.hasSuffix("-") { name.removeLast() }
        return String((name.isEmpty ? "lesson" : name).prefix(40))
    }

    /// Checks a lesson and keeps a copy in the lessons folder. Throws a LessonFile.Problem
    /// (or a file error) if it can't be used. A lesson with the same title is replaced.
    @discardableResult
    func importData(_ data: Data) throws -> (lesson: CustomLesson, replaced: Bool) {
        let checked = try LessonFile.parse(data, id: "custom.check")
        let file = directory.appendingPathComponent(Self.fileName(for: checked.lesson.title))
            .appendingPathExtension(LessonFile.fileExtension)
        let replaced = FileManager.default.fileExists(atPath: file.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        reload()
        guard let lesson = lessons.first(where: { $0.file?.standardizedFileURL == file.standardizedFileURL }) else {
            throw LessonFile.Problem(String(localized: "The lesson was saved but couldn't be read back."))
        }
        return (lesson, replaced)
    }

    func remove(_ lesson: CustomLesson) throws {
        if let file = lesson.file { try FileManager.default.removeItem(at: file) }
        reload()
    }

    // MARK: Panels

    /// Import a Lesson…: choose a .voalesson file. Says what happened, including exactly what's wrong.
    @MainActor
    func importWithPanel() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [LessonFile.contentType, .json]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a VoiceOver lesson file, ending in .voalesson.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let (lesson, replaced) = try importData(Data(contentsOf: url))
            return replaced ? String(localized: "Updated \(lesson.lesson.title). It's in Your lessons.")
                            : String(localized: "Imported \(lesson.lesson.title). It's in Your lessons.")
        } catch {
            return String(localized: "Couldn't import \(url.lastPathComponent). \(error.localizedDescription)")
        }
    }

    /// Saves the sample lesson, for a trainer to copy and change.
    @MainActor
    static func saveSampleWithPanel() -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Sample lesson") + "." + LessonFile.fileExtension
        panel.allowedContentTypes = [LessonFile.contentType]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data(LessonFile.sample.utf8).write(to: url, options: .atomic)
            return String(localized: "Sample lesson saved as \(url.lastPathComponent). Open it in TextEdit to change it, then import it.")
        } catch {
            return String(localized: "Couldn't save the sample lesson.")
        }
    }
}

// MARK: - Students and progress

/// Where the current student's progress is also kept: Preferences, so the rest of the app
/// (daily practice by voice, settings export) sees it.
protocol LessonProgressMirror: AnyObject {
    var lessonsDone: [String] { get set }
    var lessonsMissed: [String] { get set }
    var lessonSchedule: [String: [Double]] { get set }
    var lessonChallengeBest: Int { get set }
}

extension Preferences: LessonProgressMirror {}

/// Lesson progress for each student sharing this Mac. All lesson reads and writes of
/// lessons done, missed keys, the practice schedule and the challenge best go through
/// here, for the current student. The current student's progress is also kept in
/// Preferences, which is where it's read from (so a settings import still counts); the
/// others' is kept here, under "lessonStudents" in UserDefaults, with everyone's reports.
final class LessonProgress: ObservableObject {
    static let shared = LessonProgress(defaults: .standard, mirror: Preferences.shared)
    /// The first student, who has the progress from before there were students.
    static let meID = "me"
    static let storeKey = "lessonStudents"
    /// Reports kept for each student; the oldest go first.
    static let maxSessions = 1000

    struct Student: Codable, Identifiable, Hashable {
        let id: String
        var name: String
    }

    /// One finished lesson, for the student's report.
    struct Session: Codable, Identifiable, Hashable {
        var id = UUID()
        let date: Date
        let lessonID: String
        let lesson: String
        let score: String
        let mode: String
        let lines: [String]
    }

    struct Record: Codable, Equatable {
        var done: [String] = []
        var missed: [String] = []
        var schedule: [String: [Double]] = [:]
        var challengeBest = 0
        var sessions: [Session] = []
    }

    private struct Saved: Codable {
        var students: [Student]
        var current: String
        var records: [String: Record]
    }

    @Published private(set) var students: [Student]
    @Published private(set) var currentID: String
    private var records: [String: Record]
    private let defaults: UserDefaults
    private let mirror: LessonProgressMirror

    init(defaults: UserDefaults, mirror: LessonProgressMirror) {
        self.defaults = defaults
        self.mirror = mirror
        if let data = defaults.data(forKey: Self.storeKey), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           !saved.students.isEmpty {
            students = saved.students
            currentID = saved.students.contains { $0.id == saved.current } ? saved.current : saved.students[0].id
            records = saved.records
            // Preferences has the current student's latest progress (it may have come from a settings import).
            records[currentID, default: Record()].take(from: mirror)
        } else {
            // The first time: the progress so far becomes "Me", without losing anything.
            var me = Record()
            me.done = defaults.stringArray(forKey: "lessonsDone") ?? []
            me.missed = defaults.stringArray(forKey: "lessonsMissed") ?? []
            me.schedule = defaults.dictionary(forKey: "lessonSchedule") as? [String: [Double]] ?? [:]
            me.challengeBest = defaults.integer(forKey: "lessonChallengeBest")
            students = [Student(id: Self.meID, name: String(localized: "Me"))]
            currentID = Self.meID
            records = [Self.meID: me]
            put(me)
        }
        save()
    }

    // MARK: The current student's progress

    var done: [String] {
        get { mirror.lessonsDone }
        set { change { $0.done = newValue }; if mirror.lessonsDone != newValue { mirror.lessonsDone = newValue } }
    }
    var missed: [String] {
        get { mirror.lessonsMissed }
        set { change { $0.missed = newValue }; if mirror.lessonsMissed != newValue { mirror.lessonsMissed = newValue } }
    }
    var schedule: [String: [Double]] {
        get { mirror.lessonSchedule }
        set { change { $0.schedule = newValue }; if mirror.lessonSchedule != newValue { mirror.lessonSchedule = newValue } }
    }
    var challengeBest: Int {
        get { mirror.lessonChallengeBest }
        set { change { $0.challengeBest = newValue }; if mirror.lessonChallengeBest != newValue { mirror.lessonChallengeBest = newValue } }
    }

    var current: Student { students.first { $0.id == currentID } ?? students[0] }
    var sessions: [Session] { sessions(for: currentID) }
    func sessions(for id: String) -> [Session] { records[id]?.sessions ?? [] }
    func lessonsDone(for id: String) -> [String] { id == currentID ? done : records[id]?.done ?? [] }

    /// A finished lesson, in the current student's reports.
    func record(lessonID: String, lesson: String, score: String, mode: String, lines: [String], date: Date = Date()) {
        change { record in
            record.sessions.append(Session(date: date, lessonID: lessonID, lesson: lesson, score: score, mode: mode, lines: lines))
            if record.sessions.count > Self.maxSessions { record.sessions.removeFirst(record.sessions.count - Self.maxSessions) }
        }
    }

    // MARK: Students

    /// Switches to another student: their progress replaces the current one in Preferences.
    func switchTo(_ id: String) {
        guard id != currentID, students.contains(where: { $0.id == id }) else { return }
        records[currentID, default: Record()].take(from: mirror)
        currentID = id
        put(records[id] ?? Record())
        save()
    }

    /// By name, as said or typed ("Switch student to Sam"). False if there's no such student.
    @discardableResult
    func switchTo(named name: String) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Spoken names come without accents or punctuation ("Maria" for "María").
        guard let student = students.first(where: { VoiceCommands.normalize($0.name) == VoiceCommands.normalize(wanted) }) else { return false }
        switchTo(student.id)
        return true
    }

    /// A new student, starting from the beginning. Nil if the name is empty or already used.
    @discardableResult
    func add(name: String) -> Student? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isTaken(name) else { return nil }
        let student = Student(id: UUID().uuidString, name: name)
        students.append(student)
        records[student.id] = Record()
        save()
        return student
    }

    @discardableResult
    func rename(_ id: String, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = students.firstIndex(where: { $0.id == id }),
              !isTaken(name, except: id) else { return false }
        students[index].name = name
        save()
        return true
    }

    /// Removes a student and their progress and reports. "Me" stays; removing the current
    /// student switches to Me.
    @discardableResult
    func remove(_ id: String) -> Bool {
        guard id != Self.meID, students.contains(where: { $0.id == id }) else { return false }
        if id == currentID { switchTo(Self.meID) }
        students.removeAll { $0.id == id }
        records[id] = nil
        save()
        return true
    }

    private func isTaken(_ name: String, except id: String? = nil) -> Bool {
        students.contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func change(_ apply: (inout Record) -> Void) {
        objectWillChange.send()
        apply(&records[currentID, default: Record()])
        save()
    }

    /// Puts a student's progress in Preferences, only where it differs.
    private func put(_ record: Record) {
        if mirror.lessonsDone != record.done { mirror.lessonsDone = record.done }
        if mirror.lessonsMissed != record.missed { mirror.lessonsMissed = record.missed }
        if mirror.lessonSchedule != record.schedule { mirror.lessonSchedule = record.schedule }
        if mirror.lessonChallengeBest != record.challengeBest { mirror.lessonChallengeBest = record.challengeBest }
    }

    private func save() {
        let saved = Saved(students: students, current: currentID, records: records)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.storeKey) }
    }

    // MARK: Reports

    /// The student's report as plain text, for a trainer or a vocational rehabilitation counselor.
    func reportText(for id: String) -> String {
        let name = students.first { $0.id == id }?.name ?? ""
        let course = Set(Lesson.course.map(\.id))
        return Self.reportText(student: name, sessions: sessions(for: id),
                               done: lessonsDone(for: id).filter(course.contains).count, total: Lesson.course.count)
    }

    func reportCSV(for id: String) -> String {
        Self.reportCSV(student: students.first { $0.id == id }?.name ?? "", sessions: sessions(for: id))
    }

    static func reportText(student: String, sessions: [Session], done: Int, total: Int, made: Date = Date()) -> String {
        let format = DateFormatter()
        format.dateStyle = .medium
        format.timeStyle = .short
        var lines = [String(localized: "VoiceOver Lessons report: \(student)"),
                     String(localized: "Made on \(format.string(from: made))"),
                     String(localized: "Lessons done: \(done) of \(total)"),
                     String(localized: "Sessions: \(sessions.count)")]
        for session in sessions {
            lines.append("")
            lines.append("\(format.string(from: session.date)): \(session.lesson)")
            let how = LessonMode(rawValue: session.mode)?.shortName ?? ""
            lines.append([session.score, how].filter { !$0.isEmpty }.joined(separator: ", "))
            lines += session.lines.map { "  " + $0 }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per session: Student, Date, Lesson, Score, Mode, Details.
    static func reportCSV(student: String, sessions: [Session]) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        let header = [String(localized: "Student"), String(localized: "Date"), String(localized: "Lesson"),
                      String(localized: "Score"), String(localized: "Mode"), String(localized: "Details")]
        let rows = sessions.map { session in
            [student, format.string(from: session.date), session.lesson, session.score,
             LessonMode(rawValue: session.mode)?.shortName ?? session.mode, session.lines.joined(separator: " | ")]
        }
        return ([header] + rows).map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quoted when needed; a leading = + - or @ is made harmless for spreadsheets.
    static func csvField(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    @MainActor
    func exportWithPanel(csv: Bool) -> String? {
        let name = current.name
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "VoiceOver Lessons report, \(name)") + (csv ? ".csv" : ".txt")
        panel.allowedContentTypes = [csv ? .commaSeparatedText : .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data((csv ? reportCSV(for: currentID) : reportText(for: currentID)).utf8).write(to: url, options: .atomic)
            return String(localized: "Report saved as \(url.lastPathComponent).")
        } catch {
            return String(localized: "Couldn't save the report.")
        }
    }
}

extension LessonProgress.Record {
    /// The progress Preferences has (for the current student).
    mutating func take(from mirror: LessonProgressMirror) {
        done = mirror.lessonsDone
        missed = mirror.lessonsMissed
        schedule = mirror.lessonSchedule
        challengeBest = mirror.lessonChallengeBest
    }
}

extension LessonMode {
    /// "on your own", "with a trainer": for reports.
    var shortName: String {
        switch self {
        case .onYourOwn: String(localized: "on your own")
        case .withTrainer: String(localized: "with a trainer")
        }
    }
}

// MARK: - Window sections

/// Students: who's learning now, so each learner keeps their own progress and reports.
struct StudentsSection: View {
    @ObservedObject var progress = LessonProgress.shared
    @State private var naming: Naming?
    @State private var name = ""
    @State private var removing = false
    @State private var message = ""

    private enum Naming { case adding, renaming }

    var body: some View {
        Section(String(localized: "Students")) {
            Text(String(localized: "For trainers: each student keeps their own progress and session reports on this Mac. Me has the progress from before."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(String(localized: "Student"), selection: Binding(get: { progress.currentID }, set: choose)) {
                ForEach(progress.students) { Text($0.name).tag($0.id) }
            }
            HStack {
                Button(String(localized: "Add Student…")) { name = ""; naming = .adding }
                Button(String(localized: "Rename…")) { name = progress.current.name; naming = .renaming }
                Button(String(localized: "Remove…")) { removing = true }
                    .disabled(progress.currentID == LessonProgress.meID)
            }
            Text(String(localized: "\(progress.sessions.count) sessions in \(progress.current.name)'s report"))
            HStack {
                Button(String(localized: "Export Report as Text…")) { tell(progress.exportWithPanel(csv: false)) }
                Button(String(localized: "Export Report as CSV…")) { tell(progress.exportWithPanel(csv: true)) }
                Button(String(localized: "Copy Report")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(progress.reportText(for: progress.currentID), forType: .string)
                    tell(String(localized: "\(progress.current.name)'s report copied."))
                }
            }
            if !message.isEmpty { Text(message) }
        }
        .alert(naming == .renaming ? String(localized: "Rename Student") : String(localized: "Add Student"),
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(String(localized: "Name"), text: $name)
            Button(naming == .renaming ? String(localized: "Rename") : String(localized: "Add")) { finishNaming() }
            Button(String(localized: "Cancel"), role: .cancel) { naming = nil }
        } message: {
            Text(String(localized: "A first name is enough. It stays on this Mac."))
        }
        .alert(String(localized: "Remove \(progress.current.name)?"), isPresented: $removing) {
            Button(String(localized: "Remove"), role: .destructive) {
                let gone = progress.current.name
                if progress.remove(progress.currentID) { tell(String(localized: "Removed \(gone). Now learning as \(progress.current.name).")) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Their progress and session reports are removed too. Export their report first if you need it."))
        }
    }

    private func choose(_ id: String) {
        progress.switchTo(id)
        let course = Set(Lesson.course.map(\.id))
        let done = progress.done.filter(course.contains).count
        tell(String(localized: "Now learning as \(progress.current.name). \(done) of \(Lesson.course.count) lessons done."))
    }

    private func finishNaming() {
        let mode = naming
        naming = nil
        if mode == .renaming {
            tell(progress.rename(progress.currentID, to: name) ? String(localized: "Renamed to \(name).")
                                                               : String(localized: "Choose a name that isn't empty or already used."))
        } else if let student = progress.add(name: name) {
            choose(student.id)
        } else {
            tell(String(localized: "Choose a name that isn't empty or already used."))
        }
    }

    private func tell(_ words: String?) {
        guard let words else { return }
        message = words
        LessonVoice.say(words)
    }
}

/// Your lessons: lessons a trainer imported from .voalesson files.
struct CustomLessonsSection: View {
    @ObservedObject var lessons = CustomLessons.shared
    @ObservedObject var progress = LessonProgress.shared
    @State private var removing: CustomLesson?
    @State private var message = ""

    var body: some View {
        Section(String(localized: "Your lessons")) {
            if lessons.lessons.isEmpty {
                Text(String(localized: "Lessons from a trainer appear here. Import a .voalesson file, or save the sample file to write your own."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(lessons.lessons) { custom in
                HStack {
                    let done = progress.done.contains(custom.id)
                    Button(done ? String(localized: "\(custom.lesson.title), done") : custom.lesson.title) {
                        LessonRunner.shared.start(custom.lesson)
                    }
                    .accessibilityHint(custom.lesson.summary)
                    Spacer()
                    Button(String(localized: "Remove")) { removing = custom }
                        .accessibilityLabel(String(localized: "Remove \(custom.lesson.title)"))
                }
            }
            ForEach(lessons.unreadable, id: \.self) { Text(String(localized: "Can't read \($0)")) }
            HStack {
                Button(String(localized: "Import a Lesson…")) { tell(lessons.importWithPanel()) }
                Button(String(localized: "Save a Sample Lesson File…")) { tell(CustomLessons.saveSampleWithPanel()) }
            }
            if !message.isEmpty { Text(message) }
        }
        .alert(String(localized: "Remove \(removing?.lesson.title ?? "")?"),
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(String(localized: "Remove"), role: .destructive) {
                guard let lesson = removing else { return }
                removing = nil
                do {
                    try lessons.remove(lesson)
                    tell(String(localized: "Removed \(lesson.lesson.title)."))
                } catch {
                    tell(String(localized: "Couldn't remove \(lesson.lesson.title)."))
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) { removing = nil }
        } message: {
            Text(String(localized: "The lesson is removed from this Mac. Keep your own copy of the file to import it again."))
        }
    }

    private func tell(_ words: String?) {
        guard let words else { return }
        message = words
        LessonVoice.say(words)
    }
}
