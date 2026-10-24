// Commands.swift — every keyboard command, its default key, and the keys a
// command can be moved to (like JAWS Keyboard Manager). Keys are pressed with
// the shortcut modifier (Right Option by default), or on their own after the
// layer key. Digits 1 to 9 stay reserved for presets, slash for layer help.

import AppKit

enum Command: String, CaseIterable, Identifiable, Codable {
    case speechLeft, speechRight, speechLouder, othersLouder, status, menu
    case quiet, playing, appLouder, appQuieter, appMute, device, microphone
    case silence, readItem, history, clipboard, camera, layer
    case describeImage, assistant, analyzeText, research, systemStatus
    case docReader, scanAndRead, captions, focusFrame, audioHub, hubPlayPause
    case rescueVoiceOver, compareText, voiceOverCommands, reportBug
    case readWindow, describeVideo, openDownload, micCheck, colorIdentifier, lightDetector
    case commandPalette, inputHelp, tutorial, translate, audioMouse, beepMode
    case exportSettings, importSettings, diagnostics, performance
    case sensorStatus, customLabel, placeMarker, nextPlaceMarker, doItForMe
    case documentCheck, brailleExport, codeReader, labelReader, moneyReader, practice, typingTrainer, voiceOverLessons
    case listenForCommand, checkForUpdates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speechLeft: String(localized: "Speech left (again: split off)")
        case .speechRight: String(localized: "Speech right (again: split off)")
        case .speechLouder: String(localized: "Speech louder")
        case .othersLouder: String(localized: "Other sounds louder")
        case .status: String(localized: "What's on")
        case .menu: String(localized: "Open the menu")
        case .quiet: String(localized: "Quiet everything but VoiceOver")
        case .playing: String(localized: "What's playing")
        case .appLouder: String(localized: "Front app louder")
        case .appQuieter: String(localized: "Front app quieter")
        case .appMute: String(localized: "Mute front app")
        case .device: String(localized: "Next output device")
        case .microphone: String(localized: "Mute microphone")
        case .silence: String(localized: "Silence VoiceOver")
        case .readItem: String(localized: "Read item under VoiceOver cursor")
        case .history: String(localized: "Speech history")
        case .clipboard: String(localized: "Say clipboard")
        case .camera: String(localized: "Check camera framing")
        case .layer: String(localized: "Layer key")
        case .describeImage: String(localized: "Describe image under VoiceOver cursor")
        case .assistant: String(localized: "Ask the assistant")
        case .analyzeText: String(localized: "Check clipboard text")
        case .research: String(localized: "Research It")
        case .systemStatus: String(localized: "System status")
        case .docReader: String(localized: "Doc Reader")
        case .scanAndRead: String(localized: "Scan and Read")
        case .captions: String(localized: "Large-print captions")
        case .focusFrame: String(localized: "Focus frame")
        case .audioHub: String(localized: "Audio hub")
        case .hubPlayPause: String(localized: "Audio hub play or pause")
        case .rescueVoiceOver: String(localized: "Restart VoiceOver")
        case .compareText: String(localized: "Compare text")
        case .voiceOverCommands: String(localized: "Find a VoiceOver command")
        case .reportBug: String(localized: "Report a bug to Apple")
        case .readWindow: String(localized: "Read the text in the front window")
        case .describeVideo: String(localized: "Describe what's happening in a video")
        case .openDownload: String(localized: "Open the latest download")
        case .micCheck: String(localized: "Microphone check")
        case .colorIdentifier: String(localized: "Identify a color with the camera")
        case .lightDetector: String(localized: "Light detector")
        case .commandPalette: String(localized: "Command palette: search and run any command")
        case .inputHelp: String(localized: "Input help: hear what keys do without doing it")
        case .tutorial: String(localized: "Tutorial")
        case .translate: String(localized: "Translate")
        case .audioMouse: String(localized: "Audio mouse: hear where the pointer is")
        case .beepMode: String(localized: "Beeps while VoiceOver is silenced")
        case .exportSettings: String(localized: "Export settings")
        case .importSettings: String(localized: "Import settings")
        case .diagnostics: String(localized: "Save a diagnostics report")
        case .performance: String(localized: "App performance")
        case .checkForUpdates: String(localized: "Check for updates")
        case .sensorStatus: String(localized: "What's using the camera and microphone")
        case .customLabel: String(localized: "Label the item under the VoiceOver cursor")
        case .placeMarker: String(localized: "Add a place marker on this web page")
        case .nextPlaceMarker: String(localized: "Go to the next place marker")
        case .doItForMe: String(localized: "Do it for me: ask the assistant to find or press something")
        case .documentCheck: String(localized: "Check a document's accessibility")
        case .brailleExport: String(localized: "Save text as braille")
        case .codeReader: String(localized: "Read a barcode or QR code")
        case .labelReader: String(localized: "Read a medicine label")
        case .moneyReader: String(localized: "Identify money")
        case .practice: String(localized: "VoiceOver practice")
        case .typingTrainer: String(localized: "Typing trainer")
        case .voiceOverLessons: String(localized: "VoiceOver lessons: learn VoiceOver from the beginning")
        case .listenForCommand: String(localized: "Listen for a voice command, without saying Audio Split")
        }
    }

    /// The key this command has unless changed in Settings; nil for commands
    /// with no key by default (they're in the menu and the command palette).
    var defaultKey: Int64? {
        switch self {
        case .speechLeft: 123
        case .speechRight: 124
        case .speechLouder: 126
        case .othersLouder: 125
        case .status: 49
        case .menu: 46
        case .quiet: 12
        case .playing: 13
        case .appLouder: 24
        case .appQuieter: 27
        case .appMute: 29
        case .device: 2
        case .microphone: 7
        case .silence: 1
        case .readItem: 15
        case .history: 4
        case .clipboard: 8
        case .camera: 3
        case .layer: 37
        case .describeImage: 34
        case .assistant: 0
        case .analyzeText: 17
        case .research: 5
        case .systemStatus: 11
        case .docReader: 31
        case .scanAndRead: 45
        case .captions: 32
        case .focusFrame: 16
        case .audioHub: 35
        case .hubPlayPause: 38
        case .rescueVoiceOver: 40
        case .compareText: 14
        case .voiceOverCommands: 9
        case .reportBug: 43
        case .readWindow: 6
        case .describeVideo: 33
        case .openDownload: 47
        case .micCheck: 41
        case .colorIdentifier: 30
        case .lightDetector: 42
        case .commandPalette: 36
        case .inputHelp: 50
        case .translate: 39
        case .tutorial, .audioMouse, .beepMode, .exportSettings, .importSettings, .diagnostics, .performance,
             .sensorStatus, .customLabel, .placeMarker, .nextPlaceMarker, .doItForMe, .documentCheck,
             .brailleExport, .codeReader, .labelReader, .moneyReader, .practice, .typingTrainer, .voiceOverLessons, .listenForCommand, .checkForUpdates: nil
        }
    }
}

