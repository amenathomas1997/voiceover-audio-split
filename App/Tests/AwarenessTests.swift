// Tests for progress bar tones, indentation tones, watching a window, What's Next and the
// actions for Siri and Shortcuts: the parts that need no screen, calendar or sound.

import XCTest
@testable import VoiceOverAudioSplit

final class ProgressToneTests: XCTestCase {
    func testHowFullABarIs() {
        XCTAssertEqual(ProgressTones.fraction(value: 50, min: 0, max: 100), 0.5)
        XCTAssertEqual(ProgressTones.fraction(value: 0.25, min: 0, max: 1), 0.25)
        XCTAssertEqual(ProgressTones.fraction(value: 30, min: 20, max: 40), 0.5)
        XCTAssertEqual(ProgressTones.fraction(value: 150, min: 0, max: 100), 1, "never more than full")
        XCTAssertEqual(ProgressTones.fraction(value: -5, min: 0, max: 100), 0)
        // A bar with no range (a spinner) says nothing.
        XCTAssertNil(ProgressTones.fraction(value: 0, min: 0, max: 0))
        XCTAssertNil(ProgressTones.fraction(value: .nan, min: 0, max: 1))
    }

    func testPitchRisesAsItFills() {
        XCTAssertEqual(ProgressTones.frequency(for: 0), 220, accuracy: 0.01)
        XCTAssertEqual(ProgressTones.frequency(for: 1), 1760, accuracy: 0.01)
        XCTAssertGreaterThan(ProgressTones.frequency(for: 0.6), ProgressTones.frequency(for: 0.5))
        XCTAssertEqual(ProgressTones.frequency(for: 2), 1760, accuracy: 0.01, "stays in range")
    }

    func testWhenATonePlays() {
        XCTAssertTrue(ProgressTones.shouldSound(0.1, last: nil, secondsSinceLast: 0), "the first reading")
        XCTAssertFalse(ProgressTones.shouldSound(0.505, last: 0.5, secondsSinceLast: 5), "hardly moved")
        XCTAssertTrue(ProgressTones.shouldSound(0.53, last: 0.5, secondsSinceLast: 1))
        XCTAssertFalse(ProgressTones.shouldSound(0.53, last: 0.5, secondsSinceLast: 0.1), "not a stream of beeps")
        XCTAssertTrue(ProgressTones.shouldSound(0.7, last: 0.5, secondsSinceLast: 0.1), "a jump is always heard")
        XCTAssertTrue(ProgressTones.shouldSound(1, last: 0.995, secondsSinceLast: 0.1), "finishing is always heard")
        XCTAssertFalse(ProgressTones.shouldSound(1, last: 1, secondsSinceLast: 10), "but only once")
    }
}

final class IndentationTests: XCTestCase {
    func testMeasuringALine() {
        XCTAssertEqual(Indentation.measure("let x = 1"), Indentation.Measure(width: 0, tabs: 0, spaces: 0))
        XCTAssertEqual(Indentation.measure("    return x"), Indentation.Measure(width: 4, tabs: 0, spaces: 4))
        XCTAssertEqual(Indentation.measure("\t\tfoo()"), Indentation.Measure(width: 8, tabs: 2, spaces: 0))
        XCTAssertEqual(Indentation.measure("\t  bar"), Indentation.Measure(width: 6, tabs: 1, spaces: 2))
        XCTAssertEqual(Indentation.measure("\tx", tabWidth: 2)?.width, 2)
        // A blank line says nothing about the indentation around it.
        XCTAssertNil(Indentation.measure(""))
        XCTAssertNil(Indentation.measure("      "))
        XCTAssertNil(Indentation.measure("    \n"))
    }

