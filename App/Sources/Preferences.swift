// Preferences.swift — every user setting, saved in UserDefaults. The settings
// window binds to these directly; each change is pushed to the Controller.

import Combine
import Foundation

/// Where speech and other sounds go when both play on the same device.
enum Layout: String, Codable, CaseIterable, Identifiable {
    /// Speech in one ear, other sounds in the other (like JAWS).
    case opposite
    /// Speech in both ears, other sounds in one ear.
    case speechBoth
    /// Other sounds in both ears, speech in one ear.
    case othersBoth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opposite: String(localized: "Speech in one ear, other sounds in the other")
        case .speechBoth: String(localized: "Speech in both ears, other sounds in one ear")
        case .othersBoth: String(localized: "Other sounds in both ears, speech in one ear")
        }
    }
}

/// How audio from call apps (Zoom, Teams, FaceTime…) is handled.
enum CallMode: String, Codable, CaseIterable, Identifiable {
    /// Treated like any other sound.
    case split
    /// Left alone: plays normally in both ears.
    case bothEars
    /// Goes to the speech ear along with VoiceOver.
    case withSpeech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split: String(localized: "Split like other sounds")
        case .bothEars: String(localized: "Keep in both ears")
        case .withSpeech: String(localized: "Put with VoiceOver speech")
        }
    }
}

/// The right-hand modifier key that triggers the shortcuts.
enum ShortcutModifier: String, CaseIterable, Identifiable {
    case option, command, control, shift

    var id: String { rawValue }
    var title: String {
        switch self {
        case .option: String(localized: "Right Option")
        case .command: String(localized: "Right Command")
        case .control: String(localized: "Right Control")
        case .shift: String(localized: "Right Shift")
        }
    }
}

/// An app whose audio counts as a call. Matched by bundle ID prefix, because
/// call apps often play audio from helper processes (us.zoom.caphost…).
struct CallApp: Codable, Hashable, Identifiable {
    var name: String
    var bundleID: String
    var id: String { bundleID }

    static let defaults: [CallApp] = [
        CallApp(name: String(localized: "Zoom"), bundleID: "us.zoom"),
        CallApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams"),
        CallApp(name: "FaceTime", bundleID: "com.apple.FaceTime"),
        CallApp(name: "FaceTime and phone calls", bundleID: "com.apple.avconferenced"),
        CallApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        CallApp(name: "Discord", bundleID: "com.hnc.Discord"),
        CallApp(name: "Webex", bundleID: "Cisco-Systems.Spark"),
        CallApp(name: "Skype", bundleID: "com.skype"),
    ]
}

/// Which ear an app plays in.
enum EarChoice: String, Codable, CaseIterable, Identifiable {
    /// Goes wherever other sounds go (follows the split).
    case follow, left, right, both
    /// Anywhere from left to right, set with the app's position.
    case position

    var id: String { rawValue }

    var title: String {
        switch self {
        case .follow: String(localized: "Same as other sounds")
        case .left: String(localized: "Left ear")
        case .right: String(localized: "Right ear")
        case .both: String(localized: "Both ears")
        case .position: String(localized: "A position you choose")
        }
    }
}

/// Play everything in one ear, for people who hear in only one ear.
enum OneEar: String, Codable, CaseIterable, Identifiable {
    case off, left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .left: String(localized: "Everything in the left ear")
        case .right: String(localized: "Everything in the right ear")
        }
    }
}

/// Volume, mute and ear for one app. Matched by bundle ID prefix, like call apps.
struct AppRule: Codable, Hashable, Identifiable {
    var name: String
    var bundleID: String
    /// Decibels relative to normal: negative is quieter.
    var volume: Int = 0
    var muted = false
    var ear: EarChoice = .follow
    /// With `ear` set to position: -100 is fully left, 0 the middle, 100 fully right.
    var position = 0
    /// Bass and treble, in decibels.
    var bass = 0
    var treble = 0

    var id: String { bundleID }
    /// A rule with nothing changed can be dropped.
    var isDefault: Bool { volume == 0 && !muted && ear == .follow && bass == 0 && treble == 0 }

    init(name: String, bundleID: String, volume: Int = 0, muted: Bool = false, ear: EarChoice = .follow) {
        self.name = name
        self.bundleID = bundleID
        self.volume = volume
        self.muted = muted
        self.ear = ear
    }

