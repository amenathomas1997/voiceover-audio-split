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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speechLeft: "Speech left (again: split off)"
        case .speechRight: "Speech right (again: split off)"
        case .speechLouder: "Speech louder"
        case .othersLouder: "Other sounds louder"
        case .status: "What's on"
        case .menu: "Open the menu"
        case .quiet: "Quiet everything but VoiceOver"
        case .playing: "What's playing"
        case .appLouder: "Front app louder"
        case .appQuieter: "Front app quieter"
        case .appMute: "Mute front app"
        case .device: "Next output device"
        case .microphone: "Mute microphone"
        case .silence: "Silence VoiceOver"
        case .readItem: "Read item under VoiceOver cursor"
        case .history: "Speech history"
        case .clipboard: "Say clipboard"
        case .camera: "Check camera framing"
        case .layer: "Layer key"
        case .describeImage: "Describe image under VoiceOver cursor"
        case .assistant: "Ask the assistant"
        case .analyzeText: "Check clipboard text"
        case .research: "Research It"
        case .systemStatus: "System status"
        case .docReader: "Doc Reader"
        case .scanAndRead: "Scan and Read"
        case .captions: "Large-print captions"
        case .focusFrame: "Focus frame"
        case .audioHub: "Audio hub"
        case .hubPlayPause: "Audio hub play or pause"
        case .rescueVoiceOver: "Restart VoiceOver"
        case .compareText: "Compare text"
        case .voiceOverCommands: "Find a VoiceOver command"
        case .reportBug: "Report a bug to Apple"
        }
    }

    var defaultKey: Int64 {
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
            Key(code: 123, name: "Left Arrow", equivalent: arrow(NSLeftArrowFunctionKey)),
            Key(code: 124, name: "Right Arrow", equivalent: arrow(NSRightArrowFunctionKey)),
            Key(code: 126, name: "Up Arrow", equivalent: arrow(NSUpArrowFunctionKey)),
            Key(code: 125, name: "Down Arrow", equivalent: arrow(NSDownArrowFunctionKey)),
            Key(code: 49, name: "Space", equivalent: " "),
            Key(code: 24, name: "Equals", equivalent: "="),
            Key(code: 27, name: "Minus", equivalent: "-"),
            Key(code: 33, name: "Left Bracket", equivalent: "["),
            Key(code: 30, name: "Right Bracket", equivalent: "]"),
            Key(code: 41, name: "Semicolon", equivalent: ";"),
            Key(code: 39, name: "Apostrophe", equivalent: "'"),
            Key(code: 43, name: "Comma", equivalent: ","),
            Key(code: 47, name: "Period", equivalent: "."),
            Key(code: 42, name: "Backslash", equivalent: "\\"),
            Key(code: 50, name: "Grave Accent", equivalent: "`"),
        ]
    }()

    static func named(_ code: Int64) -> Key? { assignable.first { $0.code == code } }
}

/// The current key for each command: the default, unless changed in Settings.
enum KeyMap {
    /// Read on the event tap thread; rebuilt on main when the setting changes.
    nonisolated(unsafe) private(set) static var commandForKey: [Int64: Command] = build([:])

    static func update(custom: [String: Int64]) {
        commandForKey = build(custom)
    }

    /// Keys the user chose always win. A command whose default key is already
    /// taken by a chosen key (for example a default added in a later version)
    /// has no key until one is chosen for it in Settings.
    private static func build(_ custom: [String: Int64]) -> [Int64: Command] {
        var map: [Int64: Command] = [:]
        for command in Command.allCases {
            if let key = custom[command.rawValue] { map[key] = command }
        }
        for command in Command.allCases where custom[command.rawValue] == nil && map[command.defaultKey] == nil {
            map[command.defaultKey] = command
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
        }.joined(separator: ". ") + ". 1 to 9: presets. Escape cancels."
    }
}
