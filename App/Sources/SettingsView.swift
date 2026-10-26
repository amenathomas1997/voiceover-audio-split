// SettingsView.swift — the Settings window. Every control is a standard
// SwiftUI control with a text label, so VoiceOver reads it as-is.

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var devices: [OutputDevice] = outputDevices()
    @State private var appToAdd = ""
    @State private var ruleAppToAdd = ""
    @State private var newPresetName = ""
    @State private var presetAppToAdd = ""
    @State private var apiKey = ""
    @State private var hasAPIKey = APIKey.current != nil
    @State private var newSite = ""

    var body: some View {
        Form {
            PermissionsSection()

            Section(String(localized: "Where sounds go")) {
                Picker(String(localized: "Layout"), selection: $preferences.layout) {
                    ForEach(Layout.allCases) { Text($0.title).tag($0) }
                }
                Toggle(String(localized: "Keep other sounds in stereo"), isOn: $preferences.stereoOthers)
                Text(String(localized: "Music keeps its stereo sound but leans toward its ear. Off mixes other sounds to mono, like JAWS."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(String(localized: "Play speech on"), selection: $preferences.speechDeviceUID) {
                    Text(String(localized: "Same device as other sounds")).tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                Text(String(localized: "Choose another device, such as AirPods, to hear VoiceOver privately while other sounds play on the current output."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(String(localized: "Refresh device list")) { devices = outputDevices() }
                Toggle(String(localized: "Ask before keeping sound changes"), isOn: $preferences.confirmSoundChanges)
                Text(String(localized: "After a change that could stop you hearing your Mac, such as the output device, one-ear mode, the volume limit or the hearing profile, the app asks whether to keep it. If you don't answer within a minute, it goes back by itself."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Volume")) {
                Stepper(String(localized: "Change per key press: \(preferences.balanceStep) decibels"),
                        value: $preferences.balanceStep, in: 1...6)
                Stepper(String(localized: "Largest difference: \(preferences.balanceLimit) decibels"),
                        value: $preferences.balanceLimit, in: 6...30, step: 3)
                Toggle(String(localized: "Lower other sounds while VoiceOver speaks"), isOn: $preferences.ducking)
                Stepper(String(localized: "Lower by: \(preferences.duckingAmount) decibels"),
                        value: $preferences.duckingAmount, in: 3...30, step: 3)
                    .disabled(!preferences.ducking)
            }

            Section(String(localized: "Clearer speech and hearing")) {
                Toggle(String(localized: "Speech clarity boost"), isOn: $preferences.clarity)
                Text(String(localized: "Makes VoiceOver easier to understand over loud media, without just making it louder."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Even out loud media"), isOn: $preferences.leveler)
                Text(String(localized: "Turns down sudden loud moments in videos, music and ads."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Volume limit"), isOn: $preferences.volumeLimit)
                Stepper(String(localized: "Limit: \(-preferences.volumeLimitLevel) decibels below full volume"),
                        value: $preferences.volumeLimitLevel, in: -24...(-1), step: 1)
                    .disabled(!preferences.volumeLimit)
                Text(String(localized: "Keeps all sound below this level to protect your hearing. It works on top of the Mac's volume."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(String(localized: "One ear"), selection: $preferences.oneEar) {
                    ForEach(OneEar.allCases) { Text($0.title).tag($0) }
                }
                Text(String(localized: "For hearing in one ear: VoiceOver and every other sound are combined into that ear."))
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(earBalanceTitle, value: $preferences.earBalance, in: -12...12)
                Text(String(localized: "Makes one ear louder than the other, for people who hear less on one side."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Use my hearing profile"), isOn: $preferences.hearingProfileOn)
                Button(String(localized: "Set Up My Hearing Profile…")) { (NSApp.delegate as? AppDelegate)?.showHearingProfile() }
                Text(String(localized: "Boosts the frequencies you hear less well, for each ear, from an audiogram or a quick listening test."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Apps")) {
                Text(String(localized: "Give an app its own volume, ear or place between your ears, and bass and treble. You can also hold the shortcut key and press equals, minus or zero to change the app in front."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.appRules) { rule in
                    VStack(alignment: .leading) {
                        Text(rule.name).font(.headline)
                        Stepper(String(localized: "\(rule.name) volume: \(Controller.describe(appVolume: rule.volume))"),
                                value: ruleBinding(rule, \.volume), in: -30...6, step: 3)
                        Toggle(String(localized: "Mute \(rule.name)"), isOn: ruleBinding(rule, \.muted))
                        Picker(String(localized: "\(rule.name) plays in"), selection: ruleBinding(rule, \.ear)) {
                            ForEach(EarChoice.allCases) { Text($0.title).tag($0) }
                        }
                        if rule.ear == .position {
                            Stepper(String(localized: "\(rule.name) position: \(Controller.describe(position: rule.position))"),
                                    value: ruleBinding(rule, \.position), in: -100...100, step: 25)
                        }
                        Stepper(String(localized: "\(rule.name) bass: \(Controller.describe(tone: rule.bass))"),
                                value: ruleBinding(rule, \.bass), in: -12...12, step: 3)
                        Stepper(String(localized: "\(rule.name) treble: \(Controller.describe(tone: rule.treble))"),
                                value: ruleBinding(rule, \.treble), in: -12...12, step: 3)
                        Button(String(localized: "Reset \(rule.name)")) {
                            preferences.appRules.removeAll { $0.bundleID == rule.bundleID }
                        }
                    }
                }
                HStack {
                    Picker(String(localized: "Add an app"), selection: $ruleAppToAdd) {
                        Text(String(localized: "Choose an open app")).tag("")
                        ForEach(openApps.filter { app in preferences.rule(for: app.bundleID) == nil }, id: \.bundleID) {
                            Text($0.name).tag($0.bundleID)
                        }
                    }
                    Button(String(localized: "Add")) {
                        if let app = openApps.first(where: { $0.bundleID == ruleAppToAdd }) {
                            // Start at a slightly lower volume so the new rule takes effect.
                            preferences.setRule(AppRule(name: app.name, bundleID: app.bundleID, volume: -3))
                            ruleAppToAdd = ""
                        }
                    }
                    .disabled(ruleAppToAdd.isEmpty)
                }
            }

            Section(String(localized: "Presets")) {
                Text(String(localized: "Hold the shortcut key and press a number to switch to a preset."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(preferences.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack {
                        Text(index < 9 ? "\(index + 1): \(preset.name)" : preset.name)
                        Spacer()
                        Button(String(localized: "Use \(preset.name)")) { Controller.shared.applyPreset(preset) }
                        Button(String(localized: "Delete \(preset.name)")) {
                            preferences.presets.removeAll { $0.id == preset.id }
                            preferences.forgetMissingPresets()
                        }
                    }
                }
                HStack {
                    TextField(String(localized: "New preset name"), text: $newPresetName)
                    Button(String(localized: "Save current settings")) {
                        Controller.shared.saveCurrentAsPreset(named: newPresetName.trimmingCharacters(in: .whitespaces))
                        newPresetName = ""
                    }
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(String(localized: "Restore default presets")) {
                    preferences.presets = Preset.defaults
                    preferences.forgetMissingPresets()
                }
            }

            Section(String(localized: "Automatic presets")) {
                Text(String(localized: "Switch to a preset whenever an app comes to the front, for example Meeting for Zoom."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.appPresets.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        Picker(appName(bundleID), selection: appPresetBinding(bundleID)) {
                            ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Button(String(localized: "Remove \(appName(bundleID))")) { preferences.appPresets[bundleID] = nil }
                    }
                }
                HStack {
                    Picker(String(localized: "Add an app"), selection: $presetAppToAdd) {
                        Text(String(localized: "Choose an open app")).tag("")
                        ForEach(openApps.filter { preferences.appPresets[$0.bundleID] == nil }, id: \.bundleID) {
                            Text($0.name).tag($0.bundleID)
                        }
                    }
                    Button(String(localized: "Add")) {
                        if let first = preferences.presets.first, !presetAppToAdd.isEmpty {
                            preferences.appPresets[presetAppToAdd] = first.id.uuidString
                            presetAppToAdd = ""
                        }
                    }
                    .disabled(presetAppToAdd.isEmpty || preferences.presets.isEmpty)
                }
                Picker(String(localized: "All other apps"), selection: $preferences.otherAppsPreset) {
                    Text(String(localized: "Keep current settings")).tag("")
                    ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                }
            }

            Section(String(localized: "Voice command")) {
                Toggle(String(localized: "Always listen for \u{201C}Audio Split\u{201D} and \u{201C}Launch VoiceOver training\u{201D}"), isOn: $preferences.voiceCommand)
                Text(String(localized: "Say Audio Split, then a command, such as: Audio Split, quiet everything. Say Audio Split, what can I say, to hear them all. Launch VoiceOver training works on its own. Speech is recognized on your Mac and never recorded or saved; only Audio Split, find… sends your request to Anthropic, through Do It for Me. It uses the built-in microphone, so AirPods keep their full sound, and the microphone indicator stays on while it listens."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "Prefer not to keep the microphone on? Leave this off and give Listen for a Voice Command a key in Command keys: press it, then say the command without Audio Split."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(String(localized: "Hear the Voice Commands")) { Announcer.say(VoiceCommands.whatCanISay()) }
            }

            Section(String(localized: "Spoken events and clock")) {
                Toggle(String(localized: "Say when a download finishes"), isOn: $preferences.announceDownloads)
                Toggle(String(localized: "Say when headphones or speakers connect or disconnect"), isOn: $preferences.announceDevices)
                Toggle(String(localized: "Say when the network connection drops or comes back"), isOn: $preferences.announceNetwork)
                Toggle(String(localized: "Say when the battery is low, and when charging starts or stops"), isOn: $preferences.announceBattery)
                Toggle(String(localized: "Say when the screen locks"), isOn: $preferences.announceLock)
                Toggle(String(localized: "Say when another app turns the camera on or off"), isOn: $preferences.announceCamera)
                Toggle(String(localized: "Say when an app starts or stops using the microphone"), isOn: $preferences.announceMicrophone)
                Picker(String(localized: "Talking clock"), selection: $preferences.clockInterval) {
                    Text(String(localized: "Off")).tag(0)
                    Text(String(localized: "Every hour")).tag(60)
                    Text(String(localized: "Every half hour")).tag(30)
                    Text(String(localized: "Every quarter hour")).tag(15)
                }
            }

            Section(String(localized: "Presets for websites")) {
                Text(String(localized: "Switch to a preset on a website in Safari or Chrome, for example a quieter preset on youtube.com. The first time, your Mac asks to let VoiceOver Audio Split see which site is open."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.sitePresets.keys.sorted(), id: \.self) { site in
                    HStack {
                        Picker(site, selection: Binding(get: { preferences.sitePresets[site] ?? "" },
                                                        set: { preferences.sitePresets[site] = $0 })) {
                            ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Button(String(localized: "Remove \(site)")) { preferences.sitePresets[site] = nil }
                    }
                }
                HStack {
                    TextField(String(localized: "Website, for example youtube.com"), text: $newSite)
                    Button(String(localized: "Add")) {
                        if let first = preferences.presets.first {
                            preferences.sitePresets[SitePresets.normalize(newSite)] = first.id.uuidString
                            newSite = ""
                        }
                    }
                    .disabled(SitePresets.normalize(newSite).isEmpty || preferences.presets.isEmpty)
                }
            }

            Section(String(localized: "Calls")) {
                Picker(String(localized: "Call audio"), selection: $preferences.callMode) {
                    ForEach(CallMode.allCases) { Text($0.title).tag($0) }
                }
                ForEach(preferences.callApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button(String(localized: "Remove \(app.name)")) {
                            preferences.callApps.removeAll { $0 == app }
                        }
                    }
                }
                HStack {
                    Picker(String(localized: "Add a call app"), selection: $appToAdd) {
                        Text(String(localized: "Choose an open app")).tag("")
                        ForEach(addableApps, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
                    }
                    Button(String(localized: "Add")) {
                        if let app = addableApps.first(where: { $0.bundleID == appToAdd }) {
                            preferences.callApps.append(app)
                            appToAdd = ""
                        }
                    }
                    .disabled(appToAdd.isEmpty)
                }
                Button(String(localized: "Restore default call apps")) { preferences.callApps = CallApp.defaults }
                Toggle(String(localized: "Read new meeting chat messages as they arrive"), isOn: Binding(
                    get: { MeetingHelpers.chatAnnounceEnabled }, set: { MeetingHelpers.chatAnnounceEnabled = $0 }))
                Text(String(localized: "Call captions and the meeting commands, such as Am I Muted and Raise My Hand, are in the menu under Calls and Meetings. Captions are recognized on your Mac and never recorded or sent."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Everyday tools")) {
                Toggle(String(localized: "Keep a clipboard history"), isOn: Binding(
                    get: { ClipboardHistory.shared.isEnabled }, set: { ClipboardHistory.shared.isEnabled = $0 }))
                Text(String(localized: "Keeps the last 20 things you copy, in memory only, so you can hear and copy them again. Passwords copied from password managers are left out."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Show a notification for timers and reminders"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: Reminders.notificationsKey) as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: Reminders.notificationsKey) }))
                Text(String(localized: "Timers and reminders are always spoken. A notification also stays on screen until you dismiss it."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Keyboard and sounds")) {
                Picker(String(localized: "Shortcut key"), selection: $preferences.modifier) {
                    ForEach(ShortcutModifier.allCases) { Text($0.title).tag($0) }
                }
                Text(String(localized: "Hold it with a command's key below, or press the layer key first and then the command's key on its own. Digits 1 to 9 switch presets. The key of the same kind on the left keeps working normally."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Play a short tone with each change"), isOn: $preferences.playTones)
                Toggle(String(localized: "Keep audio awake, so the first words VoiceOver says aren't cut off"), isOn: $preferences.keepAudioAwake)
                Text(String(localized: "Plays silence so headphones and Bluetooth devices like AirPods don't go to sleep between phrases."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Beep each time VoiceOver would speak while it's silenced"), isOn: $preferences.beepsWhenSilenced)
                Toggle(String(localized: "Say what you copy"), isOn: $preferences.announceClipboard)
                Toggle(String(localized: "Use a nearby iPhone as the camera when available"), isOn: $preferences.preferIPhoneCamera)
                Toggle(String(localized: "Keep speech history"), isOn: $preferences.speechHistory)
                Text(String(localized: "Keeps a list of what VoiceOver says, in memory only, to review and copy from the Speech History window."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Low vision")) {
                Picker(String(localized: "Colors for large print"), selection: $preferences.readingTheme) {
                    ForEach(ReadingTheme.allCases) { Text($0.title).tag($0) }
                }
                Stepper(String(localized: "Caption text size: \(preferences.captionSize)"), value: $preferences.captionSize, in: 20...96, step: 4)
                Toggle(String(localized: "Show large-print captions of what VoiceOver says"), isOn: Binding(
                    get: { preferences.captionsOn },
                    set: { on in if on != Captions.isShowing { Controller.shared.toggleCaptions() } }))
                Toggle(String(localized: "Show a focus frame around the VoiceOver cursor"), isOn: Binding(
                    get: { preferences.focusFrameOn },
                    set: { on in if on != FocusFrame.isShowing { Controller.shared.toggleFocusFrame() } }))
                Picker(String(localized: "Focus frame color"), selection: $preferences.focusFrameColor) {
                    ForEach(FrameColor.allCases) { Text($0.title).tag($0) }
                }
                Stepper(String(localized: "Focus frame thickness: \(preferences.focusFrameThickness)"),
                        value: $preferences.focusFrameThickness, in: 2...24, step: 2)
                Toggle(String(localized: "Flash the focus frame when it moves"), isOn: $preferences.focusFrameFlash)
                Stepper(String(localized: "Doc Reader text size: \(preferences.readerFontSize)"), value: $preferences.readerFontSize,
                        in: 14...96, step: 4)
            }
            .onChange(of: preferences.focusFrameColor) { FocusFrame.refresh() }
            .onChange(of: preferences.focusFrameThickness) { FocusFrame.refresh() }

            UserCommandsSection()

            PlaceMarkersSection()

            Section(String(localized: "Command keys")) {
                ForEach(Command.allCases) { command in
                    Picker(command.title, selection: keyBinding(command)) {
                        Text(String(localized: "No key")).tag(Key.none)
                        ForEach(Key.assignable) { Text($0.name).tag($0.code) }
                    }
                }
                Button(String(localized: "Restore default keys")) { preferences.customKeys = [:] }
                Text(String(localized: "Choosing a key another command uses swaps the two commands' keys."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Assistant and image descriptions")) {
                Text(hasAPIKey ? String(localized: "An Anthropic API key is saved in your Keychain.") :
                        String(localized: "The assistant and image descriptions use Claude. Paste an API key from console.anthropic.com. Requests are billed to that account."))
                SecureField(hasAPIKey ? String(localized: "Replace API key") : String(localized: "API key"), text: $apiKey)
                HStack {
                    Button(String(localized: "Save key")) {
                        APIKey.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        apiKey = ""
                        hasAPIKey = APIKey.current != nil
                        Announcer.say(String(localized: "Key saved"))
                    }
                    .disabled(apiKey.isEmpty)
                    Button(String(localized: "Remove key")) {
                        APIKey.save("")
                        hasAPIKey = false
                        Announcer.say(String(localized: "Key removed"))
                    }
                    .disabled(!hasAPIKey)
                }
                Toggle(String(localized: "Allow sending pictures of the screen for image descriptions"), isOn: $preferences.allowImageUpload)
                Text(String(localized: "Only the item under the VoiceOver cursor is sent, and only when you ask for a description."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Backup and diagnostics")) {
                HStack {
                    Button(String(localized: "Export Settings…")) { SettingsTransfer.export() }
                    Button(String(localized: "Import Settings…")) { SettingsTransfer.importFromFile() }
                }
                Button(String(localized: "Save a Diagnostics Report…")) { Diagnostics.save() }
                Text(String(localized: "Export saves your keys, presets, app and website rules and other settings in one file, to back up or set up another Mac. Diagnostics reports include the app's recent log for bug reports; never your API key or files."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !UpdateCheck.isStoreCopy {
                Section(String(localized: "Updates")) {
                    Toggle(String(localized: "Check for updates automatically"), isOn: $preferences.checkForUpdates)
                    Button(String(localized: "Check for Updates Now")) { Updater.shared.check(userInitiated: true) }
                    Text(String(localized: "Once a day, the app asks GitHub whether a newer version is out; nothing about you is sent. If there is one, it asks before downloading. The installer is checked, then opens in Apple's Installer."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "About")) {
                Text(String(localized: "VoiceOver Audio Split \(Self.version)"))
                Text(String(localized: "Copyright 2026 Full Circle AT LLC. Free software under the GNU General Public License version 3."))
                    .font(.caption).foregroundStyle(.secondary)
                Link("Privacy policy", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split/blob/main/PRIVACY.md")!)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split")!)
                // Email needs no account; GitHub issues need a GitHub account.
                Link("Email a problem or an idea", destination: URL(string: "mailto:amena.thomas@fullcircleat.com?subject=VoiceOver%20Audio%20Split%20feedback")!)
                Link("Report it on GitHub (needs a GitHub account)", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split/issues/new/choose")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
    }

    /// "1.0 (202610221631)": the version and build, as shown in App Store Connect.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    /// The command's key; choosing a key another command uses swaps their keys.
    private func keyBinding(_ command: Command) -> Binding<Int64> {
        Binding(
            get: { KeyMap.key(for: command)?.code ?? Key.none },
            set: { newKey in
                var keys = preferences.customKeys
                let oldKey = KeyMap.key(for: command)?.code ?? Key.none
                if newKey != Key.none, let other = KeyMap.commandForKey[newKey], other != command {
                    keys[other.rawValue] = oldKey
                }
                keys[command.rawValue] = newKey
                // Keep only real changes, so restoring a default key leaves nothing saved.
                preferences.customKeys = keys.filter { id, key in key != (Command(rawValue: id)?.defaultKey ?? Key.none) }
                KeyMap.update(custom: preferences.customKeys, userCommands: preferences.userCommands)
            })
    }

    private func appPresetBinding(_ bundleID: String) -> Binding<String> {
        Binding(get: { preferences.appPresets[bundleID] ?? "" },
                set: { preferences.appPresets[bundleID] = $0 })
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }

    private var earBalanceTitle: String {
        let value = preferences.earBalance
        if value == 0 { return String(localized: "Ear balance: even") }
        return value > 0 ? String(localized: "Ear balance: right ear \(abs(value)) decibels louder")
                         : String(localized: "Ear balance: left ear \(abs(value)) decibels louder")
    }

    /// A binding to one field of an app rule, saved through Preferences.
    private func ruleBinding<T>(_ rule: AppRule, _ field: WritableKeyPath<AppRule, T>) -> Binding<T> {
        Binding(
            get: { (preferences.rule(for: rule.bundleID) ?? rule)[keyPath: field] },
            set: { value in
                var updated = preferences.rule(for: rule.bundleID) ?? rule
                updated[keyPath: field] = value
                // Keep the app listed even when everything is back to normal, until Reset.
                var rules = preferences.appRules.filter { $0.bundleID != rule.bundleID }
                rules.append(updated)
                preferences.appRules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            })
    }

    private var openApps: [CallApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> CallApp? in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return CallApp(name: name, bundleID: id)
            }
            .sorted { $0.name < $1.name }
    }

    /// Open apps that aren't already in the call list.
    private var addableApps: [CallApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> CallApp? in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return CallApp(name: name, bundleID: id)
            }
            .filter { app in !preferences.callApps.contains { $0.bundleID == app.bundleID } }
            .sorted { $0.name < $1.name }
    }
}
