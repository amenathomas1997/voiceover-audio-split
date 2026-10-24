// Controller.swift — the app's state and actions: the split, the volume
// balance, app volumes, quiet mode, presets, devices, the microphone and start
// at login. Applies Preferences to the Mixer, and runs the Splitter whenever
// any feature needs captured audio. Every change is confirmed with a tone and spoken.

import AppKit
import ServiceManagement

enum Side: String {
    case left, right
}

final class Controller {
    static let shared = Controller()

    private let defaults = UserDefaults.standard
    private let preferences = Preferences.shared
    private var splitter: Splitter?
    private var runningConfiguration: SplitConfiguration?

    /// Called after any change so open menus and windows can refresh.
    var onChange: (() -> Void)?

    /// The ear speech is in, or nil when the split is off. Saved, so the
    /// split comes back the same way after a restart or login.
    private(set) var activeSide: Side? {
        get { defaults.string(forKey: "activeSide").flatMap(Side.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "activeSide") }
    }

    /// The ear used most recently, so the split can come back on that side.
    private var lastSide: Side {
        get { defaults.string(forKey: "lastSide").flatMap(Side.init(rawValue:)) ?? .left }
        set { defaults.set(newValue.rawValue, forKey: "lastSide") }
    }

    /// Decibels. Positive: speech louder than other sounds. Negative: other sounds louder.
    private(set) var balance: Int {
        get { clamp(defaults.integer(forKey: "balance")) }
        set { defaults.set(newValue, forKey: "balance") }
    }

    /// Everything except VoiceOver silenced. Not saved: a restart brings sound back.
    private(set) var quietAll = false

    /// VoiceOver's voice silenced (speech on demand). Not saved, for the same reason.
    private(set) var speechSilenced = false

    var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    private func clamp(_ value: Int) -> Int {
        max(-preferences.balanceLimit, min(preferences.balanceLimit, value))
    }

    /// Restores the saved state at launch, without announcing it.
    func restore() {
        preferences.onChange = { [weak self] in self?.update() }
        // Capture can fail (permission turned off, an unusual output device); say so,
        // at most every half minute, instead of announcing a split that does nothing.
        var lastFailure = Date.distantPast
        NotificationCenter.default.addObserver(forName: Splitter.failed, object: nil, queue: .main) { _ in
            guard Date().timeIntervalSince(lastFailure) > 30 else { return }
            lastFailure = Date()
            Announcer.say(String(localized: "The sound split couldn't start. Check System audio recording in Settings, under Permissions, and try another output device."))
        }
        watchFrontApp()
        AudioSystem.start()
        SystemStatus.start()
        SystemEvents.start()
        update()
        if preferences.captionsOn { Captions.show() }
        if preferences.focusFrameOn { FocusFrame.show() }
    }

    // MARK: - Engine

    /// Whether any feature needs captured audio right now.
    private var engineNeeded: Bool {
        activeSide != nil || quietAll || speechSilenced || preferences.clarity || preferences.leveler || preferences.volumeLimit
            || preferences.oneEar != .off || preferences.earBalance != 0 || !preferences.appRules.isEmpty
            || (preferences.ducking && activeSide != nil)
    }

    private func configuration() -> SplitConfiguration {
        SplitConfiguration(speechDeviceUID: preferences.speechDeviceUID.isEmpty ? nil : preferences.speechDeviceUID,
                           callMode: preferences.callMode,
                           callAppPrefixes: preferences.callApps.map(\.bundleID),
                           appRuleIDs: preferences.appRules.map(\.bundleID))
    }