/// A key a command can use: its virtual key code, spoken name, and menu key equivalent.
struct Key: Identifiable, Hashable {
    let code: Int64
    let name: String
    let equivalent: String
    var id: Int64 { code }

    static let presetDigits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    static let slash: Int64 = 44
    static let escape: Int64 = 53
    /// Stored as a chosen key to mean "no key".
    static let none: Int64 = -1

    /// Keys commands can be assigned to (everything except digits 1 to 9 and slash).
    static let assignable: [Key] = {
        let letters: [(Int64, String)] = [
            (0, "a"), (11, "b"), (8, "c"), (2, "d"), (14, "e"), (3, "f"), (5, "g"), (4, "h"), (34, "i"),
            (38, "j"), (40, "k"), (37, "l"), (46, "m"), (45, "n"), (31, "o"), (35, "p"), (12, "q"), (15, "r"),
            (1, "s"), (17, "t"), (32, "u"), (9, "v"), (13, "w"), (7, "x"), (16, "y"), (6, "z"),
        ]
        func arrow(_ key: Int) -> String { String(Character(UnicodeScalar(key)!)) }
        return letters.map { Key(code: $0.0, name: $0.1.uppercased(), equivalent: $0.1) } + [
            Key(code: 29, name: "0", equivalent: "0"),
            Key(code: 123, name: String(localized: "Left Arrow"), equivalent: arrow(NSLeftArrowFunctionKey)),
            Key(code: 124, name: String(localized: "Right Arrow"), equivalent: arrow(NSRightArrowFunctionKey)),
            Key(code: 126, name: String(localized: "Up Arrow"), equivalent: arrow(NSUpArrowFunctionKey)),
            Key(code: 125, name: String(localized: "Down Arrow"), equivalent: arrow(NSDownArrowFunctionKey)),
            Key(code: 49, name: String(localized: "Space"), equivalent: " "),
            Key(code: 24, name: String(localized: "Equals"), equivalent: "="),
            Key(code: 27, name: String(localized: "Minus"), equivalent: "-"),
            Key(code: 33, name: String(localized: "Left Bracket"), equivalent: "["),
            Key(code: 30, name: String(localized: "Right Bracket"), equivalent: "]"),
            Key(code: 41, name: String(localized: "Semicolon"), equivalent: ";"),
            Key(code: 39, name: String(localized: "Apostrophe"), equivalent: "'"),
            Key(code: 43, name: String(localized: "Comma"), equivalent: ","),
            Key(code: 47, name: String(localized: "Period"), equivalent: "."),
            Key(code: 42, name: String(localized: "Backslash"), equivalent: "\\"),
            Key(code: 50, name: String(localized: "Grave Accent"), equivalent: "`"),
            Key(code: 36, name: String(localized: "Return"), equivalent: "\r"),
        ]
    }()

