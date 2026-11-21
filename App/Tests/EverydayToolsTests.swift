// EverydayToolsTests.swift — checks timers and reminders, the clipboard history
// and the window switcher's search, without hardware, permissions or VoiceOver.

import XCTest
@testable import VoiceOverAudioSplit

final class ReminderParserTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// Saturday 25 October 2026, 10:00 in the morning.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 10, minute: 0))!
    }

    private func parse(_ text: String) -> Reminder? {
        ReminderParser.parse(text, now: now, calendar: calendar)
    }

    private func at(day: Int = 25, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Noon is in the day. Left open, "at noon" said after noon was set for midnight tonight,
    /// and "tomorrow at 12" for the midnight that starts tomorrow.
    func testNoonIsInTheDay() {
        XCTAssertEqual(parse("remind me at noon to eat")?.due, at(12))
        XCTAssertEqual(parse("remind me tomorrow at noon to eat")?.due, at(day: 26, 12))
        XCTAssertEqual(parse("remind me tomorrow at 12 to eat")?.due, at(day: 26, 12))
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 13))!
        XCTAssertEqual(ReminderParser.parse("remind me at noon to eat", now: afternoon, calendar: calendar)?.due, at(day: 26, 12))
        XCTAssertEqual(ReminderParser.parse("rappelle-moi à midi de manger", now: afternoon, calendar: calendar)?.due, at(day: 26, 12))
        XCTAssertEqual(ReminderParser.parse("set an alarm for noon", now: afternoon, calendar: calendar)?.due, at(day: 26, 12))
        XCTAssertEqual(ReminderParser.parse("remind me at midnight to sleep", now: afternoon, calendar: calendar)?.due, at(day: 26, 0))
    }

    /// Asking about or cancelling what's set must not set another one.
    func testCommandsAboutExistingOnesAreNotNewOnes() {
        for text in ["cancel the 10 minute timer", "stop the timer", "how long is left on my 20 minute timer",
                     "cancel the reminder at 3 pm", "list my reminders", "what timers do I have",
                     "cancela el temporizador de 10 minutos", "annule le minuteur de 10 minutes", "lösche den 10 Minuten Timer"] {
            XCTAssertNil(parse(text), text)
        }
        // The same words inside the reminder itself are part of the message.
        XCTAssertEqual(parse("remind me in 10 minutes to cancel my order")?.message, "cancel my order")
        XCTAssertNotNil(parse("remind me to stop the oven in 20 minutes"))
    }

    /// "1.5 hours" was heard as "1" and "5 hours"; "seventy five" as five.
    func testDecimalsAndLongerNumbers() {
        assertTimer("timer for 1.5 hours", 5400)
        assertTimer("Timer für 1,5 Stunden", 5400)
        assertTimer("set a timer for 2.5 minutes", 150)
        assertTimer("set a timer for seventy five minutes", 4500)
        assertTimer("temporizador de treinta y cinco minutos", 2100)
        assertTimer("set a timer for one hundred twenty minutes", 7200)
        assertTimer("minuteur de soixante-dix minutes", 4200)
        assertTimer("minuteur de quatre-vingt-dix minutes", 5400)
        assertTimer("set a timer for twenty five minutes", 1500)
        assertTimer("set a timer for an hour and a half", 5400)
        XCTAssertEqual(parse("remind me in 1.5 hours to call mom")?.due, now.addingTimeInterval(5400))
        XCTAssertEqual(parse("remind me in 1.5 hours to call mom")?.message, "call mom")
        // The tail of a number that wasn't understood sets nothing, rather than something wrong.
        XCTAssertNil(parse("set a timer for 2 15 minutes"))
        XCTAssertNil(parse("set a timer for one thousand five minutes"))
        // A clock time written with a dot stays a clock time.
        XCTAssertEqual(parse("remind me at 3.30 pm to stretch")?.due, at(15, 30))
    }

    private func assertTimer(_ text: String, _ seconds: TimeInterval, message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let reminder = parse(text) else { return XCTFail("Not understood: \(text)", file: file, line: line) }
        XCTAssertEqual(reminder.duration, seconds, text, file: file, line: line)
        XCTAssertEqual(reminder.due, now.addingTimeInterval(seconds), text, file: file, line: line)
        XCTAssertEqual(reminder.message, message, text, file: file, line: line)
    }

    private func assertReminder(_ text: String, due: Date, message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let reminder = parse(text) else { return XCTFail("Not understood: \(text)", file: file, line: line) }
        XCTAssertNil(reminder.duration, text, file: file, line: line)
        XCTAssertEqual(reminder.due, due, text, file: file, line: line)
        XCTAssertEqual(reminder.message, message, text, file: file, line: line)
    }

    func testEnglishTimers() {
        assertTimer("Set a timer for 10 minutes", 600)
        assertTimer("set a timer for ten minutes.", 600)
        assertTimer("Timer 2 hours", 7200)
        assertTimer("start a 5 minute timer", 300)
        assertTimer("set a timer for 1 hour and 30 minutes", 5400)
        assertTimer("timer for an hour and a half", 5400)
        assertTimer("timer for half an hour", 1800)
        assertTimer("set a timer for twenty five minutes", 1500)
        assertTimer("timer for 45 seconds", 45)
        assertTimer("set a timer for 10min", 600)
        assertTimer("set a timer for 10 minutes for the pasta", 600, message: "the pasta")
        assertTimer("set a 3 minute timer for tea", 180, message: "tea")
    }

    func testOtherLanguageTimers() {
        assertTimer("Pon un temporizador de 10 minutos", 600)
        assertTimer("temporizador de una hora y media", 5400)
        assertTimer("Mets un minuteur de 10 minutes", 600)
        assertTimer("minuteur de deux heures", 7200)
        assertTimer("Stelle einen Timer für 10 Minuten", 600)
        assertTimer("Timer auf eine halbe Stunde", 1800)
    }

    func testEnglishReminders() {
        assertReminder("Remind me at 3 pm to call the doctor", due: at(15), message: "call the doctor")
        assertReminder("remind me to call the doctor at 3 p.m.", due: at(15), message: "call the doctor")
        assertReminder("Remind me in 20 minutes to check the oven", due: now.addingTimeInterval(1200), message: "check the oven")
        assertReminder("remind me to stretch in an hour", due: now.addingTimeInterval(3600), message: "stretch")
        assertReminder("remind me at 3:30 pm to leave", due: at(15, 30), message: "leave")
        assertReminder("Set a reminder for noon to eat lunch", due: at(12), message: "eat lunch")
        assertReminder("remind me tomorrow at 9 am to take my pills", due: at(day: 26, 9), message: "take my pills")
        assertReminder("remind me to water the plants 10 minutes from now", due: now.addingTimeInterval(600),
                       message: "water the plants")
        // Keeps how the message was written.
        assertReminder("Remind me in 5 minutes to call Dr Smith", due: now.addingTimeInterval(300), message: "call Dr Smith")
    }

    func testClockWithoutAmOrPmIsTheNextOne() {
        // At 10 in the morning, "at 3" is 3 this afternoon, and "at 11" is 11 this morning.
        assertReminder("remind me at 3 to call mom", due: at(15), message: "call mom")
        assertReminder("remind me at 11 to call mom", due: at(11), message: "call mom")
        // "At 9 am" has passed today, so it's tomorrow.
        assertReminder("remind me at 9 am to call mom", due: at(day: 26, 9), message: "call mom")
        assertReminder("remind me at 15:45 to call mom", due: at(15, 45), message: "call mom")
    }

    func testOtherLanguageReminders() {
        assertReminder("Recuérdame en 20 minutos que revise el horno", due: now.addingTimeInterval(1200), message: "revise el horno")
        assertReminder("recuérdame a las 3 de la tarde llamar al médico", due: at(15), message: "llamar al médico")
        assertReminder("Rappelle-moi dans 20 minutes de vérifier le four", due: now.addingTimeInterval(1200), message: "vérifier le four")
        assertReminder("rappelle-moi à 15 h d'appeler le médecin", due: at(15), message: "d'appeler le médecin")
        assertReminder("Erinnere mich in 20 Minuten an den Ofen", due: now.addingTimeInterval(1200), message: "den Ofen")
        assertReminder("erinnere mich um 15 Uhr 30 an den Arzt", due: at(15, 30), message: "den Arzt")
    }

    func testNotTimersOrReminders() {
        XCTAssertNil(parse("what time is it"))
        XCTAssertNil(parse("speech left"))
        XCTAssertNil(parse("set a timer"))
        XCTAssertNil(parse("remind me to call the doctor"))
        XCTAssertNil(parse(""))
        // "a" and "for" alone aren't times.
        XCTAssertNil(parse("remind me to buy a 6 pack"))
        XCTAssertNil(parse("remind me to pay for 2 tickets"))
        // Longer than a week.
        XCTAssertNil(parse("set a timer for 900 hours"))
    }
}

