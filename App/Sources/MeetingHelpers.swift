// MeetingHelpers.swift — JAWS-style meeting commands for Zoom, Microsoft Teams and
// FaceTime: "am I muted?", toggle mute or video, raise or lower your hand, open or
// read the chat, who is talking, leave the meeting, and reading new chat messages
// as they arrive. They work while you're somewhere else: the meeting app is found
// even when it isn't in front, and its own buttons are pressed through the
// accessibility interface, which doesn't move the keyboard focus or the VoiceOver
// cursor.
//
// Only when a button can't be found is the app's own keyboard shortcut used. Key
// presses only reach the app in front, so the meeting app is brought forward for
// a moment, the shortcut is pressed, and the app you were in is brought back (only
// when the meeting app really came forward and is still in front, so nothing is
// switched behind your back if you moved on). VoiceOver says the app names as
// that happens.
//
// Button names differ by app, version and language, so they're kept in tables
// below (English, Spanish, French and German), and the matching is done by pure
// functions that the tests check. Names are compared whole (after dropping
// shortcut hints like "(⌘+Shift+M)"), so "Mute all" or "Mute participant" never
// count as your own mute button.
//
// All accessibility work runs on one background queue with the short timeouts
// from AXTools, never on the main thread.

import AppKit
import ApplicationServices

// MARK: - Apps and controls

enum MeetingApp: String, CaseIterable {
    case zoom, teams, faceTime

    var bundleIDs: [String] {
        switch self {
        case .zoom: ["us.zoom.xos"]
        case .teams: ["com.microsoft.teams2", "com.microsoft.teams"]
        case .faceTime: ["com.apple.FaceTime"]
        }
    }

    var name: String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Microsoft Teams"
        case .faceTime: "FaceTime"
        }
    }

    init?(bundleID: String) {
        guard let app = Self.allCases.first(where: { $0.bundleIDs.contains(bundleID) }) else { return nil }
        self = app
    }
}

/// The meeting controls the commands use. For each, "on" means: muted, camera on,
/// hand raised. Chat and leave have no state.
enum MeetingControl: CaseIterable {
    case mute, video, hand, chat, leave
}

enum MuteState: Equatable {
    case muted, unmuted

    var spoken: String {
        switch self {
        case .muted: String(localized: "You're muted")
        case .unmuted: String(localized: "You're unmuted")
        }
    }
}

/// One accessible name a control can have, already normalized (lowercase, no accents).
struct NamePattern: Equatable {
    let text: String
    /// The state the name itself tells: "Unmute audio" means you're muted.
    let state: Bool?
    /// For toggles whose name never changes ("Mic", "Camera"): the state when the
    /// control's value is 1; a value of 0 means the opposite.
    let whenValueIsOne: Bool?

    init(_ text: String, _ state: Bool? = nil, whenValueIsOne: Bool? = nil) {
        self.text = MeetingHelpers.normalize(text)
        self.state = state
        self.whenValueIsOne = whenValueIsOne
    }
}

/// An app's documented keyboard shortcut, used only when its button can't be found.
struct MeetingShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

struct ChatMessage: Equatable {
    let name: String
    let text: String

    var spoken: String { String(localized: "\(name): \(text)") }
}

/// A running meeting app, for choosing which one the commands act on.
struct MeetingCandidate: Equatable {
    let bundleID: String
    var isFront = false
    var isLastUsed = false
    var lastActive: Date?
}

// MARK: - Tables and pure logic

enum MeetingHelpers {
    /// UserDefaults key: read new chat messages aloud. Off by default.
    static let chatAnnounceKey = "meetingChatAnnounce"

    private static func on(_ text: String) -> NamePattern { NamePattern(text, true) }
    private static func off(_ text: String) -> NamePattern { NamePattern(text, false) }
    private static func plain(_ text: String) -> NamePattern { NamePattern(text) }
    private static func toggle(_ text: String, valueOne: Bool) -> NamePattern { NamePattern(text, whenValueIsOne: valueOne) }

