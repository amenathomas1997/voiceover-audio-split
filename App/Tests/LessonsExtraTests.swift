// LessonsExtraTests.swift — the second Everyday apps level, lesson files from trainers,
// key names in words, and students sharing one Mac.

import XCTest
@testable import VoiceOverAudioSplit

final class EverydayApps2Tests: XCTestCase {
    let newIDs = ["messages", "calendar", "files", "meetings", "braille", "utility"]

    func testNewLevelComesBeforeTheReview() {
        XCTAssertEqual(Lesson.course.count, 30)
        let titles = Lesson.levels.map(\.title)
        XCTAssertEqual(titles, ["Basics", "Everyday apps", "Going further", "Everyday apps 2", "Review"])
        XCTAssertEqual(Lesson.levels[3].lessons.map(\.id), newIDs)
        XCTAssertEqual(Lesson.levels[2].lessons.count, 8)
        XCTAssertEqual(Lesson.course.last?.id, "review")
        XCTAssertTrue(Lesson.review.title.hasPrefix("30. "))
    }

    func testNewLessonsAreComplete() {
        for id in newIDs {
            let lesson = try! XCTUnwrap(Lesson.all.first { $0.id == id }, id)
            guard case .explain = lesson.steps.first?.kind else { return XCTFail("\(id) starts with an explanation") }
            XCTAssertFalse(LessonGuide.goals(id).isEmpty, id)
            XCTAssertFalse(LessonGuide.recap(id).isEmpty, id)
            XCTAssertFalse(LessonGuide.trainer(id).isEmpty, id)
            XCTAssertFalse(lesson.summary.isEmpty, id)
            var combos: [KeyCombo] = []
            var hasMission = false
            for step in lesson.steps {
                switch step.kind {
                case .explain(let text):
                    XCTAssertFalse(text.isEmpty, id)
                case .practice(let task, let keys, let combo, _, _):
                    // The keys said are the keys checked.
                    XCTAssertEqual(KeyCombo.parse(keys), combo, "\(id): \(task), \(keys)")
                    XCTAssertFalse(combo.steersLessons, "\(id): \(keys)")
                    combos.append(combo)
                case .question(let prompt, let options, let answer, let why):
                    XCTAssertTrue((2...4).contains(options.count), prompt)
                    XCTAssertTrue(options.indices.contains(answer), prompt)
                    XCTAssertFalse(why.isEmpty, prompt)
                case .mission(let task, let check, _):
                    hasMission = true
                    XCTAssertFalse(task.isEmpty, id)
                    switch check {
                    case .frontApp, .frontAppAny, .finderWindowTitled, .yourWord: break
                    default: XCTFail("\(id): \(task) isn't checked by app, window title or your word")
                    }
                }
            }
            XCTAssertEqual(Set(combos).count, combos.count, "\(id): a quick check can't have two tasks with the same keys")
            XCTAssertFalse(combos.isEmpty && !hasMission, id)
        }
    }

    func testNewMissions() {
        let runner = LessonRunner()
        XCTAssertFalse(Mission.frontAppAny(["com.example.not-running"]).isDone(runner))
        XCTAssertTrue(Mission.finderWindowTitled("x").needsAccessibility)
        XCTAssertFalse(Mission.frontAppAny(["x.y"]).needsAccessibility)
    }
}