final class RemindersModelTests: XCTestCase {
    private let suite = "EverydayToolsTests.reminders"
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var spoken: [String] = []
    private var delivered: [(due: [Reminder], missed: [Reminder])] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        spoken = []
        delivered = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel() -> Reminders {
        Reminders(defaults: defaults, now: { [unowned self] in clock }, calendar: .current,
                  announce: { [unowned self] in spoken.append($0) }, sound: { _ in },
                  deliver: { [unowned self] due, missed in delivered.append((due, missed)) })
    }

    func testSetListAndCancel() {
        let model = makeModel()
        XCTAssertTrue(model.handle("set a timer for 10 minutes"))
        XCTAssertEqual(spoken.last, "Timer set for 10 minutes.")
        clock += 1
        XCTAssertTrue(model.handle("remind me in 1 hour to call the doctor"))
        XCTAssertTrue(spoken.last?.hasSuffix(": call the doctor.") == true, spoken.last ?? "")
        XCTAssertFalse(model.handle("speech left"))
        XCTAssertEqual(model.pending.count, 2)
        XCTAssertTrue(model.spokenList.hasPrefix("2 timers and reminders. Timer for 10 minutes, ends at"), model.spokenList)
        XCTAssertTrue(model.spokenList.contains("call the doctor, at"), model.spokenList)

        model.cancelLast()
        XCTAssertEqual(spoken.last, "Cancelled the reminder: call the doctor.")
        XCTAssertEqual(model.pending.count, 1)
        model.cancelAll()
        XCTAssertEqual(spoken.last, "Cancelled 1 timer or reminder.")
        XCTAssertTrue(model.pending.isEmpty)
        model.cancelLast()
        XCTAssertEqual(spoken.last, "There are no timers or reminders to cancel.")
        XCTAssertEqual(model.spokenList, "No timers or reminders.")
    }