    /// Rules saved by earlier versions have no position or tone.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        bundleID = try values.decode(String.self, forKey: .bundleID)
        volume = try values.decodeIfPresent(Int.self, forKey: .volume) ?? 0
        muted = try values.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        ear = try values.decodeIfPresent(EarChoice.self, forKey: .ear) ?? .follow
        position = try values.decodeIfPresent(Int.self, forKey: .position) ?? 0
        bass = try values.decodeIfPresent(Int.self, forKey: .bass) ?? 0
        treble = try values.decodeIfPresent(Int.self, forKey: .treble) ?? 0
    }
}

/// A saved combination of settings, applied with the shortcut key + a number.
struct Preset: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// "off", "left" or "right".
    var split: String
    var balance: Int
    var layout: Layout
    var stereoOthers: Bool
    var ducking: Bool
    var duckingAmount: Int
    var callMode: CallMode
    var clarity: Bool
    var leveler: Bool
    var volumeLimit: Bool
    var volumeLimitLevel: Int
    var oneEar: OneEar
    var earBalance: Int

    static let defaults: [Preset] = [
        Preset(name: String(localized: "Meeting"), split: "left", balance: 6, layout: .opposite, stereoOthers: false, ducking: false,
               duckingAmount: 10, callMode: .bothEars, clarity: true, leveler: true, volumeLimit: false,
               volumeLimitLevel: -6, oneEar: .off, earBalance: 0),
        Preset(name: String(localized: "Music"), split: "off", balance: 0, layout: .opposite, stereoOthers: true, ducking: true,
               duckingAmount: 9, callMode: .split, clarity: false, leveler: false, volumeLimit: false,
               volumeLimitLevel: -6, oneEar: .off, earBalance: 0),
        Preset(name: String(localized: "Focus"), split: "left", balance: 9, layout: .opposite, stereoOthers: false, ducking: true,
               duckingAmount: 15, callMode: .split, clarity: true, leveler: true, volumeLimit: false,
               volumeLimitLevel: -6, oneEar: .off, earBalance: 0),
    ]
}

/// High-contrast color pairs for large-print text (Doc Reader, captions).
enum ReadingTheme: String, Codable, CaseIterable, Identifiable {
    case blackOnWhite, whiteOnBlack, yellowOnBlack, blackOnYellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blackOnWhite: String(localized: "Black on white")
        case .whiteOnBlack: String(localized: "White on black")
        case .yellowOnBlack: String(localized: "Yellow on black")
        case .blackOnYellow: String(localized: "Black on yellow")
        }
    }
}

/// A command the user adds: one of their AppleScripts or a Shortcut from the Shortcuts app.
struct UserCommand: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case appleScript, shortcut }

    var id = UUID()
    var name: String
    var kind: Kind
    /// The script's file name in the app's scripts folder, or the Shortcut's name.
    var target: String
    var key: Int64?
}

/// Colors for the focus frame.
enum FrameColor: String, Codable, CaseIterable, Identifiable {
    case yellow, red, magenta, cyan, green, orange

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let store = UserDefaults.standard

    /// Called after any change, so the Controller can apply it.
    var onChange: (() -> Void)?

    @Published var layout: Layout { didSet { save(layout.rawValue, "layout") } }
    /// Keep other sounds in stereo instead of mixing them to mono.
    @Published var stereoOthers: Bool { didSet { save(stereoOthers, "stereoOthers") } }
    /// Lower other sounds while VoiceOver is speaking.
    @Published var ducking: Bool { didSet { save(ducking, "ducking") } }
    /// How much to lower other sounds while VoiceOver speaks, in decibels.
    @Published var duckingAmount: Int { didSet { save(duckingAmount, "duckingAmount") } }
    /// Output device UID for speech, or "" to use the same device as other sounds.
    @Published var speechDeviceUID: String { didSet { save(speechDeviceUID, "speechDeviceUID") } }
    @Published var callMode: CallMode { didSet { save(callMode.rawValue, "callMode") } }
    @Published var callApps: [CallApp] { didSet { save(try? JSONEncoder().encode(callApps), "callApps") } }
    @Published var playTones: Bool { didSet { save(playTones, "playTones") } }
    @Published var modifier: ShortcutModifier { didSet { save(modifier.rawValue, "modifier") } }
    /// Decibels per Up / Down press.
    @Published var balanceStep: Int { didSet { save(balanceStep, "balanceStep") } }
    /// Largest balance either way, in decibels.
    @Published var balanceLimit: Int { didSet { save(balanceLimit, "balanceLimit") } }
    @Published var finishedSetup: Bool { didSet { save(finishedSetup, "finishedSetup") } }

