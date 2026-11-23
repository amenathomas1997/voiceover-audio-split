// Agenda.swift — "What's next?": says the event that's on now and the next one on your
// calendar, and, asked again, opens that event's meeting link (Zoom, Teams, Google Meet,
// Webex or FaceTime). The calendar is read on the Mac, only when you ask; nothing is stored
// or sent. Links are opened only if they're https links to one of those services, so an
// invitation can't make the app open something else.

import AppKit
@preconcurrency import EventKit

struct AgendaEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    /// Where a meeting link might be: the event's own link, its location and its notes.
    var texts: [String] = []
}

enum AgendaLogic {
    /// The event that's on now (the one that started most recently) and the next to start.
    /// All-day events are left out: they're the day, not an appointment.
    static func pick(_ events: [AgendaEvent], now: Date) -> (current: AgendaEvent?, next: AgendaEvent?) {
        let timed = events.filter { !$0.allDay && $0.end > now }.sorted { $0.start < $1.start }
        return (timed.last { $0.start <= now }, timed.first { $0.start > now })
    }

    static let services: [(host: String, name: String)] = [
        ("zoom.us", "Zoom"), ("zoomgov.com", "Zoom"), ("teams.microsoft.com", "Teams"), ("teams.live.com", "Teams"),
        ("meet.google.com", "Google Meet"), ("webex.com", "Webex"), ("facetime.apple.com", "FaceTime"),
    ]

    /// The first https link to a meeting service this app knows.
    static func meetingLink(in texts: [String]) -> (url: URL, service: String)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { continue }
                if let service = services.first(where: { host == $0.host || host.hasSuffix("." + $0.host) }) {
                    return (url, service.name)
                }
            }
        }
        return nil
    }

    private static func name(_ event: AgendaEvent) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "an event with no title") : String(title.prefix(120))
    }

    /// What is said: the event that's on, then the next one and when.
    static func describe(current: AgendaEvent?, next: AgendaEvent?, now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let current {
            parts.append(String(localized: "Now: \(name(current)), until \(current.end.formatted(date: .omitted, time: .shortened))."))
        }
        if let next {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            let wait = next.start.timeIntervalSince(now)
            if calendar.isDate(next.start, inSameDayAs: now) {
                parts.append(wait < 2 * 3600 ? String(localized: "Next: \(name(next)), in \(Reminders.spoken(wait)), at \(time).")
                                             : String(localized: "Next: \(name(next)), at \(time)."))
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next.start, inSameDayAs: tomorrow) {
                parts.append(String(localized: "Next: \(name(next)), tomorrow at \(time)."))
            } else {
                let day = next.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
                parts.append(String(localized: "Next: \(name(next)), on \(day) at \(time)."))
            }
        } else {
            parts.append(current == nil ? String(localized: "Nothing on your calendar in the next week.")
                                        : String(localized: "Nothing after that in the next week."))
        }
        return parts.joined(separator: " ")
    }
}

@MainActor
enum Agenda {
    private static let store = EKEventStore()
    /// A meeting link just mentioned: asking again while it stands opens it.
    private static var offered: (url: URL, service: String, title: String, until: Date)?

    /// Says what's on now and next. Asked again within twenty seconds of hearing about a
    /// meeting link, opens the link.
    static func whatsNext() {
        if let offer = offered, offer.until > Date() { return open(offer.url, service: offer.service, title: offer.title) }
        offered = nil
        withAccess {
            Tones.play(.status)
            events { events in
                let now = Date()
                let (current, next) = AgendaLogic.pick(events, now: now)
                var text = AgendaLogic.describe(current: current, next: next, now: now)
                // The link of what's on now, or of what starts within half an hour.
                let soon = next.flatMap { $0.start.timeIntervalSince(now) < 30 * 60 ? $0 : nil }
                for event in [soon, current].compactMap({ $0 }) {
                    guard let link = AgendaLogic.meetingLink(in: event.texts) else { continue }
                    offered = (link.url, link.service, event.title, Date().addingTimeInterval(20))
                    text += " " + String(localized: "It has a \(link.service) link: use the command again to open it.")
                    break
                }
                Announcer.say(text)
            }
        }
    }

    /// Opens the meeting link of the event that's on now, or of the next one if it starts
    /// within half an hour.
    static func join() {
        withAccess {
            events { events in
                let now = Date()
                let (current, next) = AgendaLogic.pick(events, now: now)
                let soon = next.flatMap { $0.start.timeIntervalSince(now) < 30 * 60 ? $0 : nil }
                for event in [soon, current].compactMap({ $0 }) {
                    if let link = AgendaLogic.meetingLink(in: event.texts) {
                        return open(link.url, service: link.service, title: event.title)
                    }
                }
                Announcer.say(String(localized: "No meeting with a link is on now or starts in the next half hour."))
            }
        }
    }

    private static func open(_ url: URL, service: String, title: String) {
        offered = nil
        Tones.play(.device)
        Announcer.say(String(localized: "Opening the \(service) link for \(title)."))
        log("Agenda: opening a meeting link.")
        NSWorkspace.shared.open(url)
    }

    /// Runs `body` once the calendar may be read, asking the first time.
    private static func withAccess(_ body: @escaping @MainActor () -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            body()
        case .notDetermined:
            store.requestFullAccessToEvents { granted, _ in
                Task { @MainActor in
                    granted ? body() : Announcer.say(String(localized: "Calendar access wasn't allowed."))
                }
            }
        default:
            Announcer.say(String(localized: "Calendar access is off. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Calendars: it needs full access to read your events."))
        }
    }

    /// Today's and this week's events, read off the main thread.
    private static func events(_ done: @escaping @MainActor ([AgendaEvent]) -> Void) {
        let store = store
        DispatchQueue.global(qos: .userInitiated).async {
            let now = Date()
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600),
                                                     end: now.addingTimeInterval(7 * 86400), calendars: nil)
            let found = store.events(matching: predicate).compactMap { event -> AgendaEvent? in
                // Not the ones that were called off, or that you said no to.
                if event.status == .canceled { return nil }
                if event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined { return nil }
                let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
                return AgendaEvent(title: event.title ?? "", start: event.startDate, end: event.endDate,
                                   allDay: event.isAllDay, texts: texts)
            }
            Task { @MainActor in done(found) }
        }
    }
}
