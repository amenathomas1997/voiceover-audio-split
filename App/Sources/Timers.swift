// Timers.swift — timers and reminders, set by voice or typing: "set a timer for
// 10 minutes", "remind me at 3 pm to call the doctor", "remind me in 20 minutes
// to check the oven" (also in Spanish, French and German). When one is due, a
// tone plays and it is spoken, and a notification is posted if allowed.
// Pending ones are saved in UserDefaults on this Mac only, so they survive a
// restart; any that came due while the app wasn't running are said once, as missed.

import AppKit
import SwiftUI
import UserNotifications

/// A timer (it has a duration) or a reminder at a time, with an optional message.
struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var due: Date
    /// What to be reminded of, or empty.
    var message: String
    /// For timers: how long it runs. Nil for reminders.
    var duration: TimeInterval?
    var created: Date

    var isTimer: Bool { duration != nil }
}

// MARK: - Parser

/// Understands spoken or typed requests for timers and reminders. Pure, so it is tested.
enum ReminderParser {
    /// The longest timer or reminder accepted: a week.
    static let longest: TimeInterval = 7 * 24 * 3600

    private static let timerWords: Set<String> = ["timer", "timers", "countdown", "temporizador", "temporizadores",
                                                  "minuteur", "minuterie", "chrono"]
    private static let alarmWords: Set<String> = ["alarm", "alarma", "alarme", "wecker"]
    private static let triggers: [[String]] = [
        ["remind", "me"], ["reminder"], ["remind"],
        ["recuerdame"], ["recordatorio"], ["recordarme"],
        ["rappelle", "moi"], ["rappel"], ["rappeler"],
        ["erinnere", "mich"], ["erinner", "mich"], ["erinnerung"],
    ]
    /// Words before a length of time: "in 20 minutes".
    private static let inWords: Set<String> = ["in", "en", "dans", "within"]
    /// Words before a clock time: "at 3 pm", "a las 3", "à 15 h", "um 15 Uhr".
    private static let atWords: Set<String> = ["at", "for", "a", "um", "para", "pour", "fur", "gegen", "vers"]
    private static let articles: Set<String> = ["las", "la", "l"]
    private static let tomorrowWords: Set<String> = ["tomorrow", "manana", "demain", "morgen"]
    private static let connectors: Set<String> = ["and", "y", "et", "und"]
    /// Words that join the time to the message: "remind me in 5 minutes *to* ...".
    private static let fillers: Set<String> = ["to", "that", "about", "of", "que", "de", "d", "dass", "zu", "an",
                                               "for", "para", "pour", "fur", "called", "named", "me", "please", "bitte"]
    private static let trailing: Set<String> = ["please", "bitte", "plait", "favor"]
    private static let halfWords: Set<String> = ["half", "media", "medio", "demi", "demie", "halbe", "halb", "halben"]

    private static let units: [String: TimeInterval] = {
        var units: [String: TimeInterval] = [:]
        for word in ["second", "seconds", "sec", "secs", "segundo", "segundos", "seconde", "secondes", "sekunde", "sekunden"] {
            units[word] = 1
        }
        for word in ["minute", "minutes", "min", "mins", "minuto", "minutos", "minuten"] { units[word] = 60 }
        for word in ["hour", "hours", "hr", "hrs", "h", "hora", "horas", "heure", "heures", "stunde", "stunden"] { units[word] = 3600 }
        return units
    }()