    /// Pushes every setting to the Mixer, and starts, restarts or stops capture as needed.
    private func update() {
        let gains = Mixer.gains(balance: balance)
        Mixer.state = Mixer.State(split: activeSide, layout: preferences.layout,
                                  stereoOthers: preferences.stereoOthers,
                                  speechGain: gains.speech, othersGain: gains.others,
                                  quietAll: quietAll, speechMuted: speechSilenced,
                                  appRules: preferences.appRules)
        Mixer.duckingEnabled = preferences.ducking && activeSide != nil
        Mixer.duckGain = powf(10, -Float(preferences.duckingAmount) / 20)
        Mixer.clarityEnabled = preferences.clarity
        Mixer.levelerEnabled = preferences.leveler
        Mixer.limiterEnabled = preferences.volumeLimit
        Mixer.limiterCeiling = powf(10, Float(preferences.volumeLimitLevel) / 20)
        Mixer.oneEar = switch preferences.oneEar { case .off: -1; case .left: 0; case .right: 1 }
        let ear = Float(preferences.earBalance)
        Mixer.earGainLeft = ear > 0 ? powf(10, -ear / 20) : 1
        Mixer.earGainRight = ear < 0 ? powf(10, ear / 20) : 1
        Hotkeys.modifier = preferences.modifier
        KeyMap.update(custom: preferences.customKeys, userCommands: preferences.userCommands)
        Announcer.useSystemVoice = speechSilenced
        AudioHub.shared.applyMix(othersGain: activeSide == nil ? 1 : gains.others, quiet: quietAll)
        SpeechHistory.shared.update(enabled: preferences.speechHistory)
        KeepAudioAwake.update(enabled: preferences.keepAudioAwake)
        SystemEvents.updateClock()
        SensorWatch.update()
        CustomLabels.update(preferences.customLabels)
        VoiceCommand.shared.update(enabled: preferences.voiceCommand)
        BeepMode.update(active: speechSilenced && preferences.beepsWhenSilenced)
        ClipboardWatcher.update(enabled: preferences.announceClipboard)
        updateSiteWatching()

        if !engineNeeded {
            if splitter != nil { log("Audio capture off.") }
            splitter?.stop()
            splitter = nil
            runningConfiguration = nil
        } else if splitter == nil || runningConfiguration != configuration() {
            // Devices, call apps and app rules change what is captured: rebuild.
            splitter?.stop()
            let configuration = configuration()
            let splitter = Splitter(configuration: configuration)
            splitter.start()
            self.splitter = splitter
            runningConfiguration = configuration
        }
        onChange?()
    }

    func stopForQuit() {
        splitter?.stop()
    }

    // MARK: - Split

    func setSide(_ side: Side?) {
        activeSide = side
        if let side { lastSide = side } else { log("Split off.") }
        update()
        Tones.play(tone(for: side))
        Announcer.say(describeSplit())
    }

    /// Pressing the side that is already active turns the split off.
    func toggle(_ side: Side) {
        setSide(activeSide == side ? nil : side)
    }

    // MARK: - Descriptions

    private var speechDeviceName: String? {
        preferences.speechDeviceUID.isEmpty ? nil : deviceName(uid: preferences.speechDeviceUID)
    }

    /// "Speech left, other sounds right", "Audio split off", and so on.
    func describeSplit() -> String {
        guard let side = activeSide else { return String(localized: "Audio split off") }
        if let device = speechDeviceName { return String(localized: "Speech on \(device), other sounds on the other device") }
        // Whole sentences for each case, so each language can word them naturally.
        switch (preferences.layout, side) {
        case (.opposite, .left): return String(localized: "Speech left, other sounds right")
        case (.opposite, .right): return String(localized: "Speech right, other sounds left")
        case (.speechBoth, .left): return String(localized: "Speech in both ears, other sounds right")
        case (.speechBoth, .right): return String(localized: "Speech in both ears, other sounds left")
        case (.othersBoth, .left): return String(localized: "Speech left, other sounds in both ears")
        case (.othersBoth, .right): return String(localized: "Speech right, other sounds in both ears")
        }
    }

    static func describe(balance: Int) -> String {
        if balance == 0 { return String(localized: "Speech and other sounds equal volume") }
        return balance > 0 ? String(localized: "Speech \(balance) decibels louder") : String(localized: "Other sounds \(-balance) decibels louder")
    }

    private func tone(for side: Side?) -> Tone {
        guard let side else { return .off }
        if speechDeviceName != nil || preferences.layout == .speechBoth { return .speechBoth }
        return side == .left ? .speechLeft : .speechRight
    }