    func testSavedAndRestoredAfterRestart() throws {
        let model = makeModel()
        model.handle("remind me in 20 minutes to check the oven")
        let data = try XCTUnwrap(defaults.data(forKey: Reminders.storageKey))
        let saved = try JSONDecoder().decode([Reminder].self, from: data)
        XCTAssertEqual(saved.map(\.message), ["check the oven"])

        let restarted = makeModel()
        XCTAssertEqual(restarted.pending, model.pending)
    }

    func testDueAndMissed() {
        let model = makeModel()
        model.handle("set a timer for 1 minute")
        model.handle("remind me in 1 hour to call the doctor")
        clock += 61
        model.checkDue()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered[0].due.count, 1)
        XCTAssertTrue(delivered[0].missed.isEmpty)
        XCTAssertEqual(model.pending.count, 1)
        XCTAssertEqual(model.dueText(due: delivered[0].due, missed: []), "Timer done: 1 minute.")

        // The app wasn't running when the reminder came due: said once, as missed.
        clock += 3 * 3600
        let restarted = makeModel()
        restarted.start()
        XCTAssertEqual(delivered.count, 2)
        XCTAssertTrue(delivered[1].due.isEmpty)
        XCTAssertEqual(delivered[1].missed.map(\.message), ["call the doctor"])
        let text = restarted.dueText(due: [], missed: delivered[1].missed)
        XCTAssertTrue(text.hasPrefix("Missed reminder at "), text)
        XCTAssertTrue(text.hasSuffix(": call the doctor."), text)
        XCTAssertTrue(restarted.pending.isEmpty)
        XCTAssertNil(defaults.data(forKey: Reminders.storageKey))