    func testPitchRisesWithIndentation() {
        XCTAssertEqual(Indentation.frequency(forWidth: 0), 220, accuracy: 0.01)
        XCTAssertEqual(Indentation.frequency(forWidth: 24), 440, accuracy: 0.01, "24 columns is an octave")
        XCTAssertGreaterThan(Indentation.frequency(forWidth: 8), Indentation.frequency(forWidth: 4))
        XCTAssertEqual(Indentation.frequency(forWidth: 500), Indentation.frequency(forWidth: 72), "stops rising")
    }

    func testSaidInWords() {
        XCTAssertEqual(Indentation.spoken(nil), "This line is blank.")
        XCTAssertEqual(Indentation.spoken(Indentation.measure("x")), "Not indented.")
        XCTAssertEqual(Indentation.spoken(Indentation.measure("    x")), "Indented 4 spaces.")
        XCTAssertEqual(Indentation.spoken(Indentation.measure(" x")), "Indented 1 space.")
        XCTAssertEqual(Indentation.spoken(Indentation.measure("\tx")), "Indented 1 tab.")
        XCTAssertEqual(Indentation.spoken(Indentation.measure("\t\t x")), "Indented 2 tabs and 1 space.")
    }
}

final class ScreenWatchTests: XCTestCase {
    func testOnlyNewLinesAreSaid() {
        let before = ["Installing", "Step 1 of 3", "Please wait"]
        XCTAssertEqual(ScreenWatchLogic.newLines(before: before, now: before), [])
        XCTAssertEqual(ScreenWatchLogic.newLines(before: before, now: ["Installing", "Step 2 of 3", "Please wait"]), ["Step 2 of 3"])
        // Text that only scrolled, or changed its spacing or case, isn't new.
        XCTAssertEqual(ScreenWatchLogic.newLines(before: before, now: ["Please  wait", "INSTALLING", "Step 1 of 3"]), [])
        // The same words appearing a second time are new.
        XCTAssertEqual(ScreenWatchLogic.newLines(before: ["ok"], now: ["ok", "ok"]), ["ok"])
        XCTAssertEqual(ScreenWatchLogic.newLines(before: [], now: ["Done", "   "]), ["Done"])
    }

    func testLongChangesAreShortened() {
        XCTAssertEqual(ScreenWatchLogic.announcement(["One", "Two"]), "One. Two")
        XCTAssertEqual(ScreenWatchLogic.announcement(["One", "Two", "Three", "Four", "Five"]), "One. Two. Three. And 2 more lines.")
        XCTAssertEqual(ScreenWatchLogic.announcement(["One", "Two", "Three", "Four"]), "One. Two. Three. And 1 more line.")
        XCTAssertLessThanOrEqual(ScreenWatchLogic.announcement([String(repeating: "x", count: 900)]).count, 200)
    }
}

