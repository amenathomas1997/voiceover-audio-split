// AppDelegate.swift — VoiceOver Audio Split runs as a menu bar app with no
// Dock icon. Its menu (VoiceOver: VO-M twice for menu extras) mirrors the
// keyboard shortcuts and opens the Settings and Setup Guide windows.

import AppKit
import CoreAudio
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = Controller.shared
    private let preferences = Preferences.shared
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var assistantWindow: NSWindow?
    private var researchWindow: NSWindow?
    private var docReaderWindow: NSWindow?
    private var scanWindow: NSWindow?
    private var audioHubWindow: NSWindow?
    private var compareWindow: NSWindow?
    private var textCheckerWindow: NSWindow?
    private var commandsWindow: NSWindow?
    private var bugReportWindow: NSWindow?
    private var paletteWindow: NSWindow?
    private var tutorialWindow: NSWindow?
    private var translateWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under unit tests the app only hosts the test bundle: no menu, audio or shortcuts.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        if CommandLine.arguments.contains("--check-online") { return checkOnline() }
        #endif
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "VoiceOver Audio Split")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.restore()
        Hotkeys.start()
        if !preferences.finishedSetup { showSetupGuide() }
        #if DEBUG
        if CommandLine.arguments.contains("--self-test") { selfTest() }
        #endif
    }

    #if DEBUG
    /// Development builds only: checks text recognition and the online services
    /// without starting shortcuts, audio capture or VoiceOver scripting (so no
    /// permission prompts), logs the results, and quits.
    /// Run with: open -a <app> --args --check-online
    private func checkOnline() {
        Task { @MainActor in
            let image = NSImage(size: NSSize(width: 900, height: 200), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                ("Scan and Read works on this Mac" as NSString).draw(
                    at: NSPoint(x: 40, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
                return true
            }
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            log("Check: OCR = \(TextRecognition.text(in: cgImage))")
            log("Check: Downloads folder readable = \(SystemEvents.latestDownload() != nil)")
            log("Check: scripts folder = \(UserCommands.scriptsFolder?.lastPathComponent ?? "unavailable")")
            log("Check: \(Performance.summary())")
            let report = Diagnostics.report()
            log("Check: diagnostics report \(report.count) characters, log included = \(report.contains("Check: OCR"))")
            let hub = AudioHub.shared
            for (query, source) in [("jazz", HubSource.radio), ("accessibility", .podcasts), ("pride", .audiobooks), ("", .news)] {
                let found = (try? await hub.find(query, in: source)) ?? []
                log("Check: \(source.title) = \(found.count) results, first: \(found.first?.title ?? "none")")
                if source == .audiobooks, case .feed(let url)? = found.first?.kind,
                   let data = try? await URLSession.shared.data(from: url).0 {
                    log("Check: first audiobook chapters = \(RSSFeed.parse(data).filter { $0.audio != nil }.count)")
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Development builds only: tries the Mac-wide controls inside the sandbox
    /// and puts everything back. Run with: open -a <app> --args --self-test
    private func selfTest() {
        log("Self-test: playing = \(AudioSystem.appsPlaying())")
        log("Self-test: output devices = \(outputDevices().map(\.name))")
        // Lengths and counts only: never log what was copied or spoken.
        log("Self-test: clipboard description length = \(Clipboard.describe().count)")
        DispatchQueue.global().async {
            log("Self-test: item under VoiceOver cursor length = \(VoiceOverText.itemUnderCursor()?.count ?? -1)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            log("Self-test: speech history phrases = \(SpeechHistory.shared.phrases.count)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            log("Self-test: system status parts = \(SystemStatus.summary().components(separatedBy: ". ").count)")
        }
        log("Self-test: text analyzer = \(TextAnalyzer.analyze("This  is is a test (with a problem .\nSecond line "))")
        log("Self-test: command keys = \(KeyMap.commandForKey.count) of \(Command.allCases.count)")
        Task {
            for (query, source) in [("accessibility", ResearchSource.definition), ("VoiceOver", .wikipedia), ("Chicago", .weather)] {
                let answer = await Research.lookUp(query, in: source)
                log("Self-test: \(source.title) = \(answer.prefix(70))")
            }
        }
        let original = defaultOutputDevice()
        let picked = AudioSystem.nextOutputDevice()
        log("Self-test: next output = \(picked ?? "failed")")
        // Check the choice survives automatic switching, then put everything back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let held = outputDevices().first { $0.id == defaultOutputDevice() }?.name
            log("Self-test: output after 5 seconds = \(held ?? "unknown") (held: \(held == picked))")
            AudioSystem.releaseHold()
            AudioSystem.setDefaultOutput(original)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                log("Self-test: output restored = \(defaultOutputDevice() == original)")
            }
        }
        let wasMuted = AudioSystem.isMicMuted
        log("Self-test: mic toggle = \(AudioSystem.toggleMicrophone()), muted now = \(AudioSystem.isMicMuted)")
        if AudioSystem.isMicMuted != wasMuted { _ = AudioSystem.toggleMicrophone() }
        log("Self-test: mic restored = \(AudioSystem.isMicMuted == wasMuted)")
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier else { continue }
            let matched = audioProcesses().filter { belongs($0, to: id, appPIDs: pids(of: id)) }.map(\.bundleID)
            if !matched.isEmpty { log("Self-test: \(id) audio comes from \(matched)") }
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        controller.stopForQuit()
    }

    /// Opening the app again (Spotlight, Finder, Launchpad) shows Settings. This
    /// matters when the menu bar is full and macOS hides the menu bar item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Shows the app's menu where the pointer is, for the menu shortcut. Works
    /// even when the menu bar item is hidden behind the notch or a full menu bar.
    func popUpMenu() {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        NSApp.activate()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Windows

    private func showSettings() {
        settingsWindow = show(settingsWindow, title: "VoiceOver Audio Split Settings", view: SettingsView())
    }

    /// Opens the assistant. To describe an image, the picture is taken first and
    /// the model opens the window afterwards, so VoiceOver's cursor stays on the image.
    func showAssistant(describingImage: Bool) {
        let model = AssistantModel.shared
        model.showWindow = { [weak self] in
            guard let self else { return }
            self.assistantWindow = self.show(self.assistantWindow, title: "Assistant", view: AssistantView())
        }
        if describingImage { model.describeImage() } else { model.showWindow?() }
    }

    func showDocReader() {
        docReaderWindow = show(docReaderWindow, title: "Doc Reader", view: DocReaderView())
        docReaderWindow?.styleMask.insert(.resizable)
    }

    func showScan() {
        scanWindow = show(scanWindow, title: "Scan and Read", view: ScanView())
    }

    func showAudioHub() {
        audioHubWindow = show(audioHubWindow, title: "Audio Hub", view: AudioHubView())
    }

    func showPalette() {
        paletteWindow = show(paletteWindow, title: "Command Palette", view: CommandPaletteView { [weak self] in
            self?.paletteWindow?.close()
            // Give the keyboard back to the app that was in front.
            NSApp.hide(nil)
        })
    }

    func showTutorial() {
        tutorialWindow = show(tutorialWindow, title: "Tutorial", view: TutorialView())
    }

    func showTranslate() {
        translateWindow = show(translateWindow, title: "Translate", view: TranslateView())
    }

    func showCompare() {
        compareWindow = show(compareWindow, title: "Compare Text", view: CompareView())
    }

    func showTextChecker() {
        textCheckerWindow = show(textCheckerWindow, title: "Text Checker", view: TextCheckerView())
    }

    func showVoiceOverCommands() {
        commandsWindow = show(commandsWindow, title: "VoiceOver Commands", view: VoiceOverCommandsView())
    }

    func showBugReport() {
        bugReportWindow = show(bugReportWindow, title: "Report a Bug to Apple", view: BugReportView())
    }

    func showResearch() {
        researchWindow = show(researchWindow, title: "Research It", view: ResearchView())
    }

    func showHistory() {
        historyWindow = show(historyWindow, title: "Speech History", view: HistoryView())
    }

    private func showSetupGuide() {
        setupWindow = show(setupWindow, title: "Set Up VoiceOver Audio Split", view: SetupGuideView { [weak self] in
            self?.preferences.finishedSetup = true
            self?.setupWindow?.close()
        })
    }

    /// Brings an existing window forward, or creates it. Menu bar apps must
    /// activate themselves for a window to take keyboard focus.
    private func show(_ existing: NSWindow?, title: String, view: some View) -> NSWindow {
        let window = existing ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    // MARK: - Menu (rebuilt each time it opens so checkmarks are current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let side = controller.activeSide

        // Split
        let status = NSMenuItem(title: controller.describeSplit(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        add(to: menu, "Speech Left", command: .speechLeft, checked: side == .left) { $0.setSide(.left) }
        add(to: menu, "Speech Right", command: .speechRight, checked: side == .right) { $0.setSide(.right) }
        add(to: menu, "Audio Split Off", checked: side == nil) { $0.setSide(nil) }
        add(to: menu, "What's On", command: .status) { $0.announceStatus() }
        let layoutMenu = submenu(in: menu, "Layout")
        for layout in Layout.allCases {
            add(to: layoutMenu, layout.title, checked: preferences.layout == layout) { [preferences] controller in
                preferences.layout = layout
                DispatchQueue.main.async { controller.announceStatus() }
            }
        }
        menu.addItem(.separator())

        // Volume
        let balance = NSMenuItem(title: Controller.describe(balance: controller.balance), action: nil, keyEquivalent: "")
        balance.isEnabled = false
        menu.addItem(balance)
        add(to: menu, "Speech Louder", command: .speechLouder) { [preferences] in
            $0.changeBalance(by: preferences.balanceStep)
        }
        add(to: menu, "Other Sounds Louder", command: .othersLouder) { [preferences] in
            $0.changeBalance(by: -preferences.balanceStep)
        }
        add(to: menu, "Reset Volume Balance") { $0.resetBalance() }
        add(to: menu, "Quiet Everything But VoiceOver", command: .quiet, checked: controller.quietAll) { $0.toggleQuiet() }
        add(to: menu, "Lower Other Sounds While VoiceOver Speaks", checked: preferences.ducking) { [preferences] _ in
            preferences.ducking.toggle()
            Announcer.say(preferences.ducking ? "Other sounds lower while VoiceOver speaks" : "Other sounds stay at the same volume")
        }
        menu.addItem(.separator())

        // Apps
        let appName = controller.frontAppName ?? "Front App"
        add(to: menu, "\(appName) Louder", command: .appLouder) { $0.changeFrontAppVolume(by: 3) }
        add(to: menu, "\(appName) Quieter", command: .appQuieter) { $0.changeFrontAppVolume(by: -3) }
        add(to: menu, "Mute \(appName)", command: .appMute, checked: controller.frontAppMuted) { $0.toggleFrontAppMute() }
        add(to: menu, "What's Playing", command: .playing) { $0.announcePlaying() }
        menu.addItem(.separator())

        // Speech on demand and VoiceOver tools
        add(to: menu, "Silence VoiceOver", command: .silence, checked: controller.speechSilenced) { $0.toggleSilence() }
        add(to: menu, "Read Item Under VoiceOver Cursor", command: .readItem) { $0.readItem() }
        add(to: menu, "Speech History…", command: .history) { [weak self] _ in self?.showHistory() }
        add(to: menu, "Say Clipboard", command: .clipboard) { $0.sayClipboard() }
        add(to: menu, "Check Camera Framing", command: .camera) { $0.checkCamera() }
        menu.addItem(.separator())

        // Help and research
        add(to: menu, "Describe Image Under VoiceOver Cursor", command: .describeImage) { $0.run(.describeImage) }
        add(to: menu, "Ask the Assistant…", command: .assistant) { $0.run(.assistant) }
        add(to: menu, "Check Clipboard Text…", command: .analyzeText) { $0.analyzeClipboard() }
        add(to: menu, CompareModel.shared.original == nil ? "Compare Text: Save Original" : "Compare Text: Compare With Clipboard",
            command: .compareText) { $0.run(.compareText) }
        add(to: menu, "Research It…", command: .research) { $0.run(.research) }
        add(to: menu, "System Status", command: .systemStatus) { $0.announceSystemStatus() }
        menu.addItem(.separator())

        // VoiceOver help
        add(to: menu, "Restart VoiceOver", command: .rescueVoiceOver) { $0.run(.rescueVoiceOver) }
        add(to: menu, "Keep Audio Awake (Prevents Clipped Words)", checked: preferences.keepAudioAwake) { [preferences] _ in
            preferences.keepAudioAwake.toggle()
            Announcer.say(preferences.keepAudioAwake ? "Keeping audio awake" : "Audio can sleep")
        }
        add(to: menu, "Find a VoiceOver Command…", command: .voiceOverCommands) { $0.run(.voiceOverCommands) }
        add(to: menu, "Report a Bug to Apple…", command: .reportBug) { $0.run(.reportBug) }
        menu.addItem(.separator())

        // Finding and learning commands
        add(to: menu, "Command Palette…", command: .commandPalette) { $0.run(.commandPalette) }
        add(to: menu, "Input Help", command: .inputHelp, checked: InputHelp.isOn) { $0.run(.inputHelp) }
        add(to: menu, "Tutorial…", command: .tutorial) { $0.run(.tutorial) }
        add(to: menu, "Translate…", command: .translate) { $0.run(.translate) }
        add(to: menu, "Audio Mouse", command: .audioMouse, checked: AudioMouse.isOn) { $0.run(.audioMouse) }
        add(to: menu, "Beeps While VoiceOver Is Silenced", command: .beepMode, checked: preferences.beepsWhenSilenced) {
            $0.run(.beepMode)
        }
        if !preferences.userCommands.isEmpty {
            let yours = submenu(in: menu, "Your Commands")
            for command in preferences.userCommands {
                add(to: yours, command.name, equivalent: command.key.flatMap(Key.named)?.equivalent) { _ in
                    UserCommands.run(command.id)
                }
            }
        }
        menu.addItem(.separator())

        // Screen, meetings and everyday tools
        add(to: menu, "Read Text in Front Window", command: .readWindow) { $0.run(.readWindow) }
        add(to: menu, "Open Last Window Text in Doc Reader") { _ in ScreenText.openInDocReader() }
        add(to: menu, "Describe What's Happening in Video", command: .describeVideo) { $0.run(.describeVideo) }
        add(to: menu, "Microphone Check", command: .micCheck) { $0.run(.micCheck) }
        add(to: menu, "Open Latest Download", command: .openDownload) { $0.run(.openDownload) }
        add(to: menu, "Identify a Color", command: .colorIdentifier) { $0.run(.colorIdentifier) }
        add(to: menu, "Light Detector", command: .lightDetector, checked: LightDetector.isRunning) { $0.run(.lightDetector) }
        menu.addItem(.separator())

        // Reading, low vision and listening
        add(to: menu, "Doc Reader…", command: .docReader) { $0.run(.docReader) }
        add(to: menu, "Scan and Read…", command: .scanAndRead) { $0.run(.scanAndRead) }
        add(to: menu, "Large-Print Captions", command: .captions, checked: Captions.isShowing) { $0.toggleCaptions() }
        add(to: menu, "Focus Frame", command: .focusFrame, checked: FocusFrame.isShowing) { $0.toggleFocusFrame() }
        add(to: menu, "Audio Hub…", command: .audioHub) { $0.run(.audioHub) }
        if let title = AudioHub.shared.nowPlaying {
            add(to: menu, AudioHub.shared.playing ? "Pause \(title)" : "Play \(title)", command: .hubPlayPause) {
                _ in AudioHub.shared.togglePlay()
            }
        }
        menu.addItem(.separator())

        // Devices
        add(to: menu, "Next Output Device", command: .device) { $0.nextOutputDevice() }
        add(to: menu, "Mute Microphone", command: .microphone, checked: AudioSystem.isMicMuted) { $0.toggleMicrophone() }
        menu.addItem(.separator())

        // Presets, hearing and clarity
        let presetsMenu = submenu(in: menu, "Presets")
        for (index, preset) in preferences.presets.enumerated() {
            add(to: presetsMenu, preset.name, equivalent: index < 9 ? "\(index + 1)" : nil) { $0.applyPreset(preset) }
        }
        if !preferences.presets.isEmpty { presetsMenu.addItem(.separator()) }
        add(to: presetsMenu, "Save or Edit Presets in Settings…") { [weak self] _ in self?.showSettings() }

        let hearingMenu = submenu(in: menu, "Hearing and Clarity")
        toggle(in: hearingMenu, "Speech Clarity Boost", \.clarity, on: "Speech clarity on", off: "Speech clarity off")
        toggle(in: hearingMenu, "Even Out Loud Media", \.leveler, on: "Loud media evened out", off: "Media leveling off")
        toggle(in: hearingMenu, "Volume Limit", \.volumeLimit, on: "Volume limit on", off: "Volume limit off")
        hearingMenu.addItem(.separator())
        for choice in OneEar.allCases {
            add(to: hearingMenu, choice == .off ? "Normal Stereo" : choice.title, checked: preferences.oneEar == choice) {
                [preferences] _ in
                preferences.oneEar = choice
                Announcer.say(choice == .off ? "Normal stereo" : choice.title)
            }
        }
        menu.addItem(.separator())

        // App
        add(to: menu, "Start at Login", checked: controller.startsAtLogin) { $0.toggleStartAtLogin() }
        if !Hotkeys.isTrusted {
            add(to: menu, "Allow Keyboard Shortcuts…") { _ in
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        let backup = submenu(in: menu, "Backup and Diagnostics")
        add(to: backup, "Export Settings…", command: .exportSettings) { $0.run(.exportSettings) }
        add(to: backup, "Import Settings…", command: .importSettings) { $0.run(.importSettings) }
        add(to: backup, "Save a Diagnostics Report…", command: .diagnostics) { $0.run(.diagnostics) }
        add(to: backup, "App Performance", command: .performance) { $0.run(.performance) }
        add(to: menu, "Settings…") { [weak self] _ in self?.showSettings() }
        add(to: menu, "Setup Guide…") { [weak self] _ in self?.showSetupGuide() }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceOver Audio Split", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    private func submenu(in menu: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    /// A checkmark item for an on/off setting, announcing the new state.
    private func toggle(in menu: NSMenu, _ title: String, _ setting: ReferenceWritableKeyPath<Preferences, Bool>,
                        on: String, off: String) {
        add(to: menu, title, checked: preferences[keyPath: setting]) { [preferences] _ in
            preferences[keyPath: setting].toggle()
            Announcer.say(preferences[keyPath: setting] ? on : off)
        }
    }

    /// Adds an item; a command shows its current shortcut (chosen modifier + key) beside it.
    private func add(to menu: NSMenu, _ title: String, command: Command? = nil, equivalent: String? = nil,
                     checked: Bool = false, action: @escaping (Controller) -> Void) {
        let item = ClosureMenuItem(title: title) { [controller] in action(controller) }
        item.state = checked ? .on : .off
        if let key = equivalent ?? command.flatMap({ KeyMap.key(for: $0)?.equivalent }) {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = switch preferences.modifier {
            case .option: .option
            case .command: .command
            case .control: .control
            case .shift: .shift
            }
        }
        menu.addItem(item)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