        // Nothing is said twice.
        makeModel().start()
        XCTAssertEqual(delivered.count, 2)
    }

    func testResourceMonitorWords() {
        XCTAssertEqual(ResourceMonitor.Detail.allCases.count, 7)
        XCTAssertEqual(ResourceMonitor.Detail.allCases.map(\.rawValue), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(ResourceMonitor.uptimeWords(5 * 60), "5 minutes")
        XCTAssertEqual(ResourceMonitor.uptimeWords(3 * 3600 + 20 * 60), "3 hours, 20 minutes")
        XCTAssertEqual(ResourceMonitor.uptimeWords(2 * 86400 + 5 * 3600 + 7 * 60), "2 days, 5 hours")
        XCTAssertEqual(ResourceMonitor.percent(0.4249), 42)
        XCTAssertEqual(ResourceMonitor.bytes(16 * 1024 * 1024 * 1024, .memory), "16 gigabytes")
        XCTAssertEqual(ResourceMonitor.bytes(23_890_000_000, .file), "23.9 gigabytes")
        XCTAssertEqual(ResourceMonitor.bytes(946_060_000_000, .file), "946 gigabytes")
        XCTAssertEqual(ResourceMonitor.bytes(2_000_000_000_000, .file), "2 terabytes")
        XCTAssertEqual(ResourceMonitor.bytes(512 * 1024 * 1024, .memory), "512 megabytes")
        XCTAssertTrue(ResourceMonitor.macOSVersion().hasPrefix("macOS "))
        // Reading the Mac itself works in the sandbox: memory, disks and the processor.
        XCTAssertNotNil(ResourceMonitor.memory())
        XCTAssertFalse(ResourceMonitor.volumes().isEmpty)
        XCTAssertTrue(ResourceMonitor.volumes().first?.isStartup ?? false)
    }

    func testSpokenLengths() {
        XCTAssertEqual(Reminders.spoken(600), "10 minutes")
        XCTAssertEqual(Reminders.spoken(5400), "1 hour, 30 minutes")
        XCTAssertEqual(Reminders.spoken(45), "45 seconds")
        // "A minute and a half" is said as it was set, not rounded to two minutes.
        XCTAssertEqual(Reminders.spoken(90), "1 minute, 30 seconds")
    }
}

final class ClipboardHistoryTests: XCTestCase {
    private let suite = "EverydayToolsTests.clipboard"
    private var defaults: UserDefaults!
    private var spoken: [String] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        spoken = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeHistory() -> ClipboardHistory {
        let history = ClipboardHistory(defaults: defaults, announce: { [unowned self] in spoken.append($0) })
        history.isEnabled = true
        return history
    }

    func testHistoryIsOffUntilTurnedOn() {
        let history = ClipboardHistory(defaults: defaults, announce: { _ in })
        XCTAssertFalse(history.isEnabled, "copied text can be private")
        history.record("secret")
        XCTAssertTrue(history.items.isEmpty)
    }

    func testNewestFirstWithoutDuplicates() {
        let history = makeHistory()
        history.record("one")
        history.record("two")
        history.record("  ")
        history.record("one")
        XCTAssertEqual(history.items.map(\.text), ["one", "two"])
    }

    func testKeepsTheLastTwenty() {
        let history = makeHistory()
        for number in 1...25 { history.record("item \(number)") }
        XCTAssertEqual(history.items.count, ClipboardHistory.limit)
        XCTAssertEqual(history.items.first?.text, "item 25")
        XCTAssertEqual(history.items.last?.text, "item 6")
    }

    func testSpeaksTheNthPreviousItem() {
        let history = makeHistory()
        history.speak(1)
        XCTAssertEqual(spoken.last, "The clipboard history is empty.")
        history.record("first")
        history.record("second")
        history.speak(1)
        XCTAssertEqual(spoken.last, "Item 1 of 2: second")
        history.speak(2)
        XCTAssertEqual(spoken.last, "Item 2 of 2: first")
        history.speak(3)
        XCTAssertEqual(spoken.last, "There are only 2 items in the clipboard history.")
    }

    func testOffKeepsNothingAndClearEmpties() {
        let history = makeHistory()
        history.record("kept")
        history.clear()
        XCTAssertTrue(history.items.isEmpty)
        history.record("kept")
        history.isEnabled = false
        XCTAssertTrue(history.items.isEmpty)
        history.record("not kept")
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertEqual(defaults.object(forKey: ClipboardHistory.enabledKey) as? Bool, false)
    }

    func testShortensLongText() {
        XCTAssertEqual(ClipboardHistory.short("line one\nline two"), "line one line two")
        XCTAssertEqual(ClipboardHistory.short(String(repeating: "a", count: 200), limit: 10), "aaaaaaaaaa…")
    }
}