    private static let numbers: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90, "a": 1, "an": 1,
        "uno": 1, "una": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
        "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12, "quince": 15, "veinte": 20, "treinta": 30,
        "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
        "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "quinze": 15, "vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50,
        "soixante": 60,
        "ein": 1, "eine": 1, "einen": 1, "einer": 1, "zwei": 2, "drei": 3, "vier": 4, "funf": 5, "sechs": 6,
        "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwolf": 12, "funfzehn": 15, "zwanzig": 20,
        "dreissig": 30, "dreißig": 30, "vierzig": 40, "funfzig": 50, "sechzig": 60,
        "eineinhalb": 1.5, "anderthalb": 1.5,
    ]

    /// A timer or reminder from what was said, or nil if it isn't one.
    static func parse(_ text: String, now: Date, calendar: Calendar) -> Reminder? {
        let (words, shown) = tokenize(text)
        guard !words.isEmpty else { return nil }

        if let trigger = findTrigger(words) {
            return reminder(words, shown, after: trigger, now: now, calendar: calendar)
        }
        if let index = words.firstIndex(where: timerWords.contains) {
            // The length can come before ("a 10 minute timer") or after ("timer for 10 minutes").
            for start in words.indices {
                guard let (length, end) = duration(words, start), length > 0, length <= longest else { continue }
                let rest = end > index ? Array(end..<words.count) : Array((index + 1)..<words.count)
                return Reminder(due: now.addingTimeInterval(length), message: message(rest, words, shown),
                                duration: length, created: now)
            }
            return nil
        }
        if let index = words.firstIndex(where: alarmWords.contains) {
            var tomorrow = false
            var start = index + 1
            while start < words.count {
                if tomorrowWords.contains(words[start]) { tomorrow = true; start += 1; continue }
                if atWords.contains(words[start]) || articles.contains(words[start]) { start += 1; continue }
                break
            }
            guard let time = clock(words, start) else { return nil }
            if time.end < words.count, tomorrowWords.contains(words[time.end]) { tomorrow = true }
            guard let due = next(time, tomorrow: tomorrow, now: now, calendar: calendar) else { return nil }
            return Reminder(due: due, message: "", duration: nil, created: now)
        }
        return nil
    }

    /// Words to match (lowercase, without accents or apostrophes) and the same words
    /// as written, for the message. Punctuation separates words: "3:30" is "3 30".
    static func tokenize(_ text: String) -> (keys: [String], shown: [String]) {
        let apostrophes: Set<Character> = ["'", "\u{2019}"]
        var shown: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || (apostrophes.contains(character) && !current.isEmpty) {
                current.append(character)
            } else if !current.isEmpty {
                shown.append(current)
                current = ""
            }
        }
        if !current.isEmpty { shown.append(current) }
        shown = shown.map { word in
            var word = word
            while let last = word.last, apostrophes.contains(last) { word.removeLast() }
            return word
        }.filter { !$0.isEmpty }
        let keys = shown.map { word in
            String(word.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { !apostrophes.contains($0) })
        }
        return (keys, shown)
    }

    private static func findTrigger(_ words: [String]) -> Int? {
        for start in words.indices {
            for trigger in triggers where start + trigger.count <= words.count
                && Array(words[start..<start + trigger.count]) == trigger {
                return start + trigger.count
            }
        }
        return nil
    }

    private static func reminder(_ words: [String], _ shown: [String], after trigger: Int, now: Date, calendar: Calendar) -> Reminder? {
        var used = IndexSet()
        var due: Date?
        var tomorrow = false
        var clockTime: ClockTime?

        var index = trigger
        while index < words.count, due == nil, clockTime == nil {
            let word = words[index]
            if inWords.contains(word), let (length, end) = duration(words, index + 1) {
                guard length > 0, length <= longest else { return nil }
                due = now.addingTimeInterval(length)
                used.insert(integersIn: index..<end)
            } else if atWords.contains(word) {
                var start = index + 1
                if start < words.count, articles.contains(words[start]) { start += 1 }
                // "a" and "for" are often just that, so they need "a las 3" or a clear time
                // such as "for 3 pm" or "à 15 h". "At 3" is enough.
                let bare = ["at", "um", "gegen"].contains(word) || start > index + 1
                if let time = clock(words, start), bare || time.explicit {
                    clockTime = time
                    used.insert(integersIn: index..<time.end)
                }
            }
            index += 1
        }
        // "Remind me to stretch 10 minutes from now."
        if due == nil, clockTime == nil {
            for start in trigger..<words.count {
                guard let (length, end) = duration(words, start) else { continue }
                guard length > 0, length <= longest else { return nil }
                due = now.addingTimeInterval(length)
                var last = end
                if last + 1 < words.count, words[last] == "from", words[last + 1] == "now" { last += 2 }
                else if last < words.count, words[last] == "later" { last += 1 }
                used.insert(integersIn: start..<last)
                break
            }
        }
        for index in trigger..<words.count where tomorrowWords.contains(words[index]) && !used.contains(index) {
            // "de la mañana" means in the morning, not tomorrow.
            if words[index] == "manana" && index > 0 && words[index - 1] == "la" { continue }
            tomorrow = true
            used.insert(index)
        }
        if let clockTime { due = next(clockTime, tomorrow: tomorrow, now: now, calendar: calendar) }
        guard let due else { return nil }
        let rest = (trigger..<words.count).filter { !used.contains($0) }
        return Reminder(due: due, message: message(rest, words, shown), duration: nil, created: now)
    }

    /// The words left over, without the little words that joined them to the time.
    private static func message(_ indexes: [Int], _ words: [String], _ shown: [String]) -> String {
        var indexes = indexes[...]
        var dropped = 0
        while let first = indexes.first, fillers.contains(words[first]), dropped < 2 {
            indexes = indexes.dropFirst()
            dropped += 1
        }
        while let last = indexes.last, trailing.contains(words[last]) { indexes = indexes.dropLast() }
        if let last = indexes.last, words[last] == "por" { indexes = indexes.dropLast() }
        return indexes.map { shown[$0] }.joined(separator: " ")
    }

    // MARK: Lengths of time

    /// A number such as "10", "ten", "twenty five", "una", or "one and a half".
    private static func number(_ words: [String], _ index: Int) -> (Double, Int)? {
        guard index < words.count else { return nil }
        let word = words[index]
        var value: Double
        var next = index + 1
        if let digits = Double(word), word.allSatisfy(\.isNumber) {
            value = digits
        } else if let named = numbers[word] {
            value = named
            // "twenty five"
            if named >= 20, named.truncatingRemainder(dividingBy: 10) == 0, next < words.count,
               let ones = numbers[words[next]], ones >= 1, ones <= 9, words[next] != "a", words[next] != "an" {
                value += ones
                next += 1
            }
        } else if halfWords.contains(word) {
            // "half an hour", "media hora"
            value = 0.5
            if next < words.count, words[next] == "a" || words[next] == "an" { next += 1 }
            return (value, next)
        } else {
            return nil
        }
        // "une demi-heure", "eine halbe Stunde", "a half hour"
        if value == 1, next < words.count, halfWords.contains(words[next]) { return (0.5, next + 1) }
        if let half = halfSuffix(words, next) { value += 0.5; next += half }
        return (value, next)
    }

    /// "and a half", "y media", "et demie", "und eine halbe": how many words it takes.
    private static func halfSuffix(_ words: [String], _ index: Int) -> Int? {
        guard index < words.count, connectors.contains(words[index]) else { return nil }
        for length in [1, 2] where index + length < words.count && halfWords.contains(words[index + length]) {
            if length == 1 || ["a", "an", "ein", "eine", "einer"].contains(words[index + 1]) { return length + 1 }
        }
        return nil
    }

    /// A length of time starting at `index`, in seconds, and the index after it:
    /// "10 minutes", "an hour and a half", "1 hour and 30 minutes", "10min".
    static func duration(_ words: [String], _ index: Int) -> (TimeInterval, Int)? {
        var total: TimeInterval = 0
        var position = index
        var found = false
        while position < words.count {
            var unit: TimeInterval
            var amount: Double
            var next: Int
            if let value = compact(words[position]) {
                amount = value.amount; unit = value.unit; next = position + 1
            } else if let (value, end) = number(words, position), end < words.count, let named = units[words[end]] {
                amount = value; unit = named; next = end + 1
            } else {
                break
            }
            if let half = halfSuffix(words, next) { amount += 0.5; next += half }
            total += amount * unit
            found = true
            position = next
            // "1 hour and 30 minutes", "1 hora y 30 minutos"
            if position < words.count, connectors.contains(words[position]),
               duration(words, position + 1) != nil {
                position += 1
            } else if position >= words.count || (compact(words[position]) == nil && number(words, position) == nil) {
                break
            }
        }
        return found ? (total, position) : nil
    }

    /// "10min", "2h", "30s".
    private static func compact(_ word: String) -> (amount: Double, unit: TimeInterval)? {
        let digits = word.prefix { $0.isNumber }
        let suffix = word.dropFirst(digits.count)
        guard !digits.isEmpty, !suffix.isEmpty, let value = Double(digits) else { return nil }
        let unit: TimeInterval? = switch suffix {
        case "s", "sec", "secs": 1
        case "m", "min", "mins": 60
        case "h", "hr", "hrs": 3600
        default: nil
        }
        return unit.map { (value, $0) }
    }

    // MARK: Clock times

    struct ClockTime: Equatable {
        enum Half { case am, pm }
        var hour: Int
        var minute: Int
        var half: Half?
        /// Said with a marker such as "pm", "h" or "uhr", or a word such as "noon".
        var explicit: Bool
        var end: Int
    }

    /// A clock time starting at `index`: "3 pm", "3 30 p m", "15 h 30", "15h30", "15 uhr",
    /// "noon", "3 de la tarde", "three thirty".
    static func clock(_ words: [String], _ index: Int) -> ClockTime? {
        guard index < words.count else { return nil }
        let word = words[index]
        switch word {
        case "noon", "midday", "mediodia", "midi", "mittag":
            return ClockTime(hour: 12, minute: 0, half: nil, explicit: true, end: index + 1)
        case "midnight", "medianoche", "minuit", "mitternacht":
            return ClockTime(hour: 0, minute: 0, half: nil, explicit: true, end: index + 1)
        default: break
        }

        var hour: Int
        var minute = 0
        var half: ClockTime.Half?
        var explicit = false
        var next = index + 1

        // Joined forms: "3pm", "15h30", "15h".
        let digits = word.prefix { $0.isNumber }
        let suffix = String(word.dropFirst(digits.count))
        if !digits.isEmpty, !suffix.isEmpty {
            guard let value = Int(digits) else { return nil }
            hour = value
            if suffix == "am" || suffix == "pm" {
                half = suffix == "am" ? .am : .pm
            } else if suffix.hasPrefix("h"), let rest = Int(suffix.dropFirst()) ?? (suffix == "h" ? 0 : nil) {
                minute = rest
            } else {
                return nil
            }
            explicit = true
        } else if let value = clockNumber(words, index) {
            hour = value.0
            next = value.1
        } else {
            return nil
        }

        // "o'clock", "h", "heures", "uhr"
        if next + 1 < words.count, words[next] == "o", words[next + 1] == "clock" { next += 2; explicit = true }
        else if next < words.count, words[next] == "oclock" { next += 1; explicit = true }
        else if next < words.count, ["h", "heure", "heures", "uhr", "hs", "horas"].contains(words[next]) { next += 1; explicit = true }

        // Minutes: "30", "thirty", "y media", "et quart".
        if next + 1 < words.count, ["y", "et"].contains(words[next]) {
            switch words[next + 1] {
            case "media", "demie", "demi": minute = 30; next += 2
            case "cuarto", "quart": minute = 15; next += 2
            default: break
            }
        } else if let value = clockNumber(words, next), value.0 < 60,
                  value.1 >= words.count || units[words[value.1]] == nil {
            // "3 30", "three thirty"; but not "at 3 10 minutes".
            minute = value.0
            next = value.1
        }

        // am, pm, "in the morning", "de la tarde", "du soir", "abends"
        if half == nil, let (found, end) = meridiem(words, next) {
            half = found
            next = end
            explicit = true
        }

        guard minute >= 0, minute < 60 else { return nil }
        if half != nil {
            guard hour >= 1, hour <= 12 else { return nil }
        } else {
            guard hour >= 0, hour <= 24 else { return nil }
            if hour == 24 { hour = 0 }
        }
        return ClockTime(hour: hour, minute: minute, half: half, explicit: explicit, end: next)
    }

    /// A whole number for a clock: digits, or words such as "three" or "twenty five".
    private static func clockNumber(_ words: [String], _ index: Int) -> (Int, Int)? {
        guard index < words.count else { return nil }
        let word = words[index]
        if word.allSatisfy(\.isNumber), let value = Int(word) { return (value, index + 1) }
        // "a" and "an" are numbers only in lengths of time ("a minute").
        guard word != "a", word != "an", let named = numbers[word], named == named.rounded() else { return nil }
        var value = Int(named)
        var next = index + 1
        if value >= 20, value % 10 == 0, next < words.count, let ones = numbers[words[next]], ones >= 1, ones <= 9,
           words[next] != "a", words[next] != "an" {
            value += Int(ones)
            next += 1
        }
        return (value, next)
    }

    private static func meridiem(_ words: [String], _ index: Int) -> (ClockTime.Half, Int)? {
        let am: [[String]] = [["am"], ["a", "m"], ["in", "the", "morning"], ["de", "la", "manana"], ["du", "matin"],
                              ["morgens"], ["vormittags"], ["fruh"]]
        let pm: [[String]] = [["pm"], ["p", "m"], ["in", "the", "afternoon"], ["in", "the", "evening"], ["at", "night"],
                              ["tonight"], ["de", "la", "tarde"], ["de", "la", "noche"], ["de", "l", "apres", "midi"], ["de", "lapres", "midi"],
                              ["du", "soir"], ["nachmittags"], ["abends"]]
        for (half, options) in [(ClockTime.Half.am, am), (.pm, pm)] {
            for option in options where index + option.count <= words.count
                && Array(words[index..<index + option.count]) == option {
                return (half, index + option.count)
            }
        }
        return nil
    }

    /// The next time the clock shows this time (on or after tomorrow, if asked).
    /// Without am or pm, "3" is whichever of 3:00 and 15:00 comes first.
    static func next(_ time: ClockTime, tomorrow: Bool, now: Date, calendar: Calendar) -> Date? {
        var hours: [Int]
        switch time.half {
        case .am: hours = [time.hour % 12]
        case .pm: hours = [time.hour % 12 + 12]
        case nil:
            if time.hour >= 1 && time.hour <= 12 {
                hours = [time.hour % 12, time.hour % 12 + 12]
            } else {
                hours = [time.hour]
            }
            // Tomorrow, "at 3" means the afternoon; "at 9" the morning.
            if tomorrow, hours.count == 2 { hours = [time.hour < 7 ? time.hour % 12 + 12 : time.hour % 12] }
        }
        let start = tomorrow ? calendar.date(byAdding: .day, value: 1, to: now) ?? now : now
        let candidates: [Date] = hours.compactMap { hour in
            guard var date = calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: start) else { return nil }
            if !tomorrow, date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return date
        }
        return candidates.min()
    }
}