final class AgendaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ title: String, from start: TimeInterval, to end: TimeInterval, allDay: Bool = false, texts: [String] = []) -> AgendaEvent {
        AgendaEvent(title: title, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), allDay: allDay, texts: texts)
    }

    func testNowAndNext() {
        let events = [
            event("Holiday", from: -3600 * 5, to: 3600 * 19, allDay: true),
            event("Over", from: -7200, to: -3600),
            event("Standup", from: -600, to: 1200),
            event("Review", from: 1800, to: 5400),
            event("Later", from: 9000, to: 12600),
        ]
        let picked = AgendaLogic.pick(events, now: now)
        XCTAssertEqual(picked.current?.title, "Standup")
        XCTAssertEqual(picked.next?.title, "Review")
        XCTAssertNil(AgendaLogic.pick([events[0], events[1]], now: now).current)
        XCTAssertNil(AgendaLogic.pick([events[0], events[1]], now: now).next)
    }

    func testOnlyKnownMeetingLinksAreOpened() {
        XCTAssertEqual(AgendaLogic.meetingLink(in: ["Join: https://us02web.zoom.us/j/123456789?pwd=abc"])?.service, "Zoom")
        XCTAssertEqual(AgendaLogic.meetingLink(in: ["Room 4", "https://teams.microsoft.com/l/meetup-join/abc"])?.service, "Teams")
        XCTAssertEqual(AgendaLogic.meetingLink(in: ["https://meet.google.com/abc-defg-hij"])?.url.host(), "meet.google.com")
        XCTAssertEqual(AgendaLogic.meetingLink(in: ["https://example.com/agenda and https://zoom.us/j/1"])?.url.absoluteString, "https://zoom.us/j/1")
        // Not https, not a meeting service, or only made to look like one.
        XCTAssertNil(AgendaLogic.meetingLink(in: ["http://zoom.us/j/123"]))
        XCTAssertNil(AgendaLogic.meetingLink(in: ["https://example.com/zoom.us/j/123"]))
        XCTAssertNil(AgendaLogic.meetingLink(in: ["https://zoom.us.example.com/j/123"]))
        XCTAssertNil(AgendaLogic.meetingLink(in: ["https://notzoom.us/j/123"]))
        XCTAssertNil(AgendaLogic.meetingLink(in: ["Conference room B", ""]))
    }

    func testWhatIsSaid() {
        let calendar = Calendar.current
        let standup = event("Standup", from: -600, to: 1200), review = event("Review", from: 1800, to: 5400)
        let until = standup.end.formatted(date: .omitted, time: .shortened), at = review.start.formatted(date: .omitted, time: .shortened)
        let said = AgendaLogic.describe(current: standup, next: review, now: now, calendar: calendar)
        XCTAssertTrue(said.hasPrefix("Now: Standup, until \(until)."), said)
        // Within the same day it says how long until it starts; a late-evening "now" may put it tomorrow.
        XCTAssertTrue(said.contains("Next: Review, in 30 minutes, at \(at).") || said.contains("Next: Review, tomorrow at \(at)."), said)
        XCTAssertEqual(AgendaLogic.describe(current: nil, next: nil, now: now, calendar: calendar), "Nothing on your calendar in the next week.")
        XCTAssertTrue(AgendaLogic.describe(current: standup, next: nil, now: now, calendar: calendar).hasSuffix("Nothing after that in the next week."))
        let untitled = AgendaLogic.describe(current: nil, next: event("  ", from: 86400 * 3, to: 86400 * 3 + 3600), now: now, calendar: calendar)
        XCTAssertTrue(untitled.hasPrefix("Next: an event with no title, on "), untitled)
    }
}

final class AppActionTests: XCTestCase {
    func testEveryActionHasAName() {
        for action in SplitAction.allCases {
            XCTAssertNotNil(SplitAction.caseDisplayRepresentations[action], action.rawValue)
        }
        XCTAssertGreaterThanOrEqual(SplitAction.allCases.count, 12)
    }

    func testNewCommandsAreListedWithoutAKey() {
        for command in [Command.progressTones, .indentTones, .sayIndentation, .watchWindow, .whatsNext] {
            XCTAssertFalse(command.title.isEmpty)
            XCTAssertNil(command.defaultKey, "no key until the user chooses one")
        }
    }

    func testVoiceCommandsFindTheNewActions() {
        func name(_ said: String) -> String? { VoiceCommands.match(said, in: VoiceCommands.all)?.name }
        XCTAssertEqual(name("what's next"), "What's next?")
        XCTAssertEqual(name("next meeting"), "What's next?")
        XCTAssertEqual(name("watch this window"), "Watch this window")
        XCTAssertEqual(name("stop watching"), "Watch this window")
        XCTAssertEqual(name("indentation"), "How far is this indented?")
        XCTAssertEqual(name("indentation tones"), "Indentation tones")
        XCTAssertEqual(name("progress bar tones"), "Progress bar tones")
        // Opening a link acts for you: not by voice alone while a call plays through speakers.
        XCTAssertEqual(VoiceCommands.match("join my meeting", in: VoiceCommands.all)?.guarded, true)
        XCTAssertEqual(VoiceCommands.match("what's next", in: VoiceCommands.all)?.guarded, false)
    }
}