    /// Accessible names of each app's controls, more specific ones first.
    /// GUESSED from the apps' help pages and translations; check against the real apps.
    static let patterns: [MeetingApp: [MeetingControl: [NamePattern]]] = [
        .zoom: [
            .mute: [
                off("Mute audio"), on("Unmute audio"), off("Mute my audio"), on("Unmute my audio"),
                off("Mute my microphone"), on("Unmute my microphone"), off("Mute microphone"), on("Unmute microphone"),
                off("Silenciar audio"), on("Reactivar audio"), on("Activar audio"), on("Reactivar el audio"),
                on("Cancelar silencio"), on("Dejar de silenciar"),
                off("Couper le son"), on("Réactiver le son"), on("Activer le son"), off("Désactiver le son"),
                off("Désactiver l'audio"), on("Activer l'audio"), on("Réactiver l'audio"),
                off("Audio stummschalten"), on("Audio-Stummschaltung aufheben"), on("Stummschaltung aufheben"),
                off("Stummschalten"),
                off("Mute"), on("Unmute"), off("Silenciar"), off("Muet"),
            ],
            .video: [
                off("Start video"), on("Stop video"), off("Start my video"), on("Stop my video"),
                off("Iniciar video"), on("Detener video"), off("Iniciar el video"), on("Detener el video"),
                off("Démarrer la vidéo"), on("Arrêter la vidéo"), off("Démarrer vidéo"), on("Arrêter vidéo"),
                off("Video starten"), on("Video beenden"), on("Video stoppen"),
            ],
            .hand: [
                off("Raise hand"), on("Lower hand"), off("Levantar la mano"), on("Bajar la mano"),
                off("Levantar mano"), on("Bajar mano"), off("Lever la main"), on("Baisser la main"),
                off("Hand heben"), on("Hand senken"),
            ],
            .chat: [
                plain("Chat"), plain("Open chat"), plain("Show chat"), plain("Meeting chat"), plain("Abrir chat"),
                plain("Chatear"), plain("Converser"), plain("Discussion"), plain("Ouvrir le chat"), plain("Chat öffnen"),
            ],
            .leave: [
                plain("Leave"), plain("Leave meeting"), plain("End"), plain("Salir"), plain("Finalizar"),
                plain("Quitter"), plain("Terminer"), plain("Fin"), plain("Verlassen"), plain("Beenden"),
            ],
        ],
        .teams: [
            .mute: [
                off("Mute mic"), on("Unmute mic"), off("Mute microphone"), on("Unmute microphone"),
                off("Silenciar micrófono"), on("Reactivar micrófono"), on("Activar micrófono"),
                on("Reactivar audio"), on("Activar audio"), on("Activar sonido"),
                off("Désactiver le micro"), on("Activer le micro"), off("Couper le micro"),
                off("Désactiver le son"), on("Activer le son"),
                off("Mikrofon stummschalten"), on("Stummschaltung des Mikrofons aufheben"),
                on("Stummschaltung aufheben"), off("Stummschalten"),
                off("Mute"), on("Unmute"), off("Silenciar"),
                // The new Teams' mic button is a toggle named just "Mic": on means you can be heard.
                toggle("Mic", valueOne: false), toggle("Microphone", valueOne: false), toggle("Micrófono", valueOne: false),
                toggle("Micro", valueOne: false), toggle("Mikrofon", valueOne: false),
            ],
            .video: [
                off("Turn camera on"), on("Turn camera off"), off("Turn on camera"), on("Turn off camera"),
                off("Activar cámara"), on("Desactivar cámara"), off("Activar la cámara"), on("Desactivar la cámara"),
                off("Activer la caméra"), on("Désactiver la caméra"),
                off("Kamera einschalten"), on("Kamera ausschalten"),
                // Accents are ignored, so "Camera" is also "Cámara" and "Caméra".
                toggle("Camera", valueOne: true), toggle("Kamera", valueOne: true), toggle("Video", valueOne: true),
            ],
            .hand: [
                off("Raise hand"), on("Lower hand"), off("Raise your hand"), on("Lower your hand"),
                off("Levantar la mano"), on("Bajar la mano"), off("Lever la main"), on("Baisser la main"),
                off("Hand heben"), on("Hand senken"),
                off("Raise"), on("Lower"), off("Levantar"), on("Bajar"), off("Lever"), on("Baisser"),
                off("Heben"), on("Senken"),
            ],
            .chat: [
                plain("Show conversation"), plain("Open chat"), plain("Show chat"), plain("Chat"),
                plain("Mostrar conversación"), plain("Conversación"), plain("Afficher la conversation"),
                plain("Conversation"), plain("Unterhaltung anzeigen"), plain("Unterhaltung"),
            ],
            .leave: [
                plain("Leave"), plain("Hang up"), plain("Leave meeting"), plain("Leave call"), plain("Salir"),
                plain("Colgar"), plain("Quitter"), plain("Raccrocher"), plain("Verlassen"), plain("Auflegen"),
            ],
        ],
        .faceTime: [
            .mute: [
                on("Unmute"), toggle("Mute", valueOne: true), toggle("Silenciar", valueOne: true),
                toggle("Couper le son", valueOne: true), toggle("Silence", valueOne: true),
                toggle("Stummschalten", valueOne: true), toggle("Ton aus", valueOne: true),
            ],
            .video: [
                off("Turn camera on"), on("Turn camera off"),
                // Also "Cámara", "Caméra" and "Vidéo": accents are ignored.
                toggle("Camera", valueOne: true), toggle("Video", valueOne: true), toggle("Kamera", valueOne: true),
            ],
            .hand: [],
            .chat: [],
            .leave: [
                plain("Leave"), plain("End"), plain("End call"), plain("Salir"), plain("Finalizar"),
                plain("Quitter"), plain("Fin"), plain("Raccrocher"), plain("Verlassen"), plain("Beenden"),
            ],
        ],
    ]

