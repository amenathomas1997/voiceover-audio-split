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