final class KeyNameTests: XCTestCase {
    func testParsesKeysInWords() {
        XCTAssertEqual(KeyCombo.parse("VO Shift Down Arrow"), KeyCombo(code: 125, shift: true))
        XCTAssertEqual(KeyCombo.parse("VO Command H"), KeyCombo(code: 4, command: true))
        XCTAssertEqual(KeyCombo.parse("vo command shift h"), KeyCombo(code: 4, shift: true, command: true))
        XCTAssertEqual(KeyCombo.parse("Control Option A"), KeyCombo(code: 0), "Control Option is VO")
        XCTAssertEqual(KeyCombo.parse("Option Command V"), KeyCombo(code: 9, vo: false, command: true, option: true))
        XCTAssertEqual(KeyCombo.parse("Control Tab"), KeyCombo(code: 48, vo: false, control: true))
        XCTAssertEqual(KeyCombo.parse("Cmd+Shift+A"), KeyCombo(code: 0, vo: false, shift: true, command: true))
        XCTAssertEqual(KeyCombo.parse("Command Left Bracket"), KeyCombo(code: 33, vo: false, command: true))
        XCTAssertEqual(KeyCombo.parse("VO F8"), KeyCombo(code: 100))
        XCTAssertEqual(KeyCombo.parse("VO F12"), KeyCombo(code: 111))
        XCTAssertEqual(KeyCombo.parse("Command 1"), KeyCombo(code: 18, vo: false, command: true))
        XCTAssertEqual(KeyCombo.parse("Tab"), KeyCombo(code: 48, vo: false))
        XCTAssertEqual(KeyCombo.parse("Command Delete"), KeyCombo(code: 51, vo: false, command: true))
        XCTAssertEqual(KeyCombo.parse("  VO   Space "), KeyCombo(code: 49))
        XCTAssertEqual(KeyCombo.parse("Command Grave Accent"), KeyCombo(code: 50, vo: false, command: true))
        XCTAssertEqual(KeyCombo.parse("VO Down"), KeyCombo(code: 125), "Arrow can be left out")
    }

    func testRejectsWhatIsntKeys() {
        for bad in ["", "VO", "Command Shift", "VO Comand H", "H Command", "VO Command HH", "VO Fn Left Arrow", "Command F13", "Super H"] {
            XCTAssertNil(KeyCombo.parse(bad), bad)
        }
    }

    func testLessonKeysCantBePracticed() {
        for keys in ["Return", "Escape", "R", "B", "H", "S"] {
            XCTAssertTrue(try XCTUnwrap(KeyCombo.parse(keys)).steersLessons, keys)
        }
        for keys in ["VO H", "Shift Tab", "Tab", "Command R", "A"] {
            XCTAssertFalse(try XCTUnwrap(KeyCombo.parse(keys)).steersLessons, keys)
        }
    }
}

final class LessonFileTests: XCTestCase {
    /// A lesson file with these steps.
    private func file(_ steps: String, extra: String = "") -> Data {
        Data("{ \"title\": \"Test\", \(extra) \"steps\": [\(steps)] }".utf8)
    }

    private func problem(_ data: Data) -> String {
        do {
            _ = try LessonFile.parse(data, id: "custom.test")
            return "no problem"
        } catch {
            return (error as? LessonFile.Problem)?.message ?? "\(error)"
        }
    }

    func testSampleIsAValidLesson() throws {
        let custom = try LessonFile.parse(Data(LessonFile.sample.utf8), id: "custom.sample")
        XCTAssertEqual(custom.lesson.id, "custom.sample")
        XCTAssertEqual(custom.lesson.title, "Our library's website")
        XCTAssertFalse(custom.goals.isEmpty)
        XCTAssertFalse(custom.recap.isEmpty)
        XCTAssertFalse(custom.trainer.isEmpty)
        XCTAssertEqual(custom.lesson.steps.count, 7)
        XCTAssertEqual(custom.lesson.practice.count, 3)
        XCTAssertEqual(custom.lesson.steps[1].kind, .mission(task: "Open Safari, for real.", check: .frontApp("com.apple.Safari"),
                                                              tip: "Come back to the lessons with Command Tab when you hear Done."))
        XCTAssertEqual(custom.lesson.steps[3].kind, .practice(task: "Go to the next heading", keys: "VO Command H", combo: KeyCombo(code: 4, command: true),
                                                              tip: "Headings are like the titles of a newspaper's articles.", realKeys: false))
        guard case .question(_, let options, let answer, _) = custom.lesson.steps[5].kind else { return XCTFail("a question") }
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(answer, 0, "answers count from 1 in the file")
        XCTAssertEqual(custom.lesson.steps[6].kind, .mission(task: "Now for real: find the library's opening hours, and press Return here when you've heard them.",
                                                              check: .yourWord, tip: ""))
    }

