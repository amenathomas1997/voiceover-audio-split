// SetupGuideView.swift — shown on first launch (and from the menu): walks
// through the permissions the app needs, checking each one as it goes.

import AppKit
import Combine
import SwiftUI

struct SetupGuideView: View {
    var onDone: () -> Void

    @State private var shortcutsAllowed = Hotkeys.isTrusted
    @State private var voiceOverResult: Bool?
    @State private var splitTested = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Text(String(localized: "VoiceOver Audio Split puts VoiceOver speech in one ear and other sounds in the other. A few permissions are needed first."))
            }

            Section(String(localized: "Step 1: Allow the keyboard shortcuts")) {
                Text(shortcutsAllowed
                     ? String(localized: "Done. Keyboard shortcuts are allowed.")
                     : String(localized: "Not allowed yet. Open Accessibility settings and turn on VoiceOver Audio Split."))
                if !shortcutsAllowed {
                    Button(String(localized: "Open Accessibility settings")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }

            Section(String(localized: "Step 2: Allow the sound split")) {
                Text(splitTested
                     ? String(localized: "If your Mac asked to allow system audio recording, choose Allow. VoiceOver should now be in your left ear. Nothing is recorded or saved.")
                     : String(localized: "Turn the split on once. Your Mac asks to allow system audio recording; choose Allow. Headphones work best."))
                Button(splitTested ? String(localized: "Turn the split off") : String(localized: "Turn the split on")) {
                    Controller.shared.setSide(splitTested ? nil : .left)
                    splitTested.toggle()
                }
            }

            Section(String(localized: "Step 3: Hear announcements in VoiceOver's voice")) {
                Text(String(localized: "Open VoiceOver Utility with VoiceOver key and F8. In General, check “Allow VoiceOver to be controlled with AppleScript”. Then test below; if your Mac asks to let VoiceOver Audio Split control VoiceOver, choose OK."))
                Button(String(localized: "Test announcement")) {
                    Announcer.testVoiceOver { voiceOverResult = $0 }
                }
                if let voiceOverResult {
                    Text(voiceOverResult
                         ? String(localized: "Working. VoiceOver spoke the test.")
                         : String(localized: "VoiceOver did not respond. Check the setting above. Until then, announcements use the Mac's standard voice."))
                }
            }

            Section(String(localized: "Shortcuts")) {
                Text(String(localized: "Hold \(Preferences.shared.modifier.title) and press:"))
                Text(String(localized: "Left Arrow or Right Arrow: put speech in that ear. Press again to turn the split off."))
                Text(String(localized: "Up Arrow: speech louder. Down Arrow: other sounds louder."))
                Text(String(localized: "Space: hear what is on."))
                Text(String(localized: "M: open the VoiceOver Audio Split menu, with every command and Settings."))
                Text(String(localized: "Q: quiet everything but VoiceOver. W: hear which apps are playing."))
                Text(String(localized: "Equals and minus: the app in front louder or quieter. Zero: mute it."))
                Text(String(localized: "D: next output device. X: mute the microphone. 1 to 9: presets."))
                Text(String(localized: "S: silence VoiceOver. R: read the item under the VoiceOver cursor. H: speech history."))
                Text(String(localized: "C: hear the clipboard. F: check camera framing for video calls."))
                Text(String(localized: "L: layer. After it, press any of these keys on its own. Slash lists them; Escape cancels."))
                Text(String(localized: "I: describe the image under the VoiceOver cursor. A: ask the assistant. These need an Anthropic API key in Settings."))
                Text(String(localized: "T: analyze clipboard text. G: Research It. B: system status."))
                Text(String(localized: "O: Doc Reader. N: Scan and Read. U: large-print captions. Y: focus frame. P: audio hub. J: play or pause the audio hub."))
                Text(String(localized: "K: restart VoiceOver. E: compare text, once with the original copied and again with the new version. V: find a VoiceOver command. Comma: report a bug to Apple."))
                Text(String(localized: "Z: read the text in the front window, such as a shared screen. Left Bracket: describe what's happening in a video. Semicolon: microphone check. Period: open the latest download. Right Bracket: identify a color with the camera. Backslash: light detector."))
                Text(String(localized: "Return: the command palette, to search and run any command. Grave Accent: input help, to hear what keys do. Apostrophe: translate the clipboard. The tutorial in the menu lets you practice."))
                Text(String(localized: "Every key can be changed in Settings, under Command keys."))
                Text(String(localized: "The same menu is also in the menu bar as a headphones icon, if there is room for it. Opening the app again from Spotlight or Finder opens Settings."))
            }

            Section {
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onReceive(timer) { _ in shortcutsAllowed = Hotkeys.isTrusted }
    }
}