    /// Make VoiceOver speech easier to understand over other sounds.
    @Published var clarity: Bool { didSet { save(clarity, "clarity") } }
    /// Even out sudden loud moments in other sounds.
    @Published var leveler: Bool { didSet { save(leveler, "leveler") } }
    /// Keep the overall output below a set level.
    @Published var volumeLimit: Bool { didSet { save(volumeLimit, "volumeLimit") } }
    /// The limit, in decibels below full scale (for example -6).
    @Published var volumeLimitLevel: Int { didSet { save(volumeLimitLevel, "volumeLimitLevel") } }
    @Published var oneEar: OneEar { didSet { save(oneEar.rawValue, "oneEar") } }
    /// Decibels: positive makes the right ear louder, negative the left.
    @Published var earBalance: Int { didSet { save(earBalance, "earBalance") } }
    @Published var appRules: [AppRule] { didSet { save(try? JSONEncoder().encode(appRules), "appRules") } }
    @Published var presets: [Preset] { didSet { save(try? JSONEncoder().encode(presets), "presets") } }
    /// Keys changed from their defaults in Settings, by command ID.
    @Published var customKeys: [String: Int64] { didSet { save(customKeys, "customKeys") } }
    /// Preset to switch to when an app comes to the front, by bundle ID (preset IDs as strings).
    @Published var appPresets: [String: String] { didSet { save(appPresets, "appPresets") } }
    /// Preset for apps without their own, or "" for none.
    @Published var otherAppsPreset: String { didSet { save(otherAppsPreset, "otherAppsPreset") } }
    /// Allowed sending pictures of the screen to Anthropic for descriptions.
    @Published var allowImageUpload: Bool { didSet { save(allowImageUpload, "allowImageUpload") } }
    @Published var readingTheme: ReadingTheme { didSet { save(readingTheme.rawValue, "readingTheme") } }
    @Published var readerFontSize: Int { didSet { save(readerFontSize, "readerFontSize") } }
    @Published var readerLineSpacing: Int { didSet { save(readerLineSpacing, "readerLineSpacing") } }
    /// Words per minute for the Doc Reader, as a fraction of the system range (0 to 1).
    @Published var readerRate: Double { didSet { save(readerRate, "readerRate") } }
    @Published var captionsOn: Bool { didSet { save(captionsOn, "captionsOn") } }
    @Published var captionSize: Int { didSet { save(captionSize, "captionSize") } }
    @Published var focusFrameOn: Bool { didSet { save(focusFrameOn, "focusFrameOn") } }
    @Published var focusFrameColor: FrameColor { didSet { save(focusFrameColor.rawValue, "focusFrameColor") } }
    @Published var focusFrameThickness: Int { didSet { save(focusFrameThickness, "focusFrameThickness") } }
    @Published var focusFrameFlash: Bool { didSet { save(focusFrameFlash, "focusFrameFlash") } }
    /// Play silence so headphones and Bluetooth devices don't sleep and clip VoiceOver's first words.
    @Published var keepAudioAwake: Bool { didSet { save(keepAudioAwake, "keepAudioAwake") } }
    /// Preset to switch to on a website, by host name such as "youtube.com" (preset IDs as strings).
    @Published var sitePresets: [String: String] { didSet { save(sitePresets, "sitePresets") } }
    @Published var announceDownloads: Bool { didSet { save(announceDownloads, "announceDownloads") } }
    @Published var announceDevices: Bool { didSet { save(announceDevices, "announceDevices") } }
    @Published var announceNetwork: Bool { didSet { save(announceNetwork, "announceNetwork") } }
    @Published var announceBattery: Bool { didSet { save(announceBattery, "announceBattery") } }
    @Published var announceLock: Bool { didSet { save(announceLock, "announceLock") } }
    /// Talking clock: minutes between announcements (0 off, 15, 30 or 60).
    @Published var clockInterval: Int { didSet { save(clockInterval, "clockInterval") } }
    @Published var userCommands: [UserCommand] { didSet { save(try? JSONEncoder().encode(userCommands), "userCommands") } }
    /// While VoiceOver is silenced, beep each time it would have spoken.
    @Published var beepsWhenSilenced: Bool { didSet { save(beepsWhenSilenced, "beepsWhenSilenced") } }
    /// Speak what was just copied.
    @Published var announceClipboard: Bool { didSet { save(announceClipboard, "announceClipboard") } }
    /// Language code for Translate, such as "es".
    @Published var translateTarget: String { didSet { save(translateTarget, "translateTarget") } }
    /// Prefer an iPhone (Continuity Camera) for the camera tools when one is nearby.
    @Published var preferIPhoneCamera: Bool { didSet { save(preferIPhoneCamera, "preferIPhoneCamera") } }
    /// News feeds for the audio hub (RSS addresses).
    @Published var newsFeeds: [String] { didSet { save(newsFeeds, "newsFeeds") } }
    /// Keep a list of what VoiceOver says, to review with the history window.
    @Published var speechHistory: Bool { didSet { save(speechHistory, "speechHistory") } }
    /// Say when another app turns the camera or microphone on or off.
    @Published var announceCamera: Bool { didSet { save(announceCamera, "announceCamera") } }
    @Published var announceMicrophone: Bool { didSet { save(announceMicrophone, "announceMicrophone") } }
    @Published var customLabels: [CustomLabel] { didSet { save(try? JSONEncoder().encode(customLabels), "customLabels") } }
    @Published var placeMarkers: [PlaceMarker] { didSet { save(try? JSONEncoder().encode(placeMarkers), "placeMarkers") } }
    /// The typing trainer's best words per minute, by lesson.
    @Published var typingBest: [String: Int] { didSet { save(typingBest, "typingBest") } }
    /// The typing trainer's sound for a key typed right (a TypingSound).
    @Published var typingSound: String { didSet { save(typingSound, "typingSound") } }