    func testSmallestLesson() throws {
        let custom = try LessonFile.parse(file(#"{ "kind": "explain", "text": "Hello." }"#), id: "custom.x")
        XCTAssertEqual(custom.lesson.steps, [.say("Hello.")])
        XCTAssertEqual(custom.lesson.summary, "A lesson from your trainer.")
        XCTAssertTrue(custom.goals.isEmpty)
    }

    func testProblemsSayWhereAndWhat() {
        let explain = #"{ "kind": "explain", "text": "Hi." }"#
        XCTAssertEqual(problem(file(explain + "," + explain + #", { "kind": "practice", "task": "Next heading", "keys": "VO Comand H" }"#)),
                       "Step 3: unknown key name 'VO Comand H'. Write any held keys first (VO, Command, Shift, Option, Control), then one key, such as H, Down Arrow or F8.")
        XCTAssertEqual(problem(file(#"{ "kind": "quiz", "text": "Hi." }"#)),
                       "Step 1: unknown kind 'quiz'. Use explain, practice, question or mission.")
        XCTAssertEqual(problem(file(#"{ "text": "Hi." }"#)), "Step 1: 'kind' is missing. Use explain, practice, question or mission.")
        XCTAssertEqual(problem(file(#"{ "kind": "practice", "tsk": "Next", "keys": "VO H" }"#)),
                       "Step 1: unknown field 'tsk'. A practice step can have: keys, task, tip.")
        XCTAssertEqual(problem(file(#"{ "kind": "practice", "keys": "VO H" }"#)), "Step 1: 'task' is missing.")
        XCTAssertEqual(problem(file(#"{ "kind": "explain", "text": "  " }"#)), "Step 1: 'text' is empty.")
        XCTAssertEqual(problem(file(#"{ "kind": "explain", "text": 3 }"#)), "Step 1: 'text' must be text, in quotes.")
        XCTAssertEqual(problem(file(#"{ "kind": "practice", "task": "Repeat", "keys": "R" }"#)),
                       "Step 1: 'R' on its own steers the lesson (Return goes on, R repeats, B goes back, H gives a hint, S skips, Escape stops), so it can't be practiced. Add a key held with it, such as VO or Command.")
        XCTAssertEqual(problem(file(#"{ "kind": "practice", "task": "A", "keys": "VO H" }, { "kind": "practice", "task": "B", "keys": "Control Option H" }"#)),
                       "Step 2: the keys 'Control Option H' are already practiced in step 1. Each practice step in a lesson needs different keys, so the quick check can tell them apart.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A", "B"], "answer": 3, "why": "W" }"#)),
                       "Step 1: 'answer' must be the number of the right option, from 1 to 2.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A", "B"], "answer": true, "why": "W" }"#)),
                       "Step 1: 'answer' must be the number of the right option, from 1 to 2.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A", "B"], "answer": 0, "why": "W" }"#)),
                       "Step 1: 'answer' must be the number of the right option, from 1 to 2.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A"], "answer": 1, "why": "W" }"#)),
                       "Step 1: a question needs 2, 3 or 4 options, answered with the number keys; this one has 1.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A", ""], "answer": 1, "why": "W" }"#)),
                       "Step 1: option 2 must be some text, in quotes.")
        XCTAssertEqual(problem(file(#"{ "kind": "question", "prompt": "Q?", "options": ["A", "B"], "answer": 1 }"#)), "Step 1: 'why' is missing.")
        XCTAssertEqual(problem(file(#"{ "kind": "mission", "task": "Open it", "check": "Safari" }"#)),
                       "Step 1: 'check' must be yourWord, or the bundle ID of the app that should be in front, such as com.apple.Safari.")
        XCTAssertEqual(problem(file(#""hello""#)), "Step 1: each step must be between curly braces, with a kind.")
    }

    func testWholeFileProblems() {
        XCTAssertTrue(problem(Data("{ \"title\": ".utf8)).hasPrefix("This file isn't a lesson file: its text isn't valid JSON."))
        XCTAssertEqual(problem(Data("[]".utf8)), "This file isn't a lesson file: it must hold one lesson, between curly braces.")
        XCTAssertEqual(problem(Data(#"{ "steps": [] }"#.utf8)), "'title' is missing.")
        XCTAssertEqual(problem(Data(#"{ "title": "T" }"#.utf8)), "The lesson has no steps: add a 'steps' list.")
        XCTAssertEqual(problem(Data(#"{ "title": "T", "steps": [] }"#.utf8)),
                       "'steps' must be a list of steps, between square brackets, with at least one step.")
        XCTAssertEqual(problem(file(#"{ "kind": "explain", "text": "Hi." }"#, extra: #""author": "Sam","#)),
                       "Unknown field 'author'. A lesson can have: format, title, summary, goals, recap, trainerNotes and steps.")
        XCTAssertEqual(problem(file(#"{ "kind": "explain", "text": "Hi." }"#, extra: #""format": 2,"#)),
                       "This lesson is format 2; this version of the app reads format 1.")
        XCTAssertEqual(problem(file(#"{ "kind": "explain", "text": "Hi." }"#, extra: #""goals": 5,"#)), "'goals' must be text, in quotes.")
    }

    func testMissionChecks() {
        XCTAssertEqual(LessonFile.mission("yourWord"), .yourWord)
        XCTAssertEqual(LessonFile.mission("com.apple.Safari"), .frontApp("com.apple.Safari"))
        XCTAssertEqual(LessonFile.mission("us.zoom.xos"), .frontApp("us.zoom.xos"))
        XCTAssertNil(LessonFile.mission("Safari"))
        XCTAssertNil(LessonFile.mission("com..apple"))
        XCTAssertNil(LessonFile.mission("com.apple Safari"))
    }

    func testImportKeepsReplacesAndRemovesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CustomLessons(directory: folder)
        XCTAssertTrue(store.lessons.isEmpty)
        let first = try store.importData(Data(LessonFile.sample.utf8))
        XCTAssertFalse(first.replaced)
        XCTAssertEqual(first.lesson.id, "custom.our-library-s-website")
        XCTAssertEqual(first.lesson.file?.lastPathComponent, "our-library-s-website.voalesson")
        XCTAssertEqual(store.guide(for: first.lesson.id)?.recap, first.lesson.recap)
        XCTAssertEqual(try store.importData(Data(LessonFile.sample.utf8)).replaced, true, "the same title replaces the lesson")
        XCTAssertEqual(store.lessons.count, 1)
        // A bad file is refused and nothing is kept.
        XCTAssertThrowsError(try store.importData(Data(#"{ "title": "Bad", "steps": [{ "kind": "nope" }] }"#.utf8)))
        XCTAssertEqual(store.lessons.count, 1)
        // A file that's become unreadable is listed with why.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("broken.voalesson"))
        store.reload()
        XCTAssertEqual(store.unreadable, ["broken.voalesson: 'title' is missing."])
        // Another instance (the next launch) finds the lesson again.
        XCTAssertEqual(CustomLessons(directory: folder).lessons.map(\.id), [first.lesson.id])
        try store.remove(try XCTUnwrap(store.lessons.first))
        XCTAssertTrue(store.lessons.isEmpty)
    }

    func testFileNames() {
        XCTAssertEqual(CustomLessons.fileName(for: "Our library's website"), "our-library-s-website")
        XCTAssertEqual(CustomLessons.fileName(for: "  Zoom: joining!  "), "zoom-joining")
        XCTAssertEqual(CustomLessons.fileName(for: "!!!"), "lesson")
        XCTAssertEqual(CustomLessons.id(for: URL(fileURLWithPath: "/x/zoom-joining.voalesson")), "custom.zoom-joining")
    }
}

/// Preferences' lesson progress, without touching the real Preferences.
private final class TestMirror: LessonProgressMirror {
    var lessonsDone: [String] = []
    var lessonsMissed: [String] = []
    var lessonSchedule: [String: [Double]] = [:]
    var lessonChallengeBest = 0
}

final class StudentTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "LessonsExtraTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Progress from before students existed, as Preferences saved it.
    private func savedProgress() -> TestMirror {
        defaults.set(["start", "moving"], forKey: "lessonsDone")
        defaults.set(["web.2"], forKey: "lessonsMissed")
        defaults.set(["web.2": [1.0, 1000.0]], forKey: "lessonSchedule")
        defaults.set(7, forKey: "lessonChallengeBest")
        let mirror = TestMirror()
        mirror.lessonsDone = ["start", "moving"]
        mirror.lessonsMissed = ["web.2"]
        mirror.lessonSchedule = ["web.2": [1.0, 1000.0]]
        mirror.lessonChallengeBest = 7
        return mirror
    }

    func testExistingProgressBecomesMe() {
        _ = savedProgress()
        let mirror = TestMirror() // Even if Preferences hadn't loaded it, the saved values are used.
        let progress = LessonProgress(defaults: defaults, mirror: mirror)
        XCTAssertEqual(progress.students.map(\.id), [LessonProgress.meID])
        XCTAssertEqual(progress.current.name, "Me")
        XCTAssertEqual(progress.done, ["start", "moving"])
        XCTAssertEqual(progress.missed, ["web.2"])
        XCTAssertEqual(progress.schedule, ["web.2": [1.0, 1000.0]])
        XCTAssertEqual(progress.challengeBest, 7)
        XCTAssertEqual(mirror.lessonsDone, ["start", "moving"], "and Preferences has it")
        XCTAssertNotNil(defaults.data(forKey: LessonProgress.storeKey))
    }

    func testFreshMacStartsWithMeAndNothingDone() {
        let progress = LessonProgress(defaults: defaults, mirror: TestMirror())
        XCTAssertEqual(progress.students.count, 1)
        XCTAssertTrue(progress.done.isEmpty)
        XCTAssertEqual(progress.challengeBest, 0)
    }

    func testSwitchingStudentsSwitchesProgress() throws {
        let mirror = savedProgress()
        let progress = LessonProgress(defaults: defaults, mirror: mirror)
        let sam = try XCTUnwrap(progress.add(name: "Sam"))
        XCTAssertEqual(progress.currentID, LessonProgress.meID, "adding doesn't switch")
        progress.switchTo(sam.id)
        XCTAssertEqual(progress.current.name, "Sam")
        XCTAssertTrue(progress.done.isEmpty)
        XCTAssertTrue(mirror.lessonsDone.isEmpty, "Preferences has Sam's progress now")
        XCTAssertEqual(progress.challengeBest, 0)
        progress.done = ["start"]
        progress.challengeBest = 3
        progress.schedule = LessonSchedule.update(progress.schedule, id: "start.3", right: true, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(mirror.lessonsDone, ["start"])
        XCTAssertEqual(mirror.lessonChallengeBest, 3)

        XCTAssertTrue(progress.switchTo(named: "me"))
        XCTAssertEqual(progress.done, ["start", "moving"])
        XCTAssertEqual(progress.challengeBest, 7)
        XCTAssertEqual(mirror.lessonsMissed, ["web.2"])

        // Next launch: the current student and everyone's progress are still there.
        progress.switchTo(sam.id)
        let again = LessonProgress(defaults: defaults, mirror: mirror)
        XCTAssertEqual(again.current.name, "Sam")
        XCTAssertEqual(again.done, ["start"])
        XCTAssertEqual(again.schedule["start.3"]?.first, 1)
        again.switchTo(LessonProgress.meID)
        XCTAssertEqual(again.done, ["start", "moving"])
        XCTAssertFalse(again.switchTo(named: "Nobody"))
    }

    func testPreferencesChangedElsewhereWin() {
        let mirror = savedProgress()
        _ = LessonProgress(defaults: defaults, mirror: mirror)
        // For example a settings import, while Me is current.
        mirror.lessonsDone = ["start", "moving", "reading"]
        let progress = LessonProgress(defaults: defaults, mirror: mirror)
        XCTAssertEqual(progress.done, ["start", "moving", "reading"])
        let sam = progress.add(name: "Sam")!
        progress.switchTo(sam.id)
        progress.switchTo(LessonProgress.meID)
        XCTAssertEqual(progress.done, ["start", "moving", "reading"])
    }

    func testNamesRenamingAndRemoving() throws {
        let mirror = savedProgress()
        let progress = LessonProgress(defaults: defaults, mirror: mirror)
        XCTAssertNil(progress.add(name: "  "))
        let sam = try XCTUnwrap(progress.add(name: " Sam "))
        XCTAssertEqual(sam.name, "Sam")
        XCTAssertNil(progress.add(name: "sam"), "names are unique")
        let alex = try XCTUnwrap(progress.add(name: "Alex"))
        XCTAssertFalse(progress.rename(alex.id, to: "SAM"))
        XCTAssertTrue(progress.rename(alex.id, to: "Alexandra"))
        XCTAssertEqual(progress.students.map(\.name), ["Me", "Sam", "Alexandra"])
        XCTAssertFalse(progress.remove(LessonProgress.meID), "Me stays")
        progress.switchTo(sam.id)
        progress.done = ["start"]
        progress.record(lessonID: "start", lesson: "1. Getting started", score: "2 of 2 right first time", mode: "onYourOwn", lines: [])
        XCTAssertTrue(progress.remove(sam.id))
        XCTAssertEqual(progress.currentID, LessonProgress.meID, "removing the current student goes back to Me")
        XCTAssertEqual(mirror.lessonsDone, ["start", "moving"])
        XCTAssertTrue(progress.sessions(for: sam.id).isEmpty)
        XCTAssertEqual(progress.students.map(\.name), ["Me", "Alexandra"])
    }

    func testReportsArePerStudent() throws {
        let progress = LessonProgress(defaults: defaults, mirror: TestMirror())
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        progress.record(lessonID: "start", lesson: "1. Getting started", score: "2 of 2 right first time", mode: "withTrainer",
                        lines: ["Open the help menu (VO H): right first time"], date: date)
        let sam = try XCTUnwrap(progress.add(name: "Sam, Jr."))
        progress.switchTo(sam.id)
        XCTAssertTrue(progress.sessions.isEmpty)
        progress.record(lessonID: "web", lesson: "6. Web pages", score: "4 of 5 right first time", mode: "onYourOwn",
                        lines: ["Go to the next heading (VO Command H): right after 2 tries", "Say \"hi\""], date: date)
        XCTAssertEqual(progress.sessions.count, 1)
        XCTAssertEqual(progress.sessions(for: LessonProgress.meID).map(\.lessonID), ["start"])

        let text = progress.reportText(for: sam.id)
        XCTAssertTrue(text.hasPrefix("VoiceOver Lessons report: Sam, Jr.\n"), text)
        XCTAssertTrue(text.contains("Lessons done: 0 of 30"), text)
        XCTAssertTrue(text.contains("6. Web pages\n4 of 5 right first time, on your own\n  Go to the next heading (VO Command H): right after 2 tries"), text)
        XCTAssertFalse(text.contains("Getting started"), "only this student's sessions")

        let csv = LessonProgress.reportCSV(student: "Sam, Jr.", sessions: progress.sessions)
        let rows = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(rows[0], "Student,Date,Lesson,Score,Mode,Details")
        XCTAssertTrue(rows[1].hasPrefix("\"Sam, Jr.\","), rows[1])
        XCTAssertTrue(rows[1].hasSuffix(",6. Web pages,4 of 5 right first time,on your own,\"Go to the next heading (VO Command H): right after 2 tries | Say \"\"hi\"\"\""), rows[1])
        XCTAssertEqual(rows.count, 3, "header, one row, and a final line break")
        XCTAssertEqual(LessonProgress.csvField("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(LessonProgress.csvField("plain"), "plain")
    }

    func testOldReportsArePruned() {
        let progress = LessonProgress(defaults: defaults, mirror: TestMirror())
        for index in 0..<(LessonProgress.maxSessions + 5) {
            progress.record(lessonID: "x", lesson: "\(index)", score: "", mode: "", lines: [])
        }
        XCTAssertEqual(progress.sessions.count, LessonProgress.maxSessions)
        XCTAssertEqual(progress.sessions.first?.lesson, "5")
    }

    func testTheAppsProgressGoesThroughTheStore() {
        // The shared store reads the current student's progress from Preferences.
        let saved = Preferences.shared.lessonsDone
        defer { Preferences.shared.lessonsDone = saved }
        Preferences.shared.lessonsDone = ["start"]
        XCTAssertEqual(LessonProgress.shared.done, ["start"])
        XCTAssertEqual(LessonRunner.shared.nextLesson.id, "moving")
    }
}