    /// After Zoom's Leave or End, the button that leaves only you. "End meeting for
    /// all" is never in this list, so it's never pressed; nor is the toolbar's own
    /// "Leave", which would close the question again.
    static let leaveConfirmNames: [String] = [
        "Leave meeting", "Salir de la reunión", "Abandonar reunión", "Abandonar la reunión",
        "Quitter la réunion", "Meeting verlassen", "Besprechung verlassen",
    ].map(normalize)

    /// Documented shortcuts. FaceTime has none for these on the Mac.
    static let shortcuts: [MeetingApp: [MeetingControl: MeetingShortcut]] = [
        .zoom: [
            .mute: MeetingShortcut(keyCode: 0, flags: [.maskCommand, .maskShift]),   // Cmd+Shift+A
            .video: MeetingShortcut(keyCode: 9, flags: [.maskCommand, .maskShift]),  // Cmd+Shift+V
            .hand: MeetingShortcut(keyCode: 16, flags: [.maskAlternate]),             // Option+Y
            .chat: MeetingShortcut(keyCode: 4, flags: [.maskCommand, .maskShift]),   // Cmd+Shift+H
        ],
        .teams: [
            .mute: MeetingShortcut(keyCode: 46, flags: [.maskCommand, .maskShift]),  // Cmd+Shift+M
            .video: MeetingShortcut(keyCode: 31, flags: [.maskCommand, .maskShift]), // Cmd+Shift+O
            .hand: MeetingShortcut(keyCode: 40, flags: [.maskCommand, .maskShift]),  // Cmd+Shift+K
            .leave: MeetingShortcut(keyCode: 4, flags: [.maskCommand, .maskShift]),  // Cmd+Shift+H, hang up
        ],
        .faceTime: [:],
    ]

    /// Window titles that are probably a meeting, searched first.
    static let meetingWindowTitles: [MeetingApp: [String]] = [
        .zoom: ["zoom meeting", "zoom webinar", "reunion de zoom", "reunion zoom", "zoom-meeting", "zoom besprechung"],
        .teams: ["meeting", "call", "reunion", "llamada", "appel", "besprechung", "anruf"],
        .faceTime: ["facetime"],
    ]

    /// Names of chat message lists and chat windows.
    static let chatListNames: [String] = [
        "Chat", "Meeting chat", "Chat messages", "Messages", "Chat history", "Conversation", "Chat content",
        "Chat de la reunión", "Mensajes", "Mensajes de chat", "Conversación",
        "Chat de la réunion", "Messages du chat", "Discussion",
        "Besprechungschat", "Meeting-Chat", "Nachrichten", "Chatnachrichten", "Unterhaltung",
    ].map(normalize)

    // MARK: Normalizing and matching

    /// Lowercase, no accents, no shortcut hints ("Mute (⌘+Shift+M)" → "mute"),
    /// only the part before a comma, single spaces.
    static func normalize(_ text: String) -> String {
        var text = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        text = text.replacingOccurrences(of: "’", with: "'")
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        for separator in [",", ";", "\n", " - ", " – ", " — "] {
            if let range = text.range(of: separator) { text = String(text[..<range.lowerBound]) }
        }
        text = text.replacingOccurrences(of: #"[⌘⇧⌥⌃]"#, with: " ", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " .:…"))
    }

    /// Which table entry a control's names match, by position (lower is more specific).
    static func matchIndex(_ control: MeetingControl, names: [String], app: MeetingApp) -> Int? {
        let table = patterns[app]?[control] ?? []
        let normalized = names.map(normalize).filter { !$0.isEmpty }
        return table.indices.first { index in normalized.contains(table[index].text) }
    }

    /// Whether a control with these names and value is on (muted, camera on, hand
    /// raised). Nil when it isn't that control or its state can't be told.
    static func state(of control: MeetingControl, names: [String], value: Int?, app: MeetingApp) -> Bool? {
        guard let index = matchIndex(control, names: names, app: app), let pattern = patterns[app]?[control]?[index]
        else { return nil }
        if let state = pattern.state { return state }
        if let one = pattern.whenValueIsOne, let value { return value != 0 ? one : !one }
        return nil
    }

    static func muteState(fromButtonName name: String, app: MeetingApp, value: Int? = nil) -> MuteState? {
        state(of: .mute, names: [name], value: value, app: app).map { $0 ? .muted : .unmuted }
    }

    static func isLeaveConfirmation(_ names: [String]) -> Bool {
        names.map(normalize).contains { leaveConfirmNames.contains($0) }
    }

    static func windowTitleLooksLikeMeeting(_ title: String, app: MeetingApp) -> Bool {
        let title = normalize(title)
        return (meetingWindowTitles[app] ?? []).contains { title.contains($0) }
    }

    static func isChatListName(_ name: String) -> Bool {
        chatListNames.contains(normalize(name))
    }

    // MARK: Choosing the app

    /// The order to try running meeting apps in: the one in front, then the last one
    /// used before this app, then the most recently active, then Zoom, Teams, FaceTime.
    static func rank(_ candidates: [MeetingCandidate]) -> [MeetingCandidate] {
        func order(_ id: String) -> Int { MeetingApp(bundleID: id).flatMap { MeetingApp.allCases.firstIndex(of: $0) } ?? 99 }
        return candidates.filter { MeetingApp(bundleID: $0.bundleID) != nil }.sorted { a, b in
            if a.isFront != b.isFront { return a.isFront }
            if a.isLastUsed != b.isLastUsed { return a.isLastUsed }
            switch (a.lastActive, b.lastActive) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return order(a.bundleID) < order(b.bundleID)
            }
        }
    }

