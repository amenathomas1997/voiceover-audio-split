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

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    /// Development builds only: tries the Mac-wide controls inside the sandbox
    /// and puts everything back. Run with: open -a <app> --args --self-test
    private func selfTest() {
        log("Self-test: playing = \(AudioSystem.appsPlaying())")
        log("Self-test: output devices = \(outputDevices().map(\.name))")
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

    private static func arrow(_ key: Int) -> String { String(Character(UnicodeScalar(key)!)) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let side = controller.activeSide

        // Split
        let status = NSMenuItem(title: controller.describeSplit(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        add(to: menu, "Speech Left", key: Self.arrow(NSLeftArrowFunctionKey), checked: side == .left) { $0.setSide(.left) }
        add(to: menu, "Speech Right", key: Self.arrow(NSRightArrowFunctionKey), checked: side == .right) { $0.setSide(.right) }
        add(to: menu, "Audio Split Off", checked: side == nil) { $0.setSide(nil) }
        add(to: menu, "What's On", key: " ") { $0.announceStatus() }
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
        add(to: menu, "Speech Louder", key: Self.arrow(NSUpArrowFunctionKey)) { [preferences] in
            $0.changeBalance(by: preferences.balanceStep)
        }
        add(to: menu, "Other Sounds Louder", key: Self.arrow(NSDownArrowFunctionKey)) { [preferences] in
            $0.changeBalance(by: -preferences.balanceStep)
        }
        add(to: menu, "Reset Volume Balance") { $0.resetBalance() }
        add(to: menu, "Quiet Everything But VoiceOver", key: "q", checked: controller.quietAll) { $0.toggleQuiet() }
        add(to: menu, "Lower Other Sounds While VoiceOver Speaks", checked: preferences.ducking) { [preferences] _ in
            preferences.ducking.toggle()
            Announcer.say(preferences.ducking ? "Other sounds lower while VoiceOver speaks" : "Other sounds stay at the same volume")
        }
        menu.addItem(.separator())

        // Apps
        let appName = controller.frontAppName ?? "Front App"
        add(to: menu, "\(appName) Louder", key: "=") { $0.changeFrontAppVolume(by: 3) }
        add(to: menu, "\(appName) Quieter", key: "-") { $0.changeFrontAppVolume(by: -3) }
        add(to: menu, "Mute \(appName)", key: "0", checked: controller.frontAppMuted) { $0.toggleFrontAppMute() }
        add(to: menu, "What's Playing", key: "w") { $0.announcePlaying() }
        menu.addItem(.separator())

        // Devices
        add(to: menu, "Next Output Device", key: "d") { $0.nextOutputDevice() }
        add(to: menu, "Mute Microphone", key: "x", checked: AudioSystem.isMicMuted) { $0.toggleMicrophone() }
        menu.addItem(.separator())

        // Presets, hearing and clarity
        let presetsMenu = submenu(in: menu, "Presets")
        for (index, preset) in preferences.presets.enumerated() {
            add(to: presetsMenu, preset.name, key: index < 9 ? "\(index + 1)" : nil) { $0.applyPreset(preset) }
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

    /// Adds an item; `key` shows the shortcut (chosen modifier + key) beside it.
    private func add(to menu: NSMenu, _ title: String, key: String? = nil, checked: Bool = false,
                     action: @escaping (Controller) -> Void) {
        let item = ClosureMenuItem(title: title) { [controller] in action(controller) }
        item.state = checked ? .on : .off
        if let key {
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
