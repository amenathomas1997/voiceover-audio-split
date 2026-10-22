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
        watchFrontApp()
        AudioSystem.start()
        update()
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
        Announcer.useSystemVoice = speechSilenced
        SpeechHistory.shared.update(enabled: preferences.speechHistory)

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
        guard let side = activeSide else { return "Audio split off" }
        if let device = speechDeviceName { return "Speech on \(device), other sounds on the other device" }
        let ear = side.rawValue
        let otherEar = side == .left ? "right" : "left"
        switch preferences.layout {
        case .opposite: return "Speech \(ear), other sounds \(otherEar)"
        case .speechBoth: return "Speech in both ears, other sounds \(otherEar)"
        case .othersBoth: return "Speech \(ear), other sounds in both ears"
        }
    }

    static func describe(balance: Int) -> String {
        if balance == 0 { return "Speech and other sounds equal volume" }
        return balance > 0 ? "Speech \(balance) decibels louder" : "Other sounds \(-balance) decibels louder"
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
            if preferences.ducking { parts.append("Other sounds lower while VoiceOver speaks") }
        }
        if quietAll { parts.append("Everything but VoiceOver is quiet") }
        if speechSilenced { parts.append("VoiceOver is silenced") }
        if preferences.oneEar != .off { parts.append(preferences.oneEar.title) }
        if preferences.clarity { parts.append("Speech clarity on") }
        if preferences.leveler { parts.append("Loud media evened out") }
        if preferences.volumeLimit { parts.append("Volume limit on") }
        if AudioSystem.isMicMuted { parts.append("Microphone muted") }
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
        Announcer.say(quietAll ? "Everything but VoiceOver is quiet" : "Other sounds back")
    }

    // MARK: - Speech on demand

    /// Silences VoiceOver's voice, or brings it back. VoiceOver keeps working;
    /// use Read Item to hear the item under the VoiceOver cursor while silenced.
    func toggleSilence() {
        speechSilenced.toggle()
        update()
        Tones.play(speechSilenced ? .quiet : .unquiet)
        Announcer.say(speechSilenced ? "VoiceOver silenced. Read item speaks on request." : "VoiceOver speaking")
    }

    /// Speaks the item under the VoiceOver cursor.
    func readItem() {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = VoiceOverText.itemUnderCursor()
            DispatchQueue.main.async {
                guard let text, !text.isEmpty else {
                    return Announcer.say("Nothing to read. Check that VoiceOver allows AppleScript control.")
                }
                Announcer.say(text)
            }
        }
    }

    func sayClipboard() {
        Tones.play(.status)
        Announcer.say(Clipboard.describe())
    }

    func checkCamera() {
        Tones.play(.status)
        Announcer.say("Checking the camera")
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
            if !isMe(app) { self?.frontApp = app }
        }
    }

    var frontAppName: String? { frontApp?.localizedName }

    var frontAppMuted: Bool {
        frontApp?.bundleIdentifier.flatMap { preferences.rule(for: $0) }?.muted ?? false
    }

    private func frontRule() -> AppRule? {
        guard let app = frontApp, let id = app.bundleIdentifier else { return nil }
        return preferences.rule(for: id) ?? AppRule(name: app.localizedName ?? id, bundleID: id)
    }

    func changeFrontAppVolume(by delta: Int) {
        guard var rule = frontRule() else { return Announcer.say("No app in front") }
        rule.volume = max(-30, min(6, rule.volume + delta))
        rule.muted = false
        preferences.setRule(rule)
        Tones.play(delta > 0 ? .louder : .quieter)
        Announcer.say("\(rule.name) " + Self.describe(appVolume: rule.volume))
    }

    func toggleFrontAppMute() {
        guard var rule = frontRule() else { return Announcer.say("No app in front") }
        rule.muted.toggle()
        preferences.setRule(rule)
        Tones.play(rule.muted ? .quiet : .unquiet)
        Announcer.say("\(rule.name) \(rule.muted ? "muted" : "unmuted")")
    }

    static func describe(appVolume: Int) -> String {
        if appVolume == 0 { return "normal volume" }
        return appVolume > 0 ? "\(appVolume) decibels louder" : "\(-appVolume) decibels quieter"
    }

    // MARK: - What's playing

    func announcePlaying() {
        let apps = AudioSystem.appsPlaying()
        Tones.play(.status)
        switch apps.count {
        case 0: Announcer.say("Nothing else is playing")
        case 1: Announcer.say("\(apps[0]) is playing")
        default: Announcer.say(ListFormatter.localizedString(byJoining: apps) + " are playing")
        }
    }

    // MARK: - Devices and microphone

    func nextOutputDevice() {
        guard let name = AudioSystem.nextOutputDevice() else { return Announcer.say("Could not switch output") }
        log("Output switched to \(name).")
        Tones.play(.device)
        Announcer.say("Output: \(name)")
    }

    func toggleMicrophone() {
        let result = AudioSystem.toggleMicrophone()
        log("Microphones: \(result).")
        switch result {
        case .muted:
            Tones.play(.micMuted)
            Announcer.say("Microphone muted")
        case .unmuted:
            Tones.play(.micOn)
            Announcer.say("Microphone on, using \(AudioSystem.inputDeviceName)")
        case .unsupported:
            Announcer.say("This microphone can't be muted from here")
        }
        onChange?()
    }

    // MARK: - Presets

    func applyPreset(number: Int) {
        guard number >= 1, number <= preferences.presets.count else {
            return Announcer.say("No preset \(number)")
        }
        applyPreset(preferences.presets[number - 1])
    }

    func applyPreset(_ preset: Preset) {
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
        Announcer.say("\(preset.name). \(describeSplit())")
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
        Announcer.say("Saved preset \(name), number \(preferences.presets.count)")
    }

    // MARK: - Login

    func toggleStartAtLogin() {
        do {
            if startsAtLogin {
                try SMAppService.mainApp.unregister()
                Announcer.say("Audio split will not start at login")
            } else {
                try SMAppService.mainApp.register()
                Announcer.say("Audio split will start at login")
            }
        } catch {
            Announcer.say("Could not change start at login. Check Login Items in System Settings.")
        }
        onChange?()
    }
}