// MARK: - Model

/// Pending timers and reminders: schedules them, says them when due, and keeps
/// them in UserDefaults so they survive a restart.
final class Reminders: ObservableObject {
    static let shared = Reminders()
    /// Where pending ones are saved, as JSON.
    static let storageKey = "reminders"
    /// Whether to post a notification as well as speaking (on unless turned off).
    static let notificationsKey = "reminderNotifications"
    /// Later than this when finally noticed (for example after sleep), it is said as missed.
    static let lateAfter: TimeInterval = 120

    /// Soonest first.
    @Published private(set) var pending: [Reminder] = []

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let announce: (String) -> Void
    private let sound: (Tone) -> Void
    /// Called with the ones due on time and the ones missed; by default, tones, speech and a notification.
    var deliver: (_ due: [Reminder], _ missed: [Reminder]) -> Void = { _, _ in }
    private var timer: Timer?
    private var started = false
    private var askedForNotifications = false

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
         announce: @escaping (String) -> Void = Announcer.say, sound: @escaping (Tone) -> Void = Tones.play,
         deliver: ((_ due: [Reminder], _ missed: [Reminder]) -> Void)? = nil) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.announce = announce
        self.sound = sound
        pending = Self.load(defaults)
        self.deliver = deliver ?? { [weak self] due, missed in self?.alert(due: due, missed: missed) }
    }

    /// At launch: says any that came due while the app wasn't running, once, then
    /// schedules the rest. Also checks again after sleep and clock changes.
    func start() {
        guard !started else { return }
        started = true
        checkDue()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkDue()
        }
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.checkDue()
        }
    }

    // MARK: Adding

    /// Understands a spoken or typed request and sets it, confirming aloud.
    /// Returns false (saying nothing) if it isn't a timer or reminder.
    @discardableResult
    func handle(_ text: String) -> Bool {
        guard let reminder = ReminderParser.parse(text, now: now(), calendar: calendar) else { return false }
        add(reminder)
        return true
    }

    /// A timer for a number of minutes, for a menu item or command.
    func setTimer(minutes: Double) {
        let length = minutes * 60
        add(Reminder(due: now().addingTimeInterval(length), message: "", duration: length, created: now()))
    }

    func add(_ reminder: Reminder) {
        pending.append(reminder)
        changed()
        sound(.status)
        announce(confirmation(for: reminder))
        askForNotifications()
    }

    func confirmation(for reminder: Reminder) -> String {
        if let duration = reminder.duration {
            let length = Self.spoken(duration)
            return reminder.message.isEmpty ? String(localized: "Timer set for \(length).")
                                            : String(localized: "Timer set for \(length): \(reminder.message).")
        }
        let when = spokenTime(reminder.due)
        return reminder.message.isEmpty ? String(localized: "Reminder set for \(when).")
                                        : String(localized: "Reminder set for \(when): \(reminder.message).")
    }

    // MARK: Listing and cancelling

    /// "2 reminders. Timer for 10 minutes, ends at 3:10 PM, in 8 minutes. ..."
    var spokenList: String {
        guard !pending.isEmpty else { return String(localized: "No timers or reminders.") }
        let count = pending.count == 1 ? String(localized: "1 timer or reminder.")
                                       : String(localized: "\(pending.count) timers and reminders.")
        return ([count] + pending.map(describe)).joined(separator: " ")
    }

    func speakList() { announce(spokenList) }

    /// One line for the list: what it is, when, and how long until then.
    func describe(_ reminder: Reminder) -> String {
        let left = Self.spoken(max(0, reminder.due.timeIntervalSince(now())))
        let time = spokenTime(reminder.due)
        if let duration = reminder.duration {
            let length = Self.spoken(duration)
            return reminder.message.isEmpty
                ? String(localized: "Timer for \(length), ends at \(time), in \(left).")
                : String(localized: "Timer for \(length), \(reminder.message), ends at \(time), in \(left).")
        }
        return reminder.message.isEmpty ? String(localized: "Reminder at \(time), in \(left).")
                                        : String(localized: "\(reminder.message), at \(time), in \(left).")
    }

    /// Cancels the one set most recently, and says which.
    func cancelLast() {
        guard let last = pending.max(by: { $0.created < $1.created }) else {
            return announce(String(localized: "There are no timers or reminders to cancel."))
        }
        cancel(last.id)
    }

    func cancelAll() {
        let count = pending.count
        guard count > 0 else { return announce(String(localized: "There are no timers or reminders to cancel.")) }
        pending = []
        changed()
        announce(count == 1 ? String(localized: "Cancelled 1 timer or reminder.")
                            : String(localized: "Cancelled \(count) timers and reminders."))
    }

    func cancel(_ id: UUID) {
        guard let reminder = pending.first(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        changed()
        if let duration = reminder.duration {
            announce(String(localized: "Cancelled the timer for \(Self.spoken(duration))."))
        } else {
            announce(reminder.message.isEmpty ? String(localized: "Cancelled the reminder at \(spokenTime(reminder.due)).")
                                              : String(localized: "Cancelled the reminder: \(reminder.message)."))
        }
    }

    // MARK: Due

    /// Says every one that is due, and schedules the next.
    func checkDue() {
        let current = now()
        let due = pending.filter { $0.due <= current }
        if !due.isEmpty {
            pending.removeAll { $0.due <= current }
            save()
            let missed = due.filter { current.timeIntervalSince($0.due) > Self.lateAfter }
            deliver(due.filter { current.timeIntervalSince($0.due) <= Self.lateAfter }, missed)
        }
        schedule()
    }

    /// What is said when they come due: on time first, then any missed.
    func dueText(due: [Reminder], missed: [Reminder]) -> String {
        let onTime = due.map { reminder -> String in
            if let duration = reminder.duration {
                let length = Self.spoken(duration)
                return reminder.message.isEmpty ? String(localized: "Timer done: \(length).")
                                                : String(localized: "Timer done: \(reminder.message), \(length).")
            }
            return reminder.message.isEmpty ? String(localized: "Reminder: it's \(spokenTime(reminder.due)).")
                                            : String(localized: "Reminder: \(reminder.message).")
        }
        let late = missed.map { reminder -> String in
            let time = spokenTime(reminder.due, relative: false)
            if let duration = reminder.duration {
                let length = Self.spoken(duration)
                return reminder.message.isEmpty ? String(localized: "Missed timer for \(length), which ended at \(time).")
                                                : String(localized: "Missed timer for \(length), \(reminder.message), which ended at \(time).")
            }
            return reminder.message.isEmpty ? String(localized: "Missed reminder at \(time).")
                                            : String(localized: "Missed reminder at \(time): \(reminder.message).")
        }
        return (onTime + late).joined(separator: " ")
    }

    private func alert(due: [Reminder], missed: [Reminder]) {
        let text = dueText(due: due, missed: missed)
        // Three tones to stand out, then the words.
        for step in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.45) { [weak self] in self?.sound(.device) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.announce(text) }
        postNotification(text, timer: due.allSatisfy(\.isTimer) && missed.isEmpty)
    }

    // MARK: Scheduling and saving

    private func changed() {
        pending.sort { $0.due < $1.due }
        save()
        schedule()
    }

    /// One timer, for the soonest. Run loop timers can fire late after sleep; waking checks again.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard let soonest = pending.map(\.due).min() else { return }
        let timer = Timer(fire: Date().addingTimeInterval(max(0, soonest.timeIntervalSince(now()))), interval: 0, repeats: false) { [weak self] _ in self?.checkDue() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func save() {
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(_ defaults: UserDefaults) -> [Reminder] {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else { return [] }
        return saved.sorted { $0.due < $1.due }
    }

    // MARK: Notifications

    private var notificationsOn: Bool { defaults.object(forKey: Self.notificationsKey) as? Bool ?? true }

    /// Asked the first time one is set, so the permission prompt makes sense.
    private func askForNotifications() {
        guard notificationsOn, !askedForNotifications, Bundle.main.bundleIdentifier != nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            log("Reminder notifications allowed: \(granted)")
        }
    }

    private func postNotification(_ text: String, timer: Bool) {
        guard notificationsOn, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let content = UNMutableNotificationContent()
        content.title = timer ? String(localized: "Timer done") : String(localized: "Reminder")
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log("Could not post reminder notification: \(error.localizedDescription)") }
        }
    }

    // MARK: Words

    /// "10 minutes", "1 hour, 30 minutes", "45 seconds".
    static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 60 ? [.second] : seconds < 3600 ? [.minute, .second] : [.day, .hour, .minute]
        let rounded = seconds < 60 ? seconds.rounded() : (seconds / 60).rounded() * 60
        return formatter.string(from: max(seconds < 60 ? 1 : 60, rounded)) ?? ""
    }

    /// "3:00 PM", "tomorrow at 9:00 AM", or a date for later ones.
    func spokenTime(_ date: Date, relative: Bool = true) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now()) || !relative { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)")
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
    }
}