    static func named(_ code: Int64) -> Key? { assignable.first { $0.code == code } }
}

/// The current key for each command: the default, unless changed in Settings.
enum KeyMap {
    /// Read on the event tap thread; rebuilt on main when the setting changes.
    nonisolated(unsafe) private(set) static var commandForKey: [Int64: Command] = build([:])
    /// Keys of the user's own commands (scripts and shortcuts), on keys no built-in command uses.
    nonisolated(unsafe) private(set) static var userCommandForKey: [Int64: UUID] = [:]

    static func update(custom: [String: Int64], userCommands: [UserCommand] = []) {
        commandForKey = build(custom)
        var users: [Int64: UUID] = [:]
        for command in userCommands {
            if let key = command.key, commandForKey[key] == nil { users[key] = command.id }
        }
        userCommandForKey = users
    }

    /// Keys the user chose always win. A command whose default key is already
    /// taken by a chosen key (for example a default added in a later version)
    /// has no key until one is chosen for it in Settings.
    private static func build(_ custom: [String: Int64]) -> [Int64: Command] {
        var map: [Int64: Command] = [:]
        for command in Command.allCases {
            if let key = custom[command.rawValue], key != Key.none { map[key] = command }
        }
        for command in Command.allCases where custom[command.rawValue] == nil {
            if let key = command.defaultKey, map[key] == nil { map[key] = command }
        }
        return map
    }

    static func key(for command: Command) -> Key? {
        commandForKey.first { $0.value == command }.flatMap { Key.named($0.key) }
    }

    /// Spoken list of commands, for layer help.
    static var spokenList: String {
        Command.allCases.compactMap { command in
            key(for: command).map { "\($0.name): \(command.title)" }
        }.joined(separator: ". ") + ". " + String(localized: "1 to 9: presets. Escape cancels.")
    }
}
