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
            Section("Where sounds go") {
                Picker("Layout", selection: $preferences.layout) {
                    ForEach(Layout.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep other sounds in stereo", isOn: $preferences.stereoOthers)
                Text("Music keeps its stereo sound but leans toward its ear. Off mixes other sounds to mono, like JAWS.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Play speech on", selection: $preferences.speechDeviceUID) {
                    Text("Same device as other sounds").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                Text("Choose another device, such as AirPods, to hear VoiceOver privately while other sounds play on the current output.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh device list") { devices = outputDevices() }
            }

            Section("Volume") {
                Stepper("Change per key press: \(preferences.balanceStep) decibels",
                        value: $preferences.balanceStep, in: 1...6)
                Stepper("Largest difference: \(preferences.balanceLimit) decibels",
                        value: $preferences.balanceLimit, in: 6...30, step: 3)
                Toggle("Lower other sounds while VoiceOver speaks", isOn: $preferences.ducking)
                Stepper("Lower by: \(preferences.duckingAmount) decibels",
                        value: $preferences.duckingAmount, in: 3...30, step: 3)
                    .disabled(!preferences.ducking)
            }

            Section("Clearer speech and hearing") {
                Toggle("Speech clarity boost", isOn: $preferences.clarity)
                Text("Makes VoiceOver easier to understand over loud media, without just making it louder.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Even out loud media", isOn: $preferences.leveler)
                Text("Turns down sudden loud moments in videos, music and ads.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Volume limit", isOn: $preferences.volumeLimit)
                Stepper("Limit: \(-preferences.volumeLimitLevel) decibels below full volume",
                        value: $preferences.volumeLimitLevel, in: -24...(-1), step: 1)
                    .disabled(!preferences.volumeLimit)
                Text("Keeps all sound below this level to protect your hearing. It works on top of the Mac's volume.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("One ear", selection: $preferences.oneEar) {
                    ForEach(OneEar.allCases) { Text($0.title).tag($0) }
                }
                Text("For hearing in one ear: VoiceOver and every other sound are combined into that ear.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(earBalanceTitle, value: $preferences.earBalance, in: -12...12)
                Text("Makes one ear louder than the other, for people who hear less on one side.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Apps") {
                Text("Give an app its own volume, mute or ear. You can also hold the shortcut key and press equals, minus or zero to change the app in front.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.appRules) { rule in
                    VStack(alignment: .leading) {
                        Text(rule.name).font(.headline)
                        Stepper("\(rule.name) volume: \(Controller.describe(appVolume: rule.volume))",
                                value: ruleBinding(rule, \.volume), in: -30...6, step: 3)
                        Toggle("Mute \(rule.name)", isOn: ruleBinding(rule, \.muted))
                        Picker("\(rule.name) plays in", selection: ruleBinding(rule, \.ear)) {
                            ForEach(EarChoice.allCases) { Text($0.title).tag($0) }
                        }
                        Button("Reset \(rule.name)") {
                            preferences.appRules.removeAll { $0.bundleID == rule.bundleID }
                        }
                    }
                }
                HStack {
                    Picker("Add an app", selection: $ruleAppToAdd) {
                        Text("Choose an open app").tag("")
                        ForEach(openApps.filter { app in preferences.rule(for: app.bundleID) == nil }, id: \.bundleID) {
                            Text($0.name).tag($0.bundleID)
                        }
                    }
                    Button("Add") {
                        if let app = openApps.first(where: { $0.bundleID == ruleAppToAdd }) {
                            // Start at a slightly lower volume so the new rule takes effect.
                            preferences.setRule(AppRule(name: app.name, bundleID: app.bundleID, volume: -3))
                            ruleAppToAdd = ""
                        }
                    }
                    .disabled(ruleAppToAdd.isEmpty)
                }
            }

            Section("Presets") {
                Text("Hold the shortcut key and press a number to switch to a preset.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(preferences.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack {
                        Text(index < 9 ? "\(index + 1): \(preset.name)" : preset.name)
                        Spacer()
                        Button("Use \(preset.name)") { Controller.shared.applyPreset(preset) }
                        Button("Delete \(preset.name)") {
                            preferences.presets.removeAll { $0.id == preset.id }
                        }
                    }
                }
                HStack {
                    TextField("New preset name", text: $newPresetName)
                    Button("Save current settings") {
                        Controller.shared.saveCurrentAsPreset(named: newPresetName.trimmingCharacters(in: .whitespaces))
                        newPresetName = ""
                    }
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore default presets") { preferences.presets = Preset.defaults }
            }

            Section("Automatic presets") {
                Text("Switch to a preset whenever an app comes to the front, for example Meeting for Zoom.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.appPresets.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        Picker(appName(bundleID), selection: appPresetBinding(bundleID)) {
                            ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Button("Remove \(appName(bundleID))") { preferences.appPresets[bundleID] = nil }
                    }
                }
                HStack {
                    Picker("Add an app", selection: $presetAppToAdd) {
                        Text("Choose an open app").tag("")
                        ForEach(openApps.filter { preferences.appPresets[$0.bundleID] == nil }, id: \.bundleID) {
                            Text($0.name).tag($0.bundleID)
                        }
                    }
                    Button("Add") {
                        if let first = preferences.presets.first, !presetAppToAdd.isEmpty {
                            preferences.appPresets[presetAppToAdd] = first.id.uuidString
                            presetAppToAdd = ""
                        }
                    }
                    .disabled(presetAppToAdd.isEmpty || preferences.presets.isEmpty)
                }
                Picker("All other apps", selection: $preferences.otherAppsPreset) {
                    Text("Keep current settings").tag("")
                    ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                }
            }

            Section("Spoken events and clock") {
                Toggle("Say when a download finishes", isOn: $preferences.announceDownloads)
                Toggle("Say when headphones or speakers connect or disconnect", isOn: $preferences.announceDevices)
                Toggle("Say when the network connection drops or comes back", isOn: $preferences.announceNetwork)
                Toggle("Say when the battery is low, and when charging starts or stops", isOn: $preferences.announceBattery)
                Toggle("Say when the screen locks", isOn: $preferences.announceLock)
                Picker("Talking clock", selection: $preferences.clockInterval) {
                    Text("Off").tag(0)
                    Text("Every hour").tag(60)
                    Text("Every half hour").tag(30)
                    Text("Every quarter hour").tag(15)
                }
            }

            Section("Presets for websites") {
                Text("Switch to a preset on a website in Safari or Chrome, for example a quieter preset on youtube.com. The first time, your Mac asks to let VoiceOver Audio Split see which site is open.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.sitePresets.keys.sorted(), id: \.self) { site in
                    HStack {
                        Picker(site, selection: Binding(get: { preferences.sitePresets[site] ?? "" },
                                                        set: { preferences.sitePresets[site] = $0 })) {
                            ForEach(preferences.presets) { Text($0.name).tag($0.id.uuidString) }
                        }
                        Button("Remove \(site)") { preferences.sitePresets[site] = nil }
                    }
                }
                HStack {
                    TextField("Website, for example youtube.com", text: $newSite)
                    Button("Add") {
                        if let first = preferences.presets.first {
                            preferences.sitePresets[SitePresets.normalize(newSite)] = first.id.uuidString
                            newSite = ""
                        }
                    }
                    .disabled(SitePresets.normalize(newSite).isEmpty || preferences.presets.isEmpty)
                }
            }

            Section("Calls") {
                Picker("Call audio", selection: $preferences.callMode) {
                    ForEach(CallMode.allCases) { Text($0.title).tag($0) }
                }
                ForEach(preferences.callApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button("Remove \(app.name)") {
                            preferences.callApps.removeAll { $0 == app }
                        }
                    }
                }
                HStack {
                    Picker("Add a call app", selection: $appToAdd) {
                        Text("Choose an open app").tag("")
                        ForEach(addableApps, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
                    }
                    Button("Add") {
                        if let app = addableApps.first(where: { $0.bundleID == appToAdd }) {
                            preferences.callApps.append(app)
                            appToAdd = ""
                        }
                    }
                    .disabled(appToAdd.isEmpty)
                }
                Button("Restore default call apps") { preferences.callApps = CallApp.defaults }
            }

            Section("Keyboard and sounds") {
                Picker("Shortcut key", selection: $preferences.modifier) {
                    ForEach(ShortcutModifier.allCases) { Text($0.title).tag($0) }
                }
                Text("Hold it with a command's key below, or press the layer key first and then the command's key on its own. Digits 1 to 9 switch presets. The key of the same kind on the left keeps working normally.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Play a short tone with each change", isOn: $preferences.playTones)
                Toggle("Keep audio awake, so the first words VoiceOver says aren't cut off", isOn: $preferences.keepAudioAwake)
                Text("Plays silence so headphones and Bluetooth devices like AirPods don't go to sleep between phrases.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Beep each time VoiceOver would speak while it's silenced", isOn: $preferences.beepsWhenSilenced)
                Toggle("Say what you copy", isOn: $preferences.announceClipboard)
                Toggle("Use a nearby iPhone as the camera when available", isOn: $preferences.preferIPhoneCamera)
                Toggle("Keep speech history", isOn: $preferences.speechHistory)
                Text("Keeps a list of what VoiceOver says, in memory only, to review and copy from the Speech History window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Low vision") {
                Picker("Colors for large print", selection: $preferences.readingTheme) {
                    ForEach(ReadingTheme.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Caption text size: \(preferences.captionSize)", value: $preferences.captionSize, in: 20...96, step: 4)
                Toggle("Show large-print captions of what VoiceOver says", isOn: Binding(
                    get: { preferences.captionsOn },
                    set: { on in if on != Captions.isShowing { Controller.shared.toggleCaptions() } }))
                Toggle("Show a focus frame around the VoiceOver cursor", isOn: Binding(
                    get: { preferences.focusFrameOn },
                    set: { on in if on != FocusFrame.isShowing { Controller.shared.toggleFocusFrame() } }))
                Picker("Focus frame color", selection: $preferences.focusFrameColor) {
                    ForEach(FrameColor.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Focus frame thickness: \(preferences.focusFrameThickness)",
                        value: $preferences.focusFrameThickness, in: 2...24, step: 2)
                Toggle("Flash the focus frame when it moves", isOn: $preferences.focusFrameFlash)
                Stepper("Doc Reader text size: \(preferences.readerFontSize)", value: $preferences.readerFontSize,
                        in: 14...96, step: 4)
            }
            .onChange(of: preferences.focusFrameColor) { FocusFrame.refresh() }
            .onChange(of: preferences.focusFrameThickness) { FocusFrame.refresh() }

            UserCommandsSection()

            Section("Command keys") {
                ForEach(Command.allCases) { command in
                    Picker(command.title, selection: keyBinding(command)) {
                        Text("No key").tag(Key.none)
                        ForEach(Key.assignable) { Text($0.name).tag($0.code) }
                    }
                }
                Button("Restore default keys") { preferences.customKeys = [:] }
                Text("Choosing a key another command uses swaps the two commands' keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Assistant and image descriptions") {
                Text(hasAPIKey ? "An Anthropic API key is saved in your Keychain." :
                        "The assistant and image descriptions use Claude. Paste an API key from console.anthropic.com. Requests are billed to that account.")
                SecureField(hasAPIKey ? "Replace API key" : "API key", text: $apiKey)
                HStack {
                    Button("Save key") {
                        APIKey.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        apiKey = ""
                        hasAPIKey = APIKey.current != nil
                        Announcer.say("Key saved")
                    }
                    .disabled(apiKey.isEmpty)
                    Button("Remove key") {
                        APIKey.save("")
                        hasAPIKey = false
                        Announcer.say("Key removed")
                    }
                    .disabled(!hasAPIKey)
                }
                Toggle("Allow sending pictures of the screen for image descriptions", isOn: $preferences.allowImageUpload)
                Text("Only the item under the VoiceOver cursor is sent, and only when you ask for a description.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Backup and diagnostics") {
                HStack {
                    Button("Export Settings…") { SettingsTransfer.export() }
                    Button("Import Settings…") { SettingsTransfer.importFromFile() }
                }
                Button("Save a Diagnostics Report…") { Diagnostics.save() }
                Text("Export saves your keys, presets, app and website rules and other settings in one file, to back up or set up another Mac. Diagnostics reports include the app's recent log for bug reports; never your API key or files.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                Text("VoiceOver Audio Split \(Self.version)")
                Text("Copyright 2026 Full Circle AT LLC. Free software under the GNU General Public License version 3.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Privacy policy", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split/blob/main/PRIVACY.md")!)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split")!)
                Link("Report a problem or suggest an idea", destination: URL(string: "https://github.com/amenathomas1997/voiceover-audio-split/issues/new/choose")!)
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
        if value == 0 { return "Ear balance: even" }
        return "Ear balance: \(value > 0 ? "right" : "left") ear \(abs(value)) decibels louder"
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