    /// Says what is on, for the status shortcut.
    func announceStatus() {
        var parts = [describeSplit()]
        if activeSide != nil {
            parts.append(Self.describe(balance: balance))
            if preferences.ducking { parts.append(String(localized: "Other sounds lower while VoiceOver speaks")) }
        }
        if quietAll { parts.append(String(localized: "Everything but VoiceOver is quiet")) }
        if speechSilenced { parts.append(String(localized: "VoiceOver is silenced")) }
        if preferences.oneEar != .off { parts.append(preferences.oneEar.title) }
        if preferences.clarity { parts.append(String(localized: "Speech clarity on")) }
        if preferences.leveler { parts.append(String(localized: "Loud media evened out")) }
        if preferences.volumeLimit { parts.append(String(localized: "Volume limit on")) }
        if AudioSystem.isMicMuted { parts.append(String(localized: "Microphone muted")) }
        Tones.play(.status)
        Announcer.say(parts.joined(separator: ". "))
    }

    // MARK: - Balance

    /// Changes the balance. The balance only affects what you hear while the
    /// split is running, so this turns the split back on (last ear used) if it is off.
    func changeBalance(by delta: Int) {
        balance = clamp(balance + delta)
        log("Balance \(balance) dB.")
        var message = Self.describe(balance: balance)
        if activeSide == nil {
            activeSide = lastSide
            message = describeSplit() + ". " + message
        }
        update()
        Tones.play(delta > 0 ? .louder : .quieter)
        Announcer.say(message)
    }

    func resetBalance() {
        balance = 0
        update()
        Tones.play(.status)
        Announcer.say(Self.describe(balance: 0))
    }

    // MARK: - Quiet everything but VoiceOver

    func toggleQuiet() {
        quietAll.toggle()
        update()
        Tones.play(quietAll ? .quiet : .unquiet)
        Announcer.say(quietAll ? String(localized: "Everything but VoiceOver is quiet") : String(localized: "Other sounds back"))
    }

    // MARK: - Commands

    /// Runs a keyboard command (from a shortcut, the layer, or the menu).
    func run(_ command: Command) {
        let app = NSApp.delegate as? AppDelegate
        defer { NotificationCenter.default.post(name: .commandRan, object: command) }
        switch command {
        case .speechLeft: toggle(.left)
        case .speechRight: toggle(.right)
        case .speechLouder: changeBalance(by: preferences.balanceStep)
        case .othersLouder: changeBalance(by: -preferences.balanceStep)
        case .status: announceStatus()
        case .menu: app?.popUpMenu()
        case .quiet: toggleQuiet()
        case .playing: announcePlaying()
        case .appLouder: changeFrontAppVolume(by: 3)
        case .appQuieter: changeFrontAppVolume(by: -3)
        case .appMute: toggleFrontAppMute()
        case .device: nextOutputDevice()
        case .microphone: toggleMicrophone()
        case .silence: toggleSilence()
        case .readItem: readItem()
        case .history: app?.showHistory()
        case .clipboard: sayClipboard()
        case .camera: checkCamera()
        case .layer:
            Tones.play(.status)
            Announcer.say(String(localized: "Layer"))
        case .describeImage: app?.showAssistant(describingImage: true)
        case .assistant: app?.showAssistant(describingImage: false)
        case .analyzeText: analyzeClipboard()
        case .research: app?.showResearch()
        case .systemStatus: announceSystemStatus()
        case .docReader: app?.showDocReader()
        case .scanAndRead: app?.showScan()
        case .captions: toggleCaptions()
        case .focusFrame: toggleFocusFrame()
        case .audioHub: app?.showAudioHub()
        case .hubPlayPause: AudioHub.shared.togglePlay()
        case .rescueVoiceOver: MainActor.assumeIsolated { VoiceOverRescue.restart() }
        case .compareText:
            CompareModel.shared.step()
            if CompareModel.shared.original == nil { app?.showCompare() }
        case .voiceOverCommands: app?.showVoiceOverCommands()
        case .reportBug: app?.showBugReport()
        case .readWindow: ScreenText.readFrontWindow()
        case .describeVideo: AssistantModel.shared.describeImage(.video)
        case .openDownload: SystemEvents.openLatestDownload()
        case .micCheck: MicCheck.run()
        case .colorIdentifier: ColorIdentifier.identify()
        case .lightDetector: LightDetector.toggle()
        case .commandPalette: app?.showPalette()
        case .inputHelp: InputHelp.toggle()
        case .tutorial: app?.showTutorial()
        case .translate:
            TranslateModel.shared.loadClipboard()
            app?.showTranslate()
            // After the window has appeared: it only reacts to requests made while it's showing.
            DispatchQueue.main.async { TranslateModel.shared.translate() }
        case .audioMouse: AudioMouse.toggle()
        case .beepMode:
            preferences.beepsWhenSilenced.toggle()
            Announcer.say(preferences.beepsWhenSilenced ? String(localized: "Beeps on while VoiceOver is silenced") : String(localized: "Beeps off"))
        case .exportSettings: MainActor.assumeIsolated { SettingsTransfer.export() }
        case .importSettings: MainActor.assumeIsolated { SettingsTransfer.importFromFile() }
        case .diagnostics: MainActor.assumeIsolated { Diagnostics.save() }
        case .performance: Performance.announce()
        case .checkForUpdates: MainActor.assumeIsolated { Updater.shared.check(userInitiated: true) }
        case .sensorStatus: SensorWatch.queueSummary()
        case .customLabel: app?.showLabelEditor()
        case .placeMarker: PlaceMarkers.add()
        case .nextPlaceMarker: PlaceMarkers.next()
        case .doItForMe: app?.showDoItForMe()
        case .documentCheck: app?.showDocumentCheck()
        case .brailleExport: app?.showBraille()
        case .codeReader: CodeReader.toggle()
        case .labelReader: LabelReader.toggle()
        case .moneyReader: MoneyReader.identify()
        case .practice: app?.showPractice()
        case .typingTrainer: app?.showTypingTrainer()
        case .voiceOverLessons: app?.showLessons()
        case .listenForCommand: VoiceCommand.shared.listenOnce()
        }
    }