final class WindowSwitcherTests: XCTestCase {
    private func entry(_ app: String, _ title: String, minimized: Bool = false) -> WindowEntry {
        WindowEntry(id: "\(app)-\(title)", pid: 1, appName: app, title: title, minimized: minimized, element: nil)
    }

    func testLabels() {
        XCTAssertEqual(entry("Mail", "Inbox").label, "Mail: Inbox")
        XCTAssertEqual(entry("Notes", "").label, "Notes: Untitled window")
        XCTAssertEqual(entry("Safari", "Apple", minimized: true).label, "Safari: Apple, minimized")
    }

    func testFilterKeepsOrderAndMatchesEveryWord() {
        let entries = [entry("Mail", "Inbox"), entry("Safari", "Mail settings help"), entry("Pages", "Résumé draft")]
        XCTAssertEqual(WindowSwitcher.filter(entries, query: "").count, 3)
        XCTAssertEqual(WindowSwitcher.filter(entries, query: "mail").map(\.appName), ["Mail", "Safari"])
        XCTAssertEqual(WindowSwitcher.filter(entries, query: "mail help").map(\.appName), ["Safari"])
        XCTAssertEqual(WindowSwitcher.filter(entries, query: "RESUME").map(\.appName), ["Pages"])
        XCTAssertTrue(WindowSwitcher.filter(entries, query: "zoom").isEmpty)
    }
}

/// Screen OCR's layout: reading order, words and screen positions, without a screen.
final class ScreenOCRLayoutTests: XCTestCase {
    /// Arrow keys as the keyboard really sends them: with the Fn and keypad flags set.
    /// Treating Fn as a modifier, as the first version did, passed every one of them on.
    func testArrowKeysAreTakenWithTheFlagsTheyReallyCarry() {
        let arrow = CGEventFlags(rawValue: 0xA00100) // keypad + Fn + the "not coalesced" bit
        let homeEnd = CGEventFlags(rawValue: 0x800100)
        func action(_ code: Int64, _ flags: CGEventFlags = [], letter: Character? = nil, caps: Bool = false) -> ScreenOCR.KeyAction {
            ScreenOCR.action(keyCode: code, flags: flags, letter: letter, capsLockHeld: caps)
        }
        XCTAssertEqual(action(125, arrow), .line(1))
        XCTAssertEqual(action(126, arrow), .line(-1))
        XCTAssertEqual(action(123, arrow), .word(-1))
        XCTAssertEqual(action(124, arrow), .word(1))
        XCTAssertEqual(action(115, homeEnd), .first)
        XCTAssertEqual(action(119, homeEnd), .last)
        XCTAssertEqual(action(36), .click(right: false))
        XCTAssertEqual(action(36, .maskShift), .click(right: true))
        XCTAssertEqual(action(53), .leave)
        // VoiceOver's keys and Command shortcuts go through, and the mode stays on.
        XCTAssertEqual(action(124, arrow.union([.maskControl, .maskAlternate])), .pass)
        XCTAssertEqual(action(13, .maskCommand, letter: "w"), .pass)
        XCTAssertEqual(action(124, arrow.union(.maskAlphaShift), caps: true), .pass)
        // Caps Lock switched on for capitals, not held, is not VoiceOver's key.
        XCTAssertEqual(action(125, arrow.union(.maskAlphaShift)), .line(1))
        // C is the letter typed, wherever it sits: on Dvorak the C position types J.
        XCTAssertEqual(action(8, letter: "c"), .copy)
        XCTAssertEqual(action(34, letter: "c"), .copy)
        XCTAssertEqual(action(8, letter: "j"), .leaveAndPass)
        XCTAssertEqual(action(0, letter: "a"), .leaveAndPass)
    }

