// AppDelegate.swift — VoiceOver Audio Split runs as a menu bar app with no
// Dock icon. Its menu (VoiceOver: VO-M twice for menu extras) mirrors the
// keyboard shortcuts and opens the Settings and Setup Guide windows.

import AppKit
import CoreAudio
import Speech
import SwiftUI
import WebKit

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
    private var labelWindow: NSWindow?
    private var doItWindow: NSWindow?
    private var documentCheckWindow: NSWindow?
    private var brailleWindow: NSWindow?
    private var hearingWindow: NSWindow?
    private var remindersWindow: NSWindow?
    private var clipboardWindow: NSWindow?
    private var switcherWindow: NSWindow?
    private var objectFinderWindow: NSWindow?
    private var practiceWindow: NSWindow?
    private var typingWindow: NSWindow?
    private var lessonsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// A menu-bar app shows no menu bar, but Command C, V, X, A and Z in text fields
    /// still need an Edit menu to reach them.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let edit = NSMenu(title: String(localized: "Edit"))
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            (String(localized: "Undo"), Selector(("undo:")), "z", .command),
            (String(localized: "Redo"), Selector(("redo:")), "z", [.command, .shift]),
            (String(localized: "Cut"), #selector(NSText.cut(_:)), "x", .command),
            (String(localized: "Copy"), #selector(NSText.copy(_:)), "c", .command),
            (String(localized: "Paste"), #selector(NSText.paste(_:)), "v", .command),
            (String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, modifiers) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        let editItem = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(NSMenuItem()) // The app menu's place.
        main.addItem(editItem)
        return main
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under unit tests the app only hosts the test bundle: no menu, audio or shortcuts.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        if CommandLine.arguments.contains("--check-online") { return checkOnline() }
        // Run with VOAS_CAPTION_PIDS set to a process playing speech: logs the captions it hears.
        if CommandLine.arguments.contains("--check-captions") {
            CallCaptions.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                log("Check: captions = \((CallCaptions.shared.lines + [CallCaptions.shared.partial]).joined(separator: " | "))")
                CallCaptions.shared.stop()
            }
            return
        }
        #endif
        NSApp.mainMenu = Self.editMenu()
        connectAssistant()
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
        Updater.shared.startAutomaticChecks()
        Reminders.shared.start()
        MeetingHelpers.start()
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
                (String(localized: "Scan and Read works on this Mac") as NSString).draw(
                    at: NSPoint(x: 40, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
                return true
            }
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            log("Check: OCR = \(TextRecognition.text(in: cgImage))")
            log("Check: Downloads folder readable = \(SystemEvents.latestDownload() != nil)")
            log("Check: scripts folder = \(UserCommands.scriptsFolder?.lastPathComponent ?? "unavailable")")
            log("Check: \(Performance.summary())")
            // Packages named vocheck-*.pkg in Downloads are copied to the temporary Update folder
            // and checked there, the way a downloaded update is.
            let updates = FileManager.default.temporaryDirectory.appendingPathComponent("Update")
            try? FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
            if let downloads = SystemEvents.downloadsFolder {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
                where name.hasPrefix("vocheck-") && name.hasSuffix(".pkg") {
                    try? FileManager.default.removeItem(at: updates.appendingPathComponent(name))
                    try? FileManager.default.copyItem(at: downloads.appendingPathComponent(name), to: updates.appendingPathComponent(name))
                }
            }
            for package in (try? FileManager.default.contentsOfDirectory(at: updates, includingPropertiesForKeys: nil)) ?? []
            where package.pathExtension == "pkg" {
                let report = UpdateCheck.signatureReport(of: package)
                log("Check: update \(package.lastPathComponent) report = \(report != nil), trusted = \(report.map(UpdateCheck.isTrusted) ?? false)")
            }
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            web.loadHTMLString(PracticeWebPage.html, baseURL: nil)
            for _ in 0..<40 where web.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(300))
            let headings = (try? await web.evaluateJavaScript("document.querySelectorAll('h1,h2').length")) as? Int
            log("Check: practice web page headings = \(headings ?? -1)")
            log("Check: voice command on-device = \(SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false), built-in microphone = \(VoiceCommand.builtInMicrophone() != nil)")
            log("Check: permissions = \(Permission.allCases.map { "\($0.rawValue) \($0.status())" }.joined(separator: ", "))")
            log("Check: camera in use = \(SensorWatch.cameraInUse()), microphone apps = \(SensorWatch.appsUsingMicrophone().count)")
            if let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/3017620422003.json?fields=product_name,brands,quantity"),
               let data = try? await URLSession.shared.data(from: url).0,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                log("Check: product lookup = \(CodeReader.productDescription(json["product"] as? [String: Any]) ?? "not found")")
            }
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
        settingsWindow = show(settingsWindow, title: String(localized: "VoiceOver Audio Split Settings"), view: SettingsView())
    }

    /// Opens the assistant. To describe an image, the picture is taken first and
    /// the model opens the window afterwards, so VoiceOver's cursor stays on the image.
    func showAssistant(describingImage: Bool) {
        let model = AssistantModel.shared
        connectAssistant()
        if describingImage { model.describeImage() } else { model.showWindow?() }
    }

    /// Lets the assistant open its window, also when it's started by a shortcut (describe video).
    private func connectAssistant() {
        AssistantModel.shared.showWindow = { [weak self] in
            guard let self else { return }
            self.assistantWindow = self.show(self.assistantWindow, title: String(localized: "Assistant"), view: AssistantView())
        }
    }

    func showDocReader() {
        docReaderWindow = show(docReaderWindow, title: String(localized: "Doc Reader"), view: DocReaderView())
        docReaderWindow?.styleMask.insert(.resizable)
    }

    func showScan() {
        scanWindow = show(scanWindow, title: String(localized: "Scan and Read"), view: ScanView())
    }

    func showAudioHub() {
        audioHubWindow = show(audioHubWindow, title: String(localized: "Audio Hub"), view: AudioHubView())
    }

    func showPalette() {
        paletteWindow = show(paletteWindow, title: String(localized: "Command Palette"), view: CommandPaletteView { [weak self] in
            self?.paletteWindow?.close()
            // Give the keyboard back to the app that was in front.
            NSApp.hide(nil)
        })
    }

    func showTutorial() {
        tutorialWindow = show(tutorialWindow, title: String(localized: "Tutorial"), view: TutorialView())
    }

    func showTranslate() {
        translateWindow = show(translateWindow, title: String(localized: "Translate"), view: TranslateView())
    }

    /// Notes the control under the VoiceOver cursor before the window takes focus.
    func showLabelEditor() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let captured = CustomLabels.capture()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let editor = LabelEditor.shared
                editor.pending = captured?.signature
                editor.spoken = captured?.spoken ?? ""
                editor.text = ""
                self.labelWindow = self.show(self.labelWindow, title: String(localized: "Custom Labels"),
                                             view: LabelEditorView { [weak self] in
                                                 self?.labelWindow?.close()
                                                 NSApp.hide(nil)
                                             })
            }
        }
    }

    func showDoItForMe() {
        // Act on the last app used, never this one (the palette or Settings may be in front).
        DoItModel.shared.target = controller.lastUsedApp
        doItWindow = show(doItWindow, title: String(localized: "Do It for Me"), view: DoItForMeView())
    }

    func showDocumentCheck() {
        documentCheckWindow = show(documentCheckWindow, title: String(localized: "Document Accessibility Check"), view: DocumentCheckView())
    }

    func showReminders() {
        remindersWindow = show(remindersWindow, title: String(localized: "Timers and Reminders"), view: RemindersView())
    }

    func showClipboardHistory() {
        clipboardWindow = show(clipboardWindow, title: String(localized: "Clipboard History"), view: ClipboardHistoryView())
    }

    func showWindowSwitcher() {
        switcherWindow = show(switcherWindow, title: String(localized: "Switch to a Window"), view: WindowSwitcherView { [weak self] in
            self?.switcherWindow?.close()
            NSApp.hide(nil)
        })
    }

    func showObjectFinder() {
        objectFinderWindow = show(objectFinderWindow, title: String(localized: "Find an Object"), view: ObjectFinderView())
    }

    /// Leaving a meeting asks first, by voice when voice commands are listening, or in a dialog.
    @MainActor
    func confirmLeaveMeeting() {
        let question = MeetingHelpers.leaveNeedsConfirmation
        if VoiceCommand.shared.isListening {
            return VoiceCommand.shared.askYesNo(question) { MeetingHelpers.leave(confirmed: true) }
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: String(localized: "Leave"))
        alert.addButton(withTitle: String(localized: "Stay"))
        if alert.runModal() == .alertFirstButtonReturn { MeetingHelpers.leave(confirmed: true) }
    }

    func showHearingProfile() {
        hearingWindow = show(hearingWindow, title: String(localized: "Hearing Profile"), view: HearingProfileView())
    }

    func showBraille() {
        brailleWindow = show(brailleWindow, title: String(localized: "Save as Braille"), view: BrailleView())
    }

    func showPractice() {
        let isNew = practiceWindow == nil
        practiceWindow = show(practiceWindow, title: String(localized: "VoiceOver Practice"), view: PracticeView())
        PracticeModel.shared.window = practiceWindow
        if isNew, let practiceWindow { whenClosed(practiceWindow) { PracticeModel.shared.stop() } }
    }

    func showLessons() {
        let isNew = lessonsWindow == nil
        lessonsWindow = show(lessonsWindow, title: String(localized: "VoiceOver Lessons"), view: LessonsView())
        LessonRunner.shared.window = lessonsWindow
        if isNew, let lessonsWindow { whenClosed(lessonsWindow) { LessonRunner.shared.stop() } }
        // Spoken welcome: on your own or with a trainer, then the next lesson.
        LessonRunner.shared.welcome()
    }

    func showTypingTrainer() {
        let isNew = typingWindow == nil
        typingWindow = show(typingWindow, title: String(localized: "Typing Trainer"), view: TypingTrainerView())
        TypingTrainer.shared.window = typingWindow
        if isNew, let typingWindow { whenClosed(typingWindow) { TypingTrainer.shared.stop() } }
    }

    /// Practice and the trainer take keys while they run; closing their window must
    /// always give the keys back. (SwiftUI's onDisappear doesn't fire for a closed window
    /// that is kept for reuse.)
    private func whenClosed(_ window: NSWindow, _ action: @escaping () -> Void) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            action()
        }
    }

    func showCompare() {
        compareWindow = show(compareWindow, title: String(localized: "Compare Text"), view: CompareView())
    }

    func showTextChecker() {
        textCheckerWindow = show(textCheckerWindow, title: String(localized: "Text Checker"), view: TextCheckerView())
    }

    func showVoiceOverCommands() {
        commandsWindow = show(commandsWindow, title: String(localized: "VoiceOver Commands"), view: VoiceOverCommandsView())
    }

    func showBugReport() {
        bugReportWindow = show(bugReportWindow, title: String(localized: "Report a Bug to Apple"), view: BugReportView())
    }

    func showResearch() {
        researchWindow = show(researchWindow, title: String(localized: "Research It"), view: ResearchView())
    }

    func showHistory() {
        historyWindow = show(historyWindow, title: String(localized: "Speech History"), view: HistoryView())
    }

    func showSetupGuide() {
        setupWindow = show(setupWindow, title: String(localized: "Set Up VoiceOver Audio Split"), view: SetupGuideView { [weak self] in
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

        // The split, at the top: what's used most. Everything else is grouped in submenus
        // (VoiceOver: Right Arrow opens a submenu, Left Arrow closes it).
        let status = NSMenuItem(title: controller.describeSplit(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        add(to: menu, String(localized: "Speech Left"), command: .speechLeft, checked: side == .left) { $0.setSide(.left) }
        add(to: menu, String(localized: "Speech Right"), command: .speechRight, checked: side == .right) { $0.setSide(.right) }
        add(to: menu, String(localized: "Audio Split Off"), checked: side == nil) { $0.setSide(nil) }
        add(to: menu, String(localized: "What's On"), command: .status) { $0.announceStatus() }
        let balance = NSMenuItem(title: Controller.describe(balance: controller.balance), action: nil, keyEquivalent: "")
        balance.isEnabled = false
        menu.addItem(balance)
        add(to: menu, String(localized: "Speech Louder"), command: .speechLouder) { [preferences] in
            $0.changeBalance(by: preferences.balanceStep)
        }
        add(to: menu, String(localized: "Other Sounds Louder"), command: .othersLouder) { [preferences] in
            $0.changeBalance(by: -preferences.balanceStep)
        }
        add(to: menu, String(localized: "Quiet Everything But VoiceOver"), command: .quiet, checked: controller.quietAll) { $0.toggleQuiet() }
        add(to: menu, String(localized: "Command Palette…"), command: .commandPalette) { $0.run(.commandPalette) }
        menu.addItem(.separator())

        // Sound and devices
        let sound = submenu(in: menu, String(localized: "Sound and Devices"))
        let layoutMenu = submenu(in: sound, String(localized: "Layout"))
        for layout in Layout.allCases {
            add(to: layoutMenu, layout.title, checked: preferences.layout == layout) { [preferences] controller in
                preferences.layout = layout
                DispatchQueue.main.async { controller.announceStatus() }
            }
        }
        add(to: sound, String(localized: "Reset Volume Balance")) { $0.resetBalance() }
        add(to: sound, String(localized: "Lower Other Sounds While VoiceOver Speaks"), checked: preferences.ducking) { [preferences] _ in
            preferences.ducking.toggle()
            Announcer.say(preferences.ducking ? String(localized: "Other sounds lower while VoiceOver speaks") : String(localized: "Other sounds stay at the same volume"))
        }
        sound.addItem(.separator())
        let appName = controller.frontAppName ?? String(localized: "Front App")
        add(to: sound, String(localized: "\(appName) Louder"), command: .appLouder) { $0.changeFrontAppVolume(by: 3) }
        add(to: sound, String(localized: "\(appName) Quieter"), command: .appQuieter) { $0.changeFrontAppVolume(by: -3) }
        add(to: sound, String(localized: "Mute \(appName)"), command: .appMute, checked: controller.frontAppMuted) { $0.toggleFrontAppMute() }
        add(to: sound, String(localized: "What's Playing"), command: .playing) { $0.announcePlaying() }
        sound.addItem(.separator())
        add(to: sound, String(localized: "Next Output Device"), command: .device) { $0.nextOutputDevice() }
        add(to: sound, String(localized: "Mute Microphone"), command: .microphone, checked: AudioSystem.isMicMuted) { $0.toggleMicrophone() }
        add(to: sound, String(localized: "Microphone Check"), command: .micCheck) { $0.run(.micCheck) }
        add(to: sound, String(localized: "Camera and Microphone in Use"), command: .sensorStatus) { $0.run(.sensorStatus) }
        sound.addItem(.separator())
        let hearingMenu = submenu(in: sound, String(localized: "Hearing and Clarity"))
        toggle(in: hearingMenu, String(localized: "Speech Clarity Boost"), \.clarity, on: String(localized: "Speech clarity on"), off: String(localized: "Speech clarity off"))
        toggle(in: hearingMenu, String(localized: "Even Out Loud Media"), \.leveler, on: String(localized: "Loud media evened out"), off: String(localized: "Media leveling off"))
        toggle(in: hearingMenu, String(localized: "Volume Limit"), \.volumeLimit, on: String(localized: "Volume limit on"), off: String(localized: "Volume limit off"))
        add(to: hearingMenu, String(localized: "Hearing Profile…"), command: .hearingProfile, checked: preferences.hearingProfileOn) { $0.run(.hearingProfile) }
        hearingMenu.addItem(.separator())
        for choice in OneEar.allCases {
            add(to: hearingMenu, choice == .off ? String(localized: "Normal Stereo") : choice.title, checked: preferences.oneEar == choice) {
                [preferences] _ in
                preferences.oneEar = choice
                Announcer.say(choice == .off ? String(localized: "Normal stereo") : choice.title)
            }
        }
        add(to: sound, String(localized: "Audio Hub…"), command: .audioHub) { $0.run(.audioHub) }
        if let title = AudioHub.shared.nowPlaying {
            add(to: sound, AudioHub.shared.playing ? String(localized: "Pause \(title)") : String(localized: "Play \(title)"), command: .hubPlayPause) {
                _ in AudioHub.shared.togglePlay()
            }
        }

        // Presets
        let presetsMenu = submenu(in: menu, String(localized: "Presets"))
        for (index, preset) in preferences.presets.enumerated() {
            add(to: presetsMenu, preset.name, equivalent: index < 9 ? "\(index + 1)" : nil) { $0.applyPreset(preset) }
        }
        if !preferences.presets.isEmpty { presetsMenu.addItem(.separator()) }
        add(to: presetsMenu, String(localized: "Save or Edit Presets in Settings…")) { [weak self] _ in self?.showSettings() }

        // Speech
        let speech = submenu(in: menu, String(localized: "Speech"))
        add(to: speech, String(localized: "Silence VoiceOver"), command: .silence, checked: controller.speechSilenced) { $0.toggleSilence() }
        add(to: speech, String(localized: "Beeps While VoiceOver Is Silenced"), command: .beepMode, checked: preferences.beepsWhenSilenced) {
            $0.run(.beepMode)
        }
        add(to: speech, String(localized: "Read Item Under VoiceOver Cursor"), command: .readItem) { $0.readItem() }
        add(to: speech, String(localized: "Speech History…"), command: .history) { [weak self] _ in self?.showHistory() }
        add(to: speech, String(localized: "Say Clipboard"), command: .clipboard) { $0.sayClipboard() }
        add(to: speech, String(localized: "System Status"), command: .systemStatus) { $0.announceSystemStatus() }
        add(to: speech, String(localized: "Large-Print Captions"), command: .captions, checked: Captions.isShowing) { $0.toggleCaptions() }

        // Reading and text
        let reading = submenu(in: menu, String(localized: "Reading and Text"))
        add(to: reading, String(localized: "Doc Reader…"), command: .docReader) { $0.run(.docReader) }
        add(to: reading, String(localized: "Scan and Read…"), command: .scanAndRead) { $0.run(.scanAndRead) }
        add(to: reading, String(localized: "Read Text in Front Window"), command: .readWindow) { $0.run(.readWindow) }
        add(to: reading, String(localized: "Open Last Window Text in Doc Reader")) { _ in ScreenText.openInDocReader() }
        reading.addItem(.separator())
        add(to: reading, String(localized: "Check Clipboard Text…"), command: .analyzeText) { $0.analyzeClipboard() }
        add(to: reading, CompareModel.shared.original == nil ? String(localized: "Compare Text: Save Original") : String(localized: "Compare Text: Compare With Clipboard"),
            command: .compareText) { $0.run(.compareText) }
        add(to: reading, String(localized: "Translate…"), command: .translate) { $0.run(.translate) }
        reading.addItem(.separator())
        add(to: reading, String(localized: "Check a Document's Accessibility…"), command: .documentCheck) { $0.run(.documentCheck) }
        add(to: reading, String(localized: "Save as Braille…"), command: .brailleExport) { $0.run(.brailleExport) }
        add(to: reading, String(localized: "Make a Picture or PDF Accessible…"), command: .fileToPDF) { $0.run(.fileToPDF) }
        reading.addItem(.separator())
        add(to: reading, String(localized: "Focus Frame"), command: .focusFrame, checked: FocusFrame.isShowing) { $0.toggleFocusFrame() }

        // Camera
        let camera = submenu(in: menu, String(localized: "Camera"))
        add(to: camera, String(localized: "Read a Barcode or QR Code"), command: .codeReader, checked: CodeReader.isRunning) { $0.run(.codeReader) }
        add(to: camera, String(localized: "Read a Medicine Label"), command: .labelReader, checked: LabelReader.isRunning) { $0.run(.labelReader) }
        add(to: camera, String(localized: "Identify Money"), command: .moneyReader) { $0.run(.moneyReader) }
        add(to: camera, String(localized: "Identify a Color"), command: .colorIdentifier) { $0.run(.colorIdentifier) }
        add(to: camera, String(localized: "Light Detector"), command: .lightDetector, checked: LightDetector.isRunning) { $0.run(.lightDetector) }
        add(to: camera, String(localized: "Check Camera Framing"), command: .camera) { $0.checkCamera() }
        camera.addItem(.separator())
        add(to: camera, String(localized: "Find an Object…"), command: .objectFinder) { $0.run(.objectFinder) }
        add(to: camera, String(localized: "Scan Pages to an Accessible PDF…"), command: .scanToPDF) { $0.run(.scanToPDF) }

        // Calls and meetings
        let calls = submenu(in: menu, String(localized: "Calls and Meetings"))
        let captionsOn = MainActor.assumeIsolated { CallCaptions.shared.isRunning }
        add(to: calls, String(localized: "Call Captions"), command: .callCaptions, checked: captionsOn) { $0.run(.callCaptions) }
        add(to: calls, String(localized: "Read the Last Caption"), command: .readLastCaption) { $0.run(.readLastCaption) }
        add(to: calls, String(localized: "Copy the Call Transcript"), command: .copyCallTranscript) { $0.run(.copyCallTranscript) }
        calls.addItem(.separator())
        add(to: calls, String(localized: "Am I Muted?"), command: .meetingMuteStatus) { $0.run(.meetingMuteStatus) }
        add(to: calls, String(localized: "Mute or Unmute"), command: .meetingToggleMute) { $0.run(.meetingToggleMute) }
        add(to: calls, String(localized: "Camera On or Off"), command: .meetingToggleVideo) { $0.run(.meetingToggleVideo) }
        add(to: calls, String(localized: "Raise or Lower Hand"), command: .meetingToggleHand) { $0.run(.meetingToggleHand) }
        add(to: calls, String(localized: "Who's Talking?"), command: .meetingWhoIsTalking) { $0.run(.meetingWhoIsTalking) }
        add(to: calls, String(localized: "Open the Chat"), command: .meetingOpenChat) { $0.run(.meetingOpenChat) }
        add(to: calls, String(localized: "Read the Latest Chat Messages"), command: .meetingReadChat) { $0.run(.meetingReadChat) }
        add(to: calls, String(localized: "Read New Chat Messages as They Arrive"), command: .meetingChatAnnounce,
            checked: MeetingHelpers.chatAnnounceEnabled) { $0.run(.meetingChatAnnounce) }
        add(to: calls, String(localized: "Leave the Meeting…"), command: .meetingLeave) { $0.run(.meetingLeave) }

        // Assistant and research
        let assistant = submenu(in: menu, String(localized: "Assistant and Research"))
        add(to: assistant, String(localized: "Describe Image Under VoiceOver Cursor"), command: .describeImage) { $0.run(.describeImage) }
        add(to: assistant, String(localized: "Describe What's Happening in Video"), command: .describeVideo) { $0.run(.describeVideo) }
        add(to: assistant, String(localized: "Ask the Assistant…"), command: .assistant) { $0.run(.assistant) }
        add(to: assistant, String(localized: "Do It for Me…"), command: .doItForMe) { $0.run(.doItForMe) }
        add(to: assistant, String(localized: "Research It…"), command: .research) { $0.run(.research) }

        // VoiceOver help
        let help = submenu(in: menu, String(localized: "VoiceOver Help"))
        add(to: help, String(localized: "Restart VoiceOver"), command: .rescueVoiceOver) { $0.run(.rescueVoiceOver) }
        add(to: help, String(localized: "Keep Audio Awake (Prevents Clipped Words)"), checked: preferences.keepAudioAwake) { [preferences] _ in
            preferences.keepAudioAwake.toggle()
            Announcer.say(preferences.keepAudioAwake ? String(localized: "Keeping audio awake") : String(localized: "Audio can sleep"))
        }
        add(to: help, String(localized: "Find a VoiceOver Command…"), command: .voiceOverCommands) { $0.run(.voiceOverCommands) }
        help.addItem(.separator())
        add(to: help, String(localized: "Label Item Under VoiceOver Cursor…"), command: .customLabel) { $0.run(.customLabel) }
        add(to: help, String(localized: "Add a Place Marker"), command: .placeMarker) { $0.run(.placeMarker) }
        add(to: help, String(localized: "Next Place Marker"), command: .nextPlaceMarker) { $0.run(.nextPlaceMarker) }
        help.addItem(.separator())
        add(to: help, String(localized: "Listen for a Voice Command"), command: .listenForCommand) { $0.run(.listenForCommand) }
        add(to: help, String(localized: "Report a Bug to Apple…"), command: .reportBug) { $0.run(.reportBug) }

        // Learning
        let learning = submenu(in: menu, String(localized: "Learning"))
        add(to: learning, String(localized: "VoiceOver Lessons…"), command: .voiceOverLessons) { $0.run(.voiceOverLessons) }
        add(to: learning, String(localized: "Tutorial…"), command: .tutorial) { $0.run(.tutorial) }
        add(to: learning, String(localized: "Input Help"), command: .inputHelp, checked: InputHelp.isOn) { $0.run(.inputHelp) }
        add(to: learning, String(localized: "VoiceOver Practice…"), command: .practice) { $0.run(.practice) }
        add(to: learning, String(localized: "Typing Trainer…"), command: .typingTrainer) { $0.run(.typingTrainer) }

        // Everyday tools
        let tools = submenu(in: menu, String(localized: "Everyday Tools"))
        add(to: tools, String(localized: "Open Latest Download"), command: .openDownload) { $0.run(.openDownload) }
        add(to: tools, String(localized: "Audio Mouse"), command: .audioMouse, checked: AudioMouse.isOn) { $0.run(.audioMouse) }
        add(to: tools, String(localized: "Timers and Reminders…"), command: .reminders) { $0.run(.reminders) }
        add(to: tools, String(localized: "Clipboard History…"), command: .clipboardHistory) { $0.run(.clipboardHistory) }
        add(to: tools, String(localized: "Switch to a Window…"), command: .windowSwitcher) { $0.run(.windowSwitcher) }

        if !preferences.userCommands.isEmpty {
            let yours = submenu(in: menu, String(localized: "Your Commands"))
            for command in preferences.userCommands {
                add(to: yours, command.name, equivalent: command.key.flatMap(Key.named)?.equivalent) { _ in
                    UserCommands.run(command.id)
                }
            }
        }
        menu.addItem(.separator())

        // App
        add(to: menu, String(localized: "Start at Login"), checked: controller.startsAtLogin) { $0.toggleStartAtLogin() }
        if !Hotkeys.isTrusted {
            add(to: menu, String(localized: "Allow Keyboard Shortcuts…")) { _ in
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        let backup = submenu(in: menu, String(localized: "Backup and Diagnostics"))
        add(to: backup, String(localized: "Export Settings…"), command: .exportSettings) { $0.run(.exportSettings) }
        add(to: backup, String(localized: "Import Settings…"), command: .importSettings) { $0.run(.importSettings) }
        add(to: backup, String(localized: "Save a Diagnostics Report…"), command: .diagnostics) { $0.run(.diagnostics) }
        add(to: backup, String(localized: "App Performance"), command: .performance) { $0.run(.performance) }
        if !UpdateCheck.isStoreCopy {
            add(to: menu, String(localized: "Check for Updates…"), command: .checkForUpdates) { $0.run(.checkForUpdates) }
        }
        add(to: menu, String(localized: "Settings…")) { [weak self] _ in self?.showSettings() }
        add(to: menu, String(localized: "Setup Guide…")) { [weak self] _ in self?.showSetupGuide() }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit VoiceOver Audio Split"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
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

    required init(coder: NSCoder) { fatalError(String(localized: "not used")) }

    @objc private func run() { handler() }
}