    // MARK: - Speech on demand

    /// Silences VoiceOver's voice, or brings it back. VoiceOver keeps working;
    /// use Read Item to hear the item under the VoiceOver cursor while silenced.
    func toggleSilence() {
        speechSilenced.toggle()
        update()
        Tones.play(speechSilenced ? .quiet : .unquiet)
        Announcer.say(speechSilenced ? String(localized: "VoiceOver silenced. Read item speaks on request.") : String(localized: "VoiceOver speaking"))
    }

    /// Speaks the item under the VoiceOver cursor.
    func readItem() {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = VoiceOverText.itemUnderCursor()
            DispatchQueue.main.async {
                guard let text, !text.isEmpty else {
                    return Announcer.say(String(localized: "Nothing to read. Check that VoiceOver allows AppleScript control."))
                }
                Announcer.say(text)
            }
        }
    }

    func sayClipboard() {
        Tones.play(.status)
        Announcer.say(Clipboard.describe())
    }

    func toggleCaptions() {
        if Captions.isShowing { Captions.hide() } else { Captions.show() }
        preferences.captionsOn = Captions.isShowing
        Announcer.say(Captions.isShowing ? String(localized: "Captions on") : String(localized: "Captions off"))
    }

    func toggleFocusFrame() {
        if FocusFrame.isShowing { FocusFrame.hide() } else { FocusFrame.show() }
        preferences.focusFrameOn = FocusFrame.isShowing
        Announcer.say(FocusFrame.isShowing ? String(localized: "Focus frame on") : String(localized: "Focus frame off"))
    }

    func announceSystemStatus() {
        Tones.play(.status)
        Announcer.say(SystemStatus.summary())
    }

    /// Checks the clipboard and opens the Text Checker to step through the problems.
    func analyzeClipboard() {
        Tones.play(.status)
        TextCheckerModel.shared.checkClipboard()
        (NSApp.delegate as? AppDelegate)?.showTextChecker()
    }

    func checkCamera() {
        Tones.play(.status)
        Announcer.say(String(localized: "Checking the camera"))
        FaceCheck.shared.run { message in Announcer.say(message) }
    }

    // MARK: - Front app

    /// The last app in front other than this one. Opening this app's menu or
    /// windows brings it to the front, so the app before it is remembered.
    private var frontApp: NSRunningApplication?

    private func watchFrontApp() {
        let isMe = { (app: NSRunningApplication?) in app?.bundleIdentifier == Bundle.main.bundleIdentifier }
        if !isMe(NSWorkspace.shared.frontmostApplication) { frontApp = NSWorkspace.shared.frontmostApplication }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if !isMe(app) {
                self?.frontApp = app
                self?.applyAutomaticPreset(for: app)
            }
        }
    }

    var frontAppName: String? { frontApp?.localizedName }
    /// The app in front, or the last one before this app's own windows came forward.
    var lastUsedApp: NSRunningApplication? { frontApp }

    /// The preset last switched on automatically, so switching between apps that
    /// share a preset doesn't announce it again.
    private var automaticPresetID: String?

    /// Switches to the preset chosen for this app in Settings, or the one for all
    /// other apps. Apps with neither leave the current settings alone.
    private func applyAutomaticPreset(for app: NSRunningApplication?) {
        guard let bundleID = app?.bundleIdentifier else { return }
        // In a browser, a preset for the current website wins (checked by the site timer).
        if SitePresets.browsers[bundleID] != nil, currentSitePresetID != nil { return }
        applyAutomaticPreset(id: appPresetID(for: bundleID), reason: bundleID)
    }

    private func appPresetID(for bundleID: String) -> String? {
        preferences.appPresets[bundleID] ?? (preferences.otherAppsPreset.isEmpty ? nil : preferences.otherAppsPreset)
    }

    private func applyAutomaticPreset(id presetID: String?, reason: String) {
        guard let presetID, presetID != automaticPresetID,
              let preset = preferences.presets.first(where: { $0.id.uuidString == presetID }) else { return }
        log("Automatic preset \(preset.name) for \(reason).")
        applyPreset(preset, automatic: true)
        automaticPresetID = presetID
    }

    // MARK: - Website presets

    private var siteTimer: Timer?
    /// The website preset in effect, if the front browser is on a site that has one.
    private var currentSitePresetID: String?

    /// Checks the front browser's address every two seconds, only while website presets exist.
    private func updateSiteWatching() {
        if preferences.sitePresets.isEmpty {
            siteTimer?.invalidate()
            siteTimer = nil
            currentSitePresetID = nil
        } else if siteTimer == nil {
            siteTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkSite() }
        }
    }

    private func checkSite() {
        guard let front = NSWorkspace.shared.frontmostApplication, let bundleID = front.bundleIdentifier,
              let script = SitePresets.browsers[bundleID] else { return }
        let rules = preferences.sitePresets
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let host = AppleScriptRunner.run(script, logErrors: false).flatMap { URL(string: $0)?.host() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let sitePreset = host.flatMap { SitePresets.match(host: $0, in: rules) }
                self.currentSitePresetID = sitePreset
                self.applyAutomaticPreset(id: sitePreset ?? self.appPresetID(for: bundleID), reason: host ?? bundleID)
            }
        }
    }

    var frontAppMuted: Bool {
        frontApp?.bundleIdentifier.flatMap { preferences.rule(for: $0) }?.muted ?? false
    }

    private func frontRule() -> AppRule? {
        guard let app = frontApp, let id = app.bundleIdentifier else { return nil }
        return preferences.rule(for: id) ?? AppRule(name: app.localizedName ?? id, bundleID: id)
    }

    func changeFrontAppVolume(by delta: Int) {
        guard var rule = frontRule() else { return Announcer.say(String(localized: "No app in front")) }
        rule.volume = max(-30, min(6, rule.volume + delta))
        rule.muted = false
        preferences.setRule(rule)
        Tones.play(delta > 0 ? .louder : .quieter)
        Announcer.say(String(localized: "\(rule.name): \(Self.describe(appVolume: rule.volume))"))
    }

    func toggleFrontAppMute() {
        guard var rule = frontRule() else { return Announcer.say(String(localized: "No app in front")) }
        rule.muted.toggle()
        preferences.setRule(rule)
        Tones.play(rule.muted ? .quiet : .unquiet)
        Announcer.say(rule.muted ? String(localized: "\(rule.name) muted") : String(localized: "\(rule.name) unmuted"))
    }

    static func describe(appVolume: Int) -> String {
        if appVolume == 0 { return String(localized: "normal volume") }
        return appVolume > 0 ? String(localized: "\(appVolume) decibels louder") : String(localized: "\(-appVolume) decibels quieter")
    }

    /// -100 to 100, as words: "middle", "left 50", "fully right".
    static func describe(position: Int) -> String {
        switch position {
        case 0: String(localized: "middle")
        case ...(-100): String(localized: "fully left")
        case 100...: String(localized: "fully right")
        case ..<0: String(localized: "left \(-position)")
        default: String(localized: "right \(position)")
        }
    }

    static func describe(tone: Int) -> String {
        if tone == 0 { return String(localized: "normal") }
        return tone > 0 ? String(localized: "plus \(tone) decibels") : String(localized: "minus \(-tone) decibels")
    }

    // MARK: - What's playing

    func announcePlaying() {
        let apps = AudioSystem.appsPlaying()
        Tones.play(.status)
        switch apps.count {
        case 0: Announcer.say(String(localized: "Nothing else is playing"))
        case 1: Announcer.say(String(localized: "\(apps[0]) is playing"))
        default: Announcer.say(ListFormatter.localizedString(byJoining: apps) + " are playing")
        }
    }

    // MARK: - Devices and microphone

    func nextOutputDevice() {
        guard let name = AudioSystem.nextOutputDevice() else { return Announcer.say(String(localized: "Could not switch output")) }
        log("Output switched to \(name).")
        Tones.play(.device)
        Announcer.say(String(localized: "Output: \(name)"))
    }

    func toggleMicrophone() {
        let result = AudioSystem.toggleMicrophone()
        log("Microphones: \(result).")
        switch result {
        case .muted:
            Tones.play(.micMuted)
            Announcer.say(String(localized: "Microphone muted"))
        case .unmuted:
            Tones.play(.micOn)
            Announcer.say(String(localized: "Microphone on, using \(AudioSystem.inputDeviceName)"))
        case .unsupported:
            Announcer.say(String(localized: "This microphone can't be muted from here"))
        }
        onChange?()
    }

    // MARK: - Presets

    func applyPreset(number: Int) {
        guard number >= 1, number <= preferences.presets.count else {
            return Announcer.say(String(localized: "No preset \(number)"))
        }
        applyPreset(preferences.presets[number - 1])
    }

    /// Chosen by hand, a preset ends the automatic one, so coming back to that app applies it again.
    func applyPreset(_ preset: Preset, automatic: Bool = false) {
        if !automatic { automaticPresetID = nil }
        preferences.layout = preset.layout
        preferences.stereoOthers = preset.stereoOthers
        preferences.ducking = preset.ducking
        preferences.duckingAmount = preset.duckingAmount
        preferences.callMode = preset.callMode
        preferences.clarity = preset.clarity
        preferences.leveler = preset.leveler
        preferences.volumeLimit = preset.volumeLimit
        preferences.volumeLimitLevel = preset.volumeLimitLevel
        preferences.oneEar = preset.oneEar
        preferences.earBalance = preset.earBalance
        balance = clamp(preset.balance)
        activeSide = Side(rawValue: preset.split)
        if let side = activeSide { lastSide = side }
        update()
        Tones.play(.preset)
        Announcer.say(String(localized: "\(preset.name). \(describeSplit())"))
    }

    /// Saves the current settings as a new preset.
    func saveCurrentAsPreset(named name: String) {
        let preset = Preset(name: name, split: activeSide?.rawValue ?? "off", balance: balance,
                            layout: preferences.layout, stereoOthers: preferences.stereoOthers,
                            ducking: preferences.ducking, duckingAmount: preferences.duckingAmount,
                            callMode: preferences.callMode, clarity: preferences.clarity,
                            leveler: preferences.leveler, volumeLimit: preferences.volumeLimit,
                            volumeLimitLevel: preferences.volumeLimitLevel, oneEar: preferences.oneEar,
                            earBalance: preferences.earBalance)
        preferences.presets.append(preset)
        Announcer.say(String(localized: "Saved preset \(name), number \(preferences.presets.count)"))
    }

    // MARK: - Login

    func toggleStartAtLogin() {
        do {
            if startsAtLogin {
                try SMAppService.mainApp.unregister()
                Announcer.say(String(localized: "Audio split will not start at login"))
            } else {
                try SMAppService.mainApp.register()
                Announcer.say(String(localized: "Audio split will start at login"))
            }
        } catch {
            Announcer.say(String(localized: "Could not change start at login. Check Login Items in System Settings."))
        }
        onChange?()
    }
}
