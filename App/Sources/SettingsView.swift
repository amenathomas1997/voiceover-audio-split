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
Text("Hold it with: arrow keys for the split and volume, Space to hear what is on, M for the menu, Q to quiet everything but VoiceOver, W to hear what is playing, equals, minus and zero for the app in front, D for the next output device, X to mute the microphone, and 1 to 9 for presets. The key of the same kind on the left keeps working normally.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Play a short tone with each change", isOn: $preferences.playTones)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
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