    private init() {
        store.register(defaults: [
            "layout": Layout.opposite.rawValue, "stereoOthers": false, "ducking": false, "duckingAmount": 10,
            "speechDeviceUID": "", "callMode": CallMode.split.rawValue, "playTones": true,
            "modifier": ShortcutModifier.option.rawValue, "balanceStep": 3, "balanceLimit": 18,
            "finishedSetup": false, "clarity": false, "leveler": false, "volumeLimit": false,
            "volumeLimitLevel": -6, "oneEar": OneEar.off.rawValue, "earBalance": 0, "speechHistory": true,
            "readingTheme": ReadingTheme.yellowOnBlack.rawValue, "readerFontSize": 32, "readerLineSpacing": 10,
            "readerRate": 0.5, "captionsOn": false, "captionSize": 40, "focusFrameOn": false,
            "focusFrameColor": FrameColor.yellow.rawValue, "focusFrameThickness": 8, "focusFrameFlash": true,
            "newsFeeds": ["https://feeds.bbci.co.uk/news/rss.xml", "https://feeds.npr.org/1001/rss.xml"],
            "keepAudioAwake": false, "announceDownloads": true, "announceDevices": true,
            "announceNetwork": true, "announceBattery": true, "announceLock": false, "clockInterval": 0,
            "beepsWhenSilenced": true, "announceClipboard": false, "translateTarget": "es", "preferIPhoneCamera": true,
            "announceCamera": true, "announceMicrophone": true,
        ])
        layout = Layout(rawValue: store.string(forKey: "layout") ?? "") ?? .opposite
        stereoOthers = store.bool(forKey: "stereoOthers")
        ducking = store.bool(forKey: "ducking")
        duckingAmount = store.integer(forKey: "duckingAmount")
        speechDeviceUID = store.string(forKey: "speechDeviceUID") ?? ""
        callMode = CallMode(rawValue: store.string(forKey: "callMode") ?? "") ?? .split
        callApps = store.data(forKey: "callApps").flatMap { try? JSONDecoder().decode([CallApp].self, from: $0) }
            ?? CallApp.defaults
        playTones = store.bool(forKey: "playTones")
        modifier = ShortcutModifier(rawValue: store.string(forKey: "modifier") ?? "") ?? .option
        balanceStep = store.integer(forKey: "balanceStep")
        balanceLimit = store.integer(forKey: "balanceLimit")
        finishedSetup = store.bool(forKey: "finishedSetup")
        clarity = store.bool(forKey: "clarity")
        leveler = store.bool(forKey: "leveler")
        volumeLimit = store.bool(forKey: "volumeLimit")
        volumeLimitLevel = store.integer(forKey: "volumeLimitLevel")
        oneEar = OneEar(rawValue: store.string(forKey: "oneEar") ?? "") ?? .off
        earBalance = store.integer(forKey: "earBalance")
        appRules = store.data(forKey: "appRules").flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? []
        speechHistory = store.bool(forKey: "speechHistory")
        customKeys = (store.dictionary(forKey: "customKeys") as? [String: Int64])
            ?? (store.dictionary(forKey: "customKeys") as? [String: Int])?.mapValues(Int64.init) ?? [:]
        appPresets = store.dictionary(forKey: "appPresets") as? [String: String] ?? [:]
        otherAppsPreset = store.string(forKey: "otherAppsPreset") ?? ""
        allowImageUpload = store.bool(forKey: "allowImageUpload")
        readingTheme = ReadingTheme(rawValue: store.string(forKey: "readingTheme") ?? "") ?? .yellowOnBlack
        readerFontSize = store.integer(forKey: "readerFontSize")
        readerLineSpacing = store.integer(forKey: "readerLineSpacing")
        readerRate = store.double(forKey: "readerRate")
        captionsOn = store.bool(forKey: "captionsOn")
        captionSize = store.integer(forKey: "captionSize")
        focusFrameOn = store.bool(forKey: "focusFrameOn")
        focusFrameColor = FrameColor(rawValue: store.string(forKey: "focusFrameColor") ?? "") ?? .yellow
        focusFrameThickness = store.integer(forKey: "focusFrameThickness")
        focusFrameFlash = store.bool(forKey: "focusFrameFlash")
        newsFeeds = store.stringArray(forKey: "newsFeeds") ?? []
        keepAudioAwake = store.bool(forKey: "keepAudioAwake")
        announceDownloads = store.bool(forKey: "announceDownloads")
        announceDevices = store.bool(forKey: "announceDevices")
        announceNetwork = store.bool(forKey: "announceNetwork")
        announceBattery = store.bool(forKey: "announceBattery")
        announceLock = store.bool(forKey: "announceLock")
        clockInterval = store.integer(forKey: "clockInterval")
        userCommands = store.data(forKey: "userCommands").flatMap { try? JSONDecoder().decode([UserCommand].self, from: $0) } ?? []
        beepsWhenSilenced = store.bool(forKey: "beepsWhenSilenced")
        announceClipboard = store.bool(forKey: "announceClipboard")
        translateTarget = store.string(forKey: "translateTarget") ?? "es"
        preferIPhoneCamera = store.bool(forKey: "preferIPhoneCamera")
        announceCamera = store.bool(forKey: "announceCamera")
        announceMicrophone = store.bool(forKey: "announceMicrophone")
        customLabels = store.data(forKey: "customLabels").flatMap { try? JSONDecoder().decode([CustomLabel].self, from: $0) } ?? []
        typingBest = store.dictionary(forKey: "typingBest") as? [String: Int] ?? [:]
        typingSound = store.string(forKey: "typingSound") ?? TypingSound.click.rawValue
        placeMarkers = store.data(forKey: "placeMarkers").flatMap { try? JSONDecoder().decode([PlaceMarker].self, from: $0) } ?? []
        sitePresets = store.dictionary(forKey: "sitePresets") as? [String: String] ?? [:]
        presets = store.data(forKey: "presets").flatMap { try? JSONDecoder().decode([Preset].self, from: $0) }
            ?? Preset.defaults
    }

    func rule(for bundleID: String) -> AppRule? {
        appRules.first { $0.bundleID == bundleID }
    }

    /// Adds, changes or (when back to normal) removes an app's rule.
    func setRule(_ rule: AppRule) {
        var rules = appRules.filter { $0.bundleID != rule.bundleID }
        if !rule.isDefault { rules.append(rule) }
        appRules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var changePending = false

    /// Saves a setting. Several changes in a row (applying a preset) are
    /// reported to the Controller once.
    private func save(_ value: Any?, _ key: String) {
        store.set(value, forKey: key)
        guard !changePending else { return }
        changePending = true
        DispatchQueue.main.async {
            self.changePending = false
            self.onChange?()
        }
    }
}
