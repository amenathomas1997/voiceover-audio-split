// Extend.swift — making the app the user's own:
//   * Your commands: run any AppleScript (placed in the app's scripts folder) or
//     any Shortcut from the Shortcuts app, from a key, the menu or the palette
//   * Export and import settings: keys, presets, app and website rules and
//     everything else in one file, to back up, move to a new Mac, or share

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum UserCommands {
    /// ~/Library/Application Scripts/<app ID>: the one folder a sandboxed app may run scripts from.
    static var scriptsFolder: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    /// AppleScripts in the scripts folder.
    static func availableScripts() -> [String] {
        guard let folder = scriptsFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { ["scpt", "applescript", "scptd"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }

    static func run(_ id: UUID) {
        guard let command = Preferences.shared.userCommands.first(where: { $0.id == id }) else { return }
        Tones.play(.status)
        switch command.kind {
        case .appleScript:
            guard let url = scriptsFolder?.appendingPathComponent(command.target),
                  let task = try? NSUserAppleScriptTask(url: url) else {
                return Announcer.say(String(localized: "Couldn't find the script \(command.target)"))
            }
            task.execute(withAppleEvent: nil) { result, error in
                DispatchQueue.main.async {
                    if let error {
                        log("Script \(command.name) failed: \(error.localizedDescription)")
                        Announcer.say(String(localized: "\(command.name) failed"))
                    } else if let text = result?.stringValue, !text.isEmpty {
                        // A script that returns text has it spoken.
                        Announcer.say(text)
                    }
                }
            }
        case .shortcut:
            var url = URLComponents(string: "shortcuts://run-shortcut")!
            url.queryItems = [.init(name: "name", value: command.target)]
            if let address = url.url { NSWorkspace.shared.open(address) }
        }
    }

    static func openScriptsFolder() {
        guard let folder = scriptsFolder else { return Announcer.say(String(localized: "The scripts folder isn't available")) }
        NSWorkspace.shared.open(folder)
    }
}

struct UserCommandsSection: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var scripts = UserCommands.availableScripts()
    @State private var scriptToAdd = ""
    @State private var shortcutName = ""

    var body: some View {
        Section(String(localized: "Your commands")) {
            Text(String(localized: "Run your own AppleScripts or Shortcuts from a key, the menu or the command palette. A script that returns text has it spoken."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(preferences.userCommands) { command in
                HStack {
                    Picker(command.kind == .appleScript ? String(localized: "\(command.name) (script)") : String(localized: "\(command.name) (shortcut)"),
                           selection: keyBinding(command)) {
                        Text(String(localized: "No key")).tag(Key.none)
                        ForEach(freeKeys(for: command)) { Text($0.name).tag($0.code) }
                    }
                    Button(String(localized: "Remove \(command.name)")) {
                        preferences.userCommands.removeAll { $0.id == command.id }
                        refreshKeys()
                    }
                }
            }
            HStack {
                Picker(String(localized: "Add a script"), selection: $scriptToAdd) {
                    Text(scripts.isEmpty ? String(localized: "No scripts in the folder yet") : String(localized: "Choose a script")).tag("")
                    ForEach(scripts, id: \.self) { Text($0).tag($0) }
                }
                Button(String(localized: "Add")) {
                    let name = (scriptToAdd as NSString).deletingPathExtension
                    preferences.userCommands.append(UserCommand(name: name, kind: .appleScript, target: scriptToAdd))
                    scriptToAdd = ""
                }
                .disabled(scriptToAdd.isEmpty)
            }
            HStack {
                Button(String(localized: "Open Scripts Folder")) { UserCommands.openScriptsFolder() }
                Button(String(localized: "Refresh Script List")) { scripts = UserCommands.availableScripts() }
            }
            HStack {
                TextField(String(localized: "Shortcut name, exactly as in the Shortcuts app"), text: $shortcutName)
                Button(String(localized: "Add Shortcut")) {
                    let name = shortcutName.trimmingCharacters(in: .whitespaces)
                    preferences.userCommands.append(UserCommand(name: name, kind: .shortcut, target: name))
                    shortcutName = ""
                }
                .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Keys not used by a built-in command or another of the user's commands.
    private func freeKeys(for command: UserCommand) -> [Key] {
        let taken = Set(KeyMap.commandForKey.keys).union(
            preferences.userCommands.filter { $0.id != command.id }.compactMap(\.key))
        return Key.assignable.filter { !taken.contains($0.code) }
    }

    private func keyBinding(_ command: UserCommand) -> Binding<Int64> {
        Binding(
            get: { command.key ?? Key.none },
            set: { key in
                guard let index = preferences.userCommands.firstIndex(where: { $0.id == command.id }) else { return }
                preferences.userCommands[index].key = key == Key.none ? nil : key
                refreshKeys()
            })
    }

    private func refreshKeys() {
        KeyMap.update(custom: preferences.customKeys, userCommands: preferences.userCommands)
    }
}

// MARK: - Export and import

enum SettingsTransfer {
    /// Settings that make sense on another Mac. Left out: permissions and consent
    /// (like allowing image uploads), setup progress, and this Mac's microphone use (voice commands).
    static let portableKeys = [
        "layout", "stereoOthers", "ducking", "duckingAmount", "speechDeviceUID", "callMode", "callApps",
        "playTones", "modifier", "balanceStep", "balanceLimit", "clarity", "leveler", "volumeLimit",
        "volumeLimitLevel", "oneEar", "earBalance", "appRules", "presets", "speechHistory", "customKeys",
        "appPresets", "otherAppsPreset", "readingTheme", "readerFontSize", "readerLineSpacing", "readerRate",
        "captionsOn", "captionSize", "focusFrameOn", "focusFrameColor", "focusFrameThickness", "focusFrameFlash",
        "newsFeeds", "keepAudioAwake", "sitePresets", "announceDownloads", "announceDevices", "announceNetwork",
        "announceBattery", "announceLock", "clockInterval", "userCommands", "beepsWhenSilenced",
        "announceClipboard", "translateTarget", "preferIPhoneCamera", "balance", "lastSide",
        "announceCamera", "announceMicrophone", "customLabels", "placeMarkers", "typingBest", "typingSound", "lessonsDone", "lessonsMissed", "lessonSchedule", "lessonChallengeBest", "lessonMode",
        "practiceLearnMode", "typingSayEachKey", "checkForUpdates",
        "hearingProfileOn", "hearingLeft", "hearingRight", "confirmSoundChanges", "aiProvider", "autoDescribeImages", "recordMicrophone",
        "meetingChatAnnounce", "clipboardHistory", "reminderNotifications", "brailleGrade", "objectFinderCameraFacesYou",
    ]

    static func exportData() throws -> Data {
        let all = UserDefaults.standard.dictionaryRepresentation()
        var settings = all.filter { portableKeys.contains($0.key) }
        settings["formatVersion"] = 1
        return try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
    }

    /// Applies settings from a file; returns how many were applied.
    @discardableResult
    static func importData(_ data: Data) throws -> Int {
        guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              settings["formatVersion"] != nil else { throw CocoaError(.fileReadCorruptFile) }
        let applied = settings.filter { portableKeys.contains($0.key) }
        for (key, value) in applied { UserDefaults.standard.set(value, forKey: key) }
        return applied.count
    }

    @MainActor
    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "VoiceOver Audio Split settings.voasettings")
        panel.allowedContentTypes = [UTType(filenameExtension: "voasettings") ?? .propertyList]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportData().write(to: url)
            Announcer.say(String(localized: "Settings saved to \(url.lastPathComponent)"))
        } catch {
            Announcer.say(String(localized: "Couldn't save the settings"))
        }
    }

    @MainActor
    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "voasettings") ?? .propertyList, .propertyList]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try importData(Data(contentsOf: url))
            Announcer.say(String(localized: "Imported \(count) settings. Restarting VoiceOver Audio Split to use them."))
            // Settings are read at launch, so restart to apply them all consistently.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Relaunch.now() }
        } catch {
            Announcer.say(String(localized: "That file isn't a VoiceOver Audio Split settings file"))
        }
    }
}

/// Restarts the app: starts a new copy, then quits this one.
enum Relaunch {
    @MainActor
    static func now() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                // Only quit once the new copy is running; otherwise the shortcuts would just vanish.
                guard error == nil else {
                    return Announcer.say(String(localized: "Settings imported. Quit VoiceOver Audio Split and open it again to use them."))
                }
                NSApp.terminate(nil)
            }
        }
    }
}