// MARK: - Window

/// See and cancel timers and reminders, or type a new one.
struct RemindersView: View {
    @ObservedObject var reminders = Reminders.shared
    @State private var selection: Reminder.ID?
    @State private var request = ""
    @State private var problem = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "New timer or reminder, for example: remind me in 20 minutes to check the oven"),
                      text: $request)
                .focused($fieldFocused)
                .onSubmit(add)
            if !problem.isEmpty { Text(problem) }
            if reminders.pending.isEmpty {
                Text(String(localized: "No timers or reminders."))
            }
            List(reminders.pending, selection: $selection) { reminder in
                Text(reminders.describe(reminder)).tag(reminder.id)
            }
            .accessibilityLabel(String(localized: "Timers and reminders, soonest first"))
            .onKeyPress(.delete) {
                cancelSelected()
                return .handled
            }
            HStack {
                Button(String(localized: "Add"), action: add).disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(String(localized: "Cancel selected"), action: cancelSelected).disabled(selection == nil)
                Spacer()
                Button(String(localized: "Cancel all")) { reminders.cancelAll() }.disabled(reminders.pending.isEmpty)
            }
            Text(String(localized: "Saved on this Mac only, so they still go off after a restart."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520, height: 420)
        .onAppear { fieldFocused = true }
    }

    private func add() {
        if reminders.handle(request) {
            request = ""
            problem = ""
        } else {
            problem = String(localized: "That isn't a timer or reminder I understand. Try: set a timer for 10 minutes, or remind me at 3 pm to call the doctor.")
            Announcer.say(problem)
        }
    }

    private func cancelSelected() {
        guard let selection else { return }
        reminders.cancel(selection)
        self.selection = nil
    }
}