    // MARK: Who is talking

    /// Words that follow a name: "Ana López, speaking", "Ana is talking".
    static let speakingAfterName = [
        "is speaking", "is talking", "speaking", "talking",
        "esta hablando", "hablando", "est en train de parler", "en train de parler", "parle", "spricht",
    ]
    /// Words before a name: "Active speaker: Ana".
    static let speakingBeforeName = [
        "active speaker", "current speaker", "orador activo", "hablante activo", "intervenant actif",
        "orateur actif", "aktiver sprecher", "aktueller sprecher",
    ]
    static let notSpeaking = [
        "not speaking", "not talking", "isn't speaking", "no esta hablando", "ne parle pas", "spricht nicht",
    ]

    /// The names of the people the texts say are talking, in order, without repeats.
    static func speakers(in texts: [String]) -> [String] {
        var names: [String] = []
        for text in texts {
            guard let name = speaker(in: text), !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    static func speaker(in text: String) -> String? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let normalizedWhole = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if notSpeaking.contains(where: { normalizedWhole.contains($0) }) { return nil }
        for keyword in speakingBeforeName {
            guard let range = wordRange(of: keyword, in: text, options: options) else { continue }
            if let name = cleanName(String(text[range.upperBound...])) { return name }
        }
        for keyword in speakingAfterName {
            guard let range = wordRange(of: keyword, in: text, options: options) else { continue }
            if let name = cleanName(String(text[..<range.lowerBound])) { return name }
        }
        return nil
    }

    private static func wordRange(of word: String, in text: String, options: String.CompareOptions) -> Range<String.Index>? {
        var start = text.startIndex
        while let range = text.range(of: word, options: options, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return range }
            start = range.upperBound
        }
        return nil
    }