    /// A click is checked against the screen as it is now, not as it was pictured.
    func testClickIsCheckedAgainstTheScreenNow() {
        typealias Window = ScreenOCRLayout.OnScreenWindow
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let point = CGPoint(x: 300, y: 250)
        func check(_ windows: [Window], id: CGWindowID? = 7) -> ScreenOCRLayout.ClickCheck {
            ScreenOCRLayout.check(click: point, picturedFrame: frame, windowID: id, windows: windows, me: 1)
        }
        let pictured = Window(id: 7, frame: frame, layer: 0, processID: 50)
        let everywhere = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        XCTAssertEqual(check([pictured]), .click(point))
        XCTAssertEqual(check([]), .gone)
        XCTAssertEqual(check([Window(id: 7, frame: frame.insetBy(dx: 40, dy: 0), layer: 0, processID: 50)]), .resized)
        // Moved but the same size: the click moves with it.
        XCTAssertEqual(check([Window(id: 7, frame: frame.offsetBy(dx: 50, dy: -20), layer: 0, processID: 50)]), .click(CGPoint(x: 350, y: 230)))
        // A dialog in front of the text would take the click; one elsewhere wouldn't.
        let dialog = Window(id: 9, frame: CGRect(x: 250, y: 200, width: 300, height: 200), layer: 0, processID: 50)
        XCTAssertEqual(check([dialog, pictured]), .covered)
        XCTAssertEqual(check([Window(id: 9, frame: CGRect(x: 700, y: 500, width: 100, height: 100), layer: 8, processID: 50), pictured]), .click(point))
        // Windows behind it, the menu bar, and this app's own see-through overlays don't count.
        XCTAssertEqual(check([pictured, dialog]), .click(point))
        XCTAssertEqual(check([Window(id: 2, frame: everywhere, layer: 25, processID: 60), pictured]), .click(point))
        XCTAssertEqual(check([Window(id: 3, frame: everywhere, layer: 3, processID: 1), pictured]), .click(point))
        // This app's own ordinary window in front (the Screen OCR window itself) does.
        XCTAssertEqual(check([Window(id: 4, frame: everywhere, layer: 0, processID: 1), pictured]), .covered)
        // A whole-screen picture has no window to compare.
        XCTAssertEqual(check([], id: nil), .click(point))
    }

    private func line(_ id: Int, _ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.05) -> ScreenOCRLayout.Line {
        ScreenOCRLayout.Line(id: id, text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    func testReadingOrderIsRowsTopToBottomThenLeftToRight() {
        // Two columns on the same row, then a line below, given out of order.
        let lines = [
            line(0, "bottom", x: 0.1, y: 0.1),
            line(1, "right column", x: 0.6, y: 0.8),
            line(2, "left column", x: 0.1, y: 0.81),
        ]
        let ordered = ScreenOCRLayout.ordered(lines)
        XCTAssertEqual(ordered.map(\.text), ["left column", "right column", "bottom"])
        XCTAssertEqual(ordered.map(\.id), [0, 1, 2])
    }

    func testLinesThatBarelyTouchAreSeparateRows() {
        let lines = [line(0, "lower", x: 0.1, y: 0.50), line(1, "upper", x: 0.5, y: 0.54)]
        XCTAssertEqual(ScreenOCRLayout.ordered(lines).map(\.text), ["upper", "lower"])
    }

    func testWordsShareTheLineByLength() {
        let words = ScreenOCRLayout.words(of: "Save  the file", in: CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.1))
        XCTAssertEqual(words.map(\.text), ["Save", "the", "file"])
        XCTAssertEqual(words.first!.box.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(words.last!.box.maxX, 0.8, accuracy: 0.0001)
        XCTAssertLessThan(words[0].box.maxX, words[1].box.minX)
        XCTAssertEqual(words[0].box.width, words[2].box.width, accuracy: 0.0001)
        XCTAssertTrue(ScreenOCRLayout.words(of: "   ", in: .zero).isEmpty)
    }

    func testScreenRectFlipsVisionCoordinates() {
        // A window at (100, 50) on a 1000 by 800 screen, 400 by 300 points. A box at the top
        // left of the picture in Vision's bottom-left space is at the top left on screen.
        let frame = CGRect(x: 100, y: 50, width: 400, height: 300)
        let rect = ScreenOCRLayout.screenRect(CGRect(x: 0, y: 0.9, width: 0.5, height: 0.1), in: frame)
        XCTAssertEqual(rect.minX, 100, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 50, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 200, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 30, accuracy: 0.0001)
        let center = ScreenOCRLayout.screenCenter(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.2), in: frame)
        XCTAssertEqual(center.x, 400, accuracy: 0.0001)
        XCTAssertEqual(center.y, 320, accuracy: 0.0001)
    }

    func testScreenOCRCommandHasNoKeyByDefault() {
        XCTAssertNil(Command.screenOCR.defaultKey)
        XCTAssertFalse(Command.screenOCR.title.isEmpty)
    }
}
