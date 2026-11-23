// AppActions.swift — the app's commands as actions for Siri, the Shortcuts app and
// Spotlight (App Intents). "Hey Siri, speech left with VoiceOver Audio Split" works without
// this app listening to the microphone: Siri hears it and hands the command over. The same
// actions can be put in a shortcut, on a keyboard shortcut of your own, or in an automation.

import AppIntents

/// The commands offered to Siri and Shortcuts: the ones that make sense by voice or in an
/// automation. Each goes to a state (speech left, sound back) rather than toggling, so a
/// shortcut does the same thing however it finds the app.
enum SplitAction: String, AppEnum {
    case speechLeft, speechRight, splitOff, quietEverything, soundBack, whatsOn
    case speechLouder, otherSoundsLouder, toggleMicrophone, whatsPlaying
    case systemStatus, resourceMonitor, whatsNext, watchWindow

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Command"

    static let caseDisplayRepresentations: [SplitAction: DisplayRepresentation] = [
        .speechLeft: "Speech left",
        .speechRight: "Speech right",
        .splitOff: "Split off",
        .quietEverything: "Quiet everything",
        .soundBack: "Sound back",
        .whatsOn: "What's on",
        .speechLouder: "Speech louder",
        .otherSoundsLouder: "Other sounds louder",
        .toggleMicrophone: "Mute or unmute the microphone",
        .whatsPlaying: "What's playing",
        .systemStatus: "System status",
        .resourceMonitor: "Resource monitor",
        .whatsNext: "What's next on my calendar",
        .watchWindow: "Watch the front window",
    ]

    /// Does it, on the main thread. The app says the result itself, in VoiceOver's voice,
    /// as it does for the same command from a key.
    @MainActor
    func run() {
        let controller = Controller.shared
        switch self {
        case .speechLeft: controller.setSide(.left)
        case .speechRight: controller.setSide(.right)
        case .splitOff: controller.setSide(nil)
        case .quietEverything: if !controller.quietAll { controller.toggleQuiet() }
        case .soundBack: if controller.quietAll { controller.toggleQuiet() }
        case .whatsOn: controller.run(.status)
        case .speechLouder: controller.run(.speechLouder)
        case .otherSoundsLouder: controller.run(.othersLouder)
        case .toggleMicrophone: controller.run(.microphone)
        case .whatsPlaying: controller.run(.playing)
        case .systemStatus: controller.run(.systemStatus)
        case .resourceMonitor: controller.run(.resourceMonitor)
        case .whatsNext: controller.run(.whatsNext)
        case .watchWindow: controller.run(.watchWindow)
        }
    }
}

struct RunSplitCommand: AppIntent {
    static let title: LocalizedStringResource = "Run a VoiceOver Audio Split Command"
    static let description = IntentDescription("Moves VoiceOver's speech to one ear, quiets everything else, or runs another VoiceOver Audio Split command. The app says the result.")
    /// The app is already running in the menu bar; nothing needs to come to the front.
    static let openAppWhenRun = false

    @Parameter(title: "Command")
    var command: SplitAction

    @MainActor
    func perform() async throws -> some IntentResult {
        command.run()
        return .result()
    }
}

struct AudioSplitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunSplitCommand(),
                    phrases: ["\(\.$command) with \(.applicationName)",
                              "\(.applicationName) \(\.$command)"],
                    shortTitle: "Run a Command",
                    systemImageName: "headphones")
    }
}