    private static func cleanName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-–—.").union(.whitespacesAndNewlines))
        // "Ana is" / "Ana está" / "Ana est" / "Ana ist" before the speaking word.
        for suffix in [" is", " esta", " está", " est", " ist"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        // Only the name: the first piece before a comma (tiles also say "muted", "video off").
        if let comma = name.firstIndex(of: ",") { name = String(name[..<comma]) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, name.split(separator: " ").count <= 6 else { return nil }
        return name
    }

    // MARK: Chat messages

    private static let timePattern = #"^\d{1,2}[:.h]\d{2}(\s?([ap]\.?\s?m\.?|uhr))?$"#
    private static let ignoredParts: Set<String> = ["edited", "editado", "modifie", "bearbeitet", "new", "nuevo", "nouveau", "neu"]
    private static let recipientParts: Set<String> = [
        "to everyone", "to me", "everyone", "a todos", "todos", "a todo el mundo", "a tout le monde", "tout le monde",
        "an alle", "alle",
    ]
    /// Your own name as the apps show it: your own messages aren't read back to you.
    static let selfNames: Set<String> = ["me", "you", "yo", "tu", "moi", "vous", "ich", "du"]

    /// The sender and text of a chat message, from the texts its row shows.
    static func chatMessage(fromParts rawParts: [String]) -> ChatMessage? {
        var parts: [String] = []
        for part in rawParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard !trimmed.isEmpty, parts.last != trimmed, !ignoredParts.contains(folded), !recipientParts.contains(folded),
                  trimmed.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            parts.append(trimmed)
        }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return chatMessage(fromLine: parts[0]) }
        // "From Ana to Everyone:" then the message.
        if let header = fromToHeader(parts[0]), !header.isEmpty {
            let text = parts.dropFirst().joined(separator: " ")
            return text.isEmpty ? nil : ChatMessage(name: header, text: text)
        }
        // The whole message may be repeated in the row's description: use the first full one.
        if let whole = parts.first(where: { $0.contains(":") }).flatMap(chatMessage(fromLine:)),
           parts.contains(where: { $0 == whole.name }) {
            return whole
        }
        let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard name.split(separator: " ").count <= 6 else { return nil }
        let text = parts.dropFirst().filter { $0 != name }.joined(separator: " ")
        return text.isEmpty ? nil : ChatMessage(name: name, text: text)
    }

    /// The sender in "From Ana to Everyone:", "De Ana a Todos:", "De Ana à Tout le monde :", "Von Ana an Alle:".
    private static func fromToHeader(_ text: String) -> String? {
        let pattern = #"^(?:from|de|von)\s+(.+?)\s+(?:to|a|à|an)\s+.+?\s*:\s*$"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return firstGroup(pattern, in: String(text[match]))
    }

    static func chatMessage(fromLine line: String) -> ChatMessage? {
        let fromTo = #"^(?:from|de|von)\s+(.+?)\s+(?:to|a|à|an)\s+.+?\s*:\s*(.+)$"#
        if let name = firstGroup(fromTo, in: line), let text = group(2, fromTo, in: line) {
            return ChatMessage(name: name, text: text)
        }
        let said = #"^(.+?)\s+(?:said|says|dijo|dice|a dit|schrieb|sagt)[:,]?\s+(.+)$"#
        if let name = firstGroup(said, in: line), name.split(separator: " ").count <= 4, let text = group(2, said, in: line) {
            return ChatMessage(name: name, text: text)
        }
        let colon = #"^([^:\d][^:]{0,60}?)\s*:\s+(.+)$"#
        if let name = firstGroup(colon, in: line), name.split(separator: " ").count <= 6, let text = group(2, colon, in: line) {
            return ChatMessage(name: name, text: text)
        }
        return nil
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? { group(1, pattern, in: text) }

    private static func group(_ number: Int, _ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              number < match.numberOfRanges, let range = Range(match.range(at: number), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The rows that are new since the last look. The first look (no previous rows)
    /// finds nothing new, so joining a meeting doesn't read the whole history.
    static func newMessages(previous: [String], current: [String]) -> [String] {
        guard !previous.isEmpty, !current.isEmpty else { return [] }
        // Find where the last rows seen are in the list now; everything after is new.
        let overlap = min(3, previous.count)
        let tail = Array(previous.suffix(overlap))
        for end in stride(from: current.count, through: 1, by: -1) {
            let start = end - tail.count
            if start >= 0, Array(current[start..<end]) == tail { return Array(current[end...]) }
        }
        if let last = previous.last, let index = current.lastIndex(of: last) { return Array(current[(index + 1)...]) }
        // The list scrolled past everything seen: read what wasn't seen, at most five.
        let seen = Set(previous)
        return Array(current.filter { !seen.contains($0) }.suffix(5))
    }

    static func isOwnMessage(_ message: ChatMessage) -> Bool {
        selfNames.contains(message.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    // MARK: Spoken questions

    /// For the lead's yes/no: asked before leaving.
    static var leaveNeedsConfirmation: String {
        let app = rank(runningCandidates(front: NSWorkspace.shared.frontmostApplication, lastUsed: nil)).first
            .flatMap { MeetingApp(bundleID: $0.bundleID) }
        return app.map { String(localized: "Leave the \($0.name) meeting?") } ?? String(localized: "Leave the meeting?")
    }

    static var noMeeting: String { String(localized: "No Zoom, Teams or FaceTime meeting is open.") }
}

// MARK: - Live commands

extension MeetingHelpers {
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.meetings")
    /// When each meeting app was last in front, by bundle ID. Main thread only.
    nonisolated(unsafe) private static var lastActive: [String: Date] = [:]
    nonisolated(unsafe) private static var started = false

    /// Starts noting which meeting app was used last and the chat reading, if it's on.
    /// Call once at launch; the commands also call it.
    static func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, MeetingApp(bundleID: id) != nil else { return }
            lastActive[id] = Date()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in updateChatWatch() }
        }
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, MeetingApp(bundleID: id) != nil {
            lastActive[id] = Date()
        }
        updateChatWatch()
    }

    // MARK: Entry points (call on the main thread; they return at once)

    /// Says "You're muted" or "You're unmuted".
    static func sayMuteStatus() {
        run { meeting in
            guard let found = meeting.find(.mute) else {
                return say(String(localized: "I couldn't find the mute button in \(meeting.app.name)."))
            }
            guard let muted = found.state else {
                return say(String(localized: "I found the mute button in \(meeting.app.name), but couldn't tell whether you're muted."))
            }
            say((muted ? MuteState.muted : .unmuted).spoken)
        }
    }

    static func toggleMute() { toggle(.mute) }
    static func toggleVideo() { toggle(.video) }
    static func toggleHand() { toggle(.hand) }

    /// Opens or closes the meeting chat with the app's chat button.
    static func openChat() { toggle(.chat) }

    /// Reads the last few chat messages, opening the chat first if it isn't showing.
    static func readChat(count: Int = 3) {
        run { meeting in
            var list = chatList(for: meeting)
            if list == nil, let button = meeting.find(.chat) {
                _ = press(button.element)
                Thread.sleep(forTimeInterval: 1.2)
                list = chatList(for: meeting)
            }
            guard let list else { return say(String(localized: "I couldn't find the chat in \(meeting.app.name).")) }
            let messages = chatRows(list).compactMap(chatMessage(fromParts:)).suffix(count)
            guard !messages.isEmpty else { return say(String(localized: "No chat messages yet.")) }
            say(messages.map(\.spoken).joined(separator: ". "))
        }
    }

    /// Says who is talking, if the app shows it.
    static func sayWhoIsTalking() {
        run { meeting in
            var texts: [String] = []
            for window in meeting.windows {
                for element in AX.descendants(of: window, limit: 5000, seconds: 3) {
                    for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
                        let text = AX.string(element, attribute)
                        if !text.isEmpty && text.count < 200 { texts.append(text) }
                    }
                }
            }
            let names = speakers(in: texts)
            switch names.count {
            case 0: say(String(localized: "I can't tell who's talking in this app"))
            case 1: say(String(localized: "\(names[0]) is talking"))
            default: say(String(localized: "Talking: \(ListFormatter.localizedString(byJoining: names))"))
            }
        }
    }

    /// Leaves the meeting. Unconfirmed, it only asks `leaveNeedsConfirmation`.
    static func leave(confirmed: Bool) {
        guard confirmed else { return Announcer.say(leaveNeedsConfirmation) }
        run { meeting in
            let button = meeting.find(.leave)
            if let button {
                guard press(button.element) else { return say(String(localized: "The Leave button couldn't be pressed.")) }
            } else if !sendShortcut(.leave, for: meeting) {
                return say(String(localized: "I couldn't find the Leave button in \(meeting.app.name)."))
            }
            // Zoom then asks: press "Leave meeting", never "End meeting for all", and
            // not the button just pressed, which would close the question.
            Thread.sleep(forTimeInterval: 0.8)
            if meeting.app == .zoom, let app = meeting.running, !app.isTerminated {
                let windows = axWindows(AX.application(app.processIdentifier))
                let confirm = windows.lazy.flatMap { controls(in: $0) }.first { item in
                    isLeaveConfirmation(item.names) && !(button.map { CFEqual($0.element, item.element) } ?? false)
                }
                if let confirm { _ = press(confirm.element) }
            }
            say(String(localized: "Left the meeting"))
        }
    }

    /// Whether new chat messages are read aloud.
    static var chatAnnounceEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: chatAnnounceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: chatAnnounceKey)
            updateChatWatch()
        }
    }

    static func toggleChatAnnouncements() {
        start()
        chatAnnounceEnabled.toggle()
        Tones.play(.status)
        Announcer.say(chatAnnounceEnabled ? String(localized: "New chat messages will be read")
                                          : String(localized: "New chat messages won't be read"))
    }

    // MARK: Finding the meeting

    struct Found {
        let element: AXUIElement
        let names: [String]
        let value: Int?
        let state: Bool?
    }

    struct Control {
        let element: AXUIElement
        let names: [String]
        let value: Int?
    }

    final class Meeting {
        let app: MeetingApp
        let pid: pid_t
        let window: AXUIElement
        /// The meeting window first, then the app's other windows (Zoom's chat can be its own).
        let windows: [AXUIElement]
        private var controlsCache: [Control]?

        init(app: MeetingApp, pid: pid_t, window: AXUIElement, windows: [AXUIElement], controls: [Control]) {
            self.app = app
            self.pid = pid
            self.window = window
            self.windows = windows
            controlsCache = controls
        }

        var running: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

        func refresh() { controlsCache = nil }

        var controls: [Control] {
            if let controlsCache { return controlsCache }
            let found = MeetingHelpers.controls(in: window)
            controlsCache = found
            return found
        }

        func find(_ control: MeetingControl) -> Found? {
            let matches = controls.compactMap { item in
                MeetingHelpers.matchIndex(control, names: item.names, app: app).map { (index: $0, item: item) }
            }
            guard let best = matches.min(by: { $0.index < $1.index })?.item else { return nil }
            return Found(element: best.element, names: best.names, value: best.value,
                         state: MeetingHelpers.state(of: control, names: best.names, value: best.value, app: app))
        }
    }

    private static let controlRoles: Set<String> = [
        kAXButtonRole, kAXCheckBoxRole, kAXMenuButtonRole, kAXRadioButtonRole, kAXPopUpButtonRole, "AXToggle",
    ]

    fileprivate static func controls(in window: AXUIElement) -> [Control] {
        AX.descendants(of: window, limit: 5000, seconds: 4).compactMap { element in
            guard controlRoles.contains(AX.string(element, kAXRoleAttribute)) else { return nil }
            return control(element)
        }
    }

    private static func control(_ element: AXUIElement) -> Control? {
        let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXDOMIdentifier", kAXIdentifierAttribute]
            .map { AX.string(element, $0) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return Control(element: element, names: names, value: number(element, kAXValueAttribute))
    }

    private static func number(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private static func axWindows(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Running meeting apps, for ranking. Reads only NSWorkspace, so it's cheap.
    fileprivate static func runningCandidates(front: NSRunningApplication?, lastUsed: NSRunningApplication?) -> [MeetingCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, MeetingApp(bundleID: id) != nil, !app.isTerminated else { return nil }
            return MeetingCandidate(bundleID: id, isFront: app == front, isLastUsed: app == lastUsed,
                                    lastActive: Thread.isMainThread ? lastActive[id] : nil)
        }
    }

    /// The meeting to act on: the first app, in ranked order, with a window holding
    /// a mute or leave button. Runs on the meetings queue.
    private static func locate(_ ranked: [MeetingCandidate]) -> Meeting? {
        for candidate in ranked {
            guard let app = MeetingApp(bundleID: candidate.bundleID),
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleID).first
            else { continue }
            let pid = running.processIdentifier
            let root = AX.application(pid)
            let windows = axWindows(root)
            let ordered = windows.sorted { a, b in
                windowTitleLooksLikeMeeting(AX.string(a, kAXTitleAttribute), app: app)
                    && !windowTitleLooksLikeMeeting(AX.string(b, kAXTitleAttribute), app: app)
            }
            for window in ordered {
                let found = controls(in: window)
                let isMeeting = found.contains { item in
                    [MeetingControl.mute, .leave].contains { matchIndex($0, names: item.names, app: app) != nil }
                }
                if isMeeting {
                    return Meeting(app: app, pid: pid, window: window,
                                   windows: [window] + windows.filter { !CFEqual($0, window) }, controls: found)
                }
            }
        }
        return nil
    }

    /// Checks the permission, finds the meeting off the main thread, and runs `body` there.
    private static func run(_ body: @escaping (Meeting) -> Void) {
        start()
        guard Hotkeys.isTrusted else {
            return Announcer.say(String(localized: "Allow keyboard shortcuts in Settings first; this uses the same permission."))
        }
        let ranked = rank(runningCandidates(front: NSWorkspace.shared.frontmostApplication,
                                            lastUsed: Controller.shared.lastUsedApp))
        guard !ranked.isEmpty else { return Announcer.say(noMeeting) }
        queue.async {
            guard let meeting = locate(ranked) else { return say(noMeeting) }
            body(meeting)
        }
    }

    private static func say(_ text: String, tone: Tone? = nil) {
        DispatchQueue.main.async {
            if let tone { Tones.play(tone) }
            Announcer.say(text)
        }
    }

    /// Presses with the accessibility action. A slow app can say "couldn't complete"
    /// after the press already happened, which counts as pressed.
    private static func press(_ element: AXUIElement) -> Bool {
        let result = AX.pressResult(element)
        return result == .success || result == .cannotComplete
    }

    /// Presses a control's button, or uses the app's shortcut, then says the new state.
    private static func toggle(_ control: MeetingControl) {
        run { meeting in
            let button = meeting.find(control)
            if let button {
                guard press(button.element) else { return say(String(localized: "That button couldn't be pressed.")) }
            } else if !sendShortcut(control, for: meeting) {
                return say(String(localized: "I couldn't find that button in \(meeting.app.name)."))
            }
            guard control != .chat else { return say(String(localized: "Chat button pressed")) }
            // Read the state back: the button's name or value changes once the app has reacted.
            Thread.sleep(forTimeInterval: 0.6)
            var state: Bool?
            if let button, let again = self.control(button.element) {
                state = self.state(of: control, names: again.names, value: again.value, app: meeting.app)
            }
            if state == nil || state == button?.state {
                meeting.refresh()
                state = meeting.find(control)?.state
            }
            if let previous = button?.state, state == previous { state = nil }
            announce(control, state: state, app: meeting.app)
        }
    }

    private static func announce(_ control: MeetingControl, state: Bool?, app: MeetingApp) {
        switch (control, state) {
        case (.mute, true?): say(MuteState.muted.spoken, tone: .micMuted)
        case (.mute, false?): say(MuteState.unmuted.spoken, tone: .micOn)
        case (.video, true?): say(String(localized: "Your video is on"), tone: .status)
        case (.video, false?): say(String(localized: "Your video is off"), tone: .status)
        case (.hand, true?): say(String(localized: "Hand raised"), tone: .status)
        case (.hand, false?): say(String(localized: "Hand lowered"), tone: .status)
        default: say(String(localized: "Done in \(app.name), but I couldn't tell what changed."), tone: .status)
        }
    }

    // MARK: Keyboard shortcuts

    /// Presses the app's shortcut: brings it forward for a moment, presses the keys,
    /// then brings back the app you were in. Runs on the meetings queue.
    private static func sendShortcut(_ control: MeetingControl, for meeting: Meeting) -> Bool {
        guard let shortcut = shortcuts[meeting.app]?[control], let target = meeting.running, CGPreflightPostEventAccess()
        else { return false }
        let previous = DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication }
        let wasInFront = previous?.processIdentifier == target.processIdentifier
        if !wasInFront && !bringForward(target) { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
            event?.flags = shortcut.flags
            event?.post(tap: .cghidEventTap)
        }
        if !wasInFront, let previous, !previous.isTerminated {
            Thread.sleep(forTimeInterval: 0.3)
            // Only if the meeting app is still in front: if the user already moved on, leave them there.
            let stillFront = DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication == target }
            if stillFront { _ = bringForward(previous) }
        }
        return true
    }

    /// Activates an app and waits up to a second for it to be in front.
    private static func bringForward(_ app: NSRunningApplication) -> Bool {
        DispatchQueue.main.sync {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        for attempt in 0..<10 {
            Thread.sleep(forTimeInterval: 0.1)
            if DispatchQueue.main.sync(execute: { NSWorkspace.shared.frontmostApplication == app }) { return true }
            // macOS can refuse a background app's request; opening the app again always brings it forward.
            if attempt == 4, let url = app.bundleURL {
                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                }
            }
        }
        return false
    }

    // MARK: Chat

    private static let listRoles: Set<String> = [kAXListRole, kAXTableRole, kAXOutlineRole]

    /// The chat message list: a list named like a chat, or the biggest list in a
    /// window titled like one. Runs on the meetings queue.
    private static func chatList(for meeting: Meeting) -> AXUIElement? {
        for window in meeting.windows {
            let windowIsChat = isChatListName(AX.string(window, kAXTitleAttribute))
            var lists: [AXUIElement] = []
            for element in AX.descendants(of: window, limit: 5000, seconds: 3)
            where listRoles.contains(AX.string(element, kAXRoleAttribute)) {
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map { AX.string(element, $0) }
                if names.contains(where: isChatListName) { return element }
                lists.append(element)
            }
            if windowIsChat, let biggest = lists.max(by: { rows(of: $0).count < rows(of: $1).count }) { return biggest }
        }
        return nil
    }

    private static func rows(of list: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(list, kAXRowsAttribute as CFString, &value) == .success,
           let rows = value as? [AXUIElement], !rows.isEmpty { return rows }
        return AX.children(list)
    }

    /// The texts of the last rows of a chat list, one array per message.
    private static func chatRows(_ list: AXUIElement, last: Int = 30) -> [[String]] {
        rows(of: list).suffix(last).map { row in
            var parts: [String] = []
            for element in AX.descendants(of: row, limit: 40, seconds: 0.5)
            where AX.string(element, kAXRoleAttribute) == kAXStaticTextRole {
                let text = AX.string(element, kAXValueAttribute).isEmpty ? AX.string(element, kAXTitleAttribute)
                                                                         : AX.string(element, kAXValueAttribute)
                if !text.isEmpty { parts.append(text) }
            }
            if parts.isEmpty {
                let own = AX.text(row)
                if !own.isEmpty { parts.append(own) }
            }
            return parts
        }
    }

    // Chat watching state, on the meetings queue.
    nonisolated(unsafe) private static var chatTimer: DispatchSourceTimer?
    nonisolated(unsafe) private static var watched: (pid: pid_t, list: AXUIElement)?
    nonisolated(unsafe) private static var seen: [String] = []
    nonisolated(unsafe) private static var lastSearch = Date.distantPast
    /// The order to look for meeting apps in, refreshed from the main thread.
    nonisolated(unsafe) private static var watchRanking: [MeetingCandidate] = []

    /// Polls every 2 seconds only while chat reading is on and a meeting app is running.
    static func updateChatWatch() {
        let ranked = rank(runningCandidates(front: NSWorkspace.shared.frontmostApplication, lastUsed: nil))
        let wanted = chatAnnounceEnabled && !ranked.isEmpty && Hotkeys.isTrusted
        queue.async {
            watchRanking = ranked
            if wanted && chatTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
                timer.setEventHandler { checkChat() }
                timer.resume()
                chatTimer = timer
            } else if !wanted, let timer = chatTimer {
                timer.cancel()
                chatTimer = nil
                watched = nil
                seen = []
            }
        }
    }

    private static func checkChat() {
        if let current = watched, NSRunningApplication(processIdentifier: current.pid)?.isTerminated == false,
           !AX.string(current.list, kAXRoleAttribute).isEmpty {
            let rows = chatRows(current.list)
            let keys = rows.map { $0.joined(separator: " | ") }
            let fresh = Set(newMessages(previous: seen, current: keys))
            seen = keys
            let messages = rows.filter { fresh.contains($0.joined(separator: " | ")) }
                .compactMap(chatMessage(fromParts:)).filter { !isOwnMessage($0) }
            guard !messages.isEmpty else { return }
            let text = messages.count > 3
                ? String(localized: "\(messages.count) new chat messages. Last one, \(messages.last!.spoken)")
                : messages.map(\.spoken).joined(separator: ". ")
            return say(text, tone: .beep)
        }
        // No chat list yet (the chat may be closed): look again every 15 seconds at most.
        watched = nil
        guard Date().timeIntervalSince(lastSearch) > 15 else { return }
        lastSearch = Date()
        guard let meeting = locate(watchRanking), let list = chatList(for: meeting) else { return }
        watched = (meeting.pid, list)
        seen = chatRows(list).map { $0.joined(separator: " | ") }
    }
}
