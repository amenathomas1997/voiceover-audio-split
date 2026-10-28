// SetupGuideView.swift — shown on first launch (and from the menu): walks
// through the permissions the app needs, checking each one as it goes.

import AppKit
import Combine
import SwiftUI

struct SetupGuideView: View {
    var onDone: () -> Void

    @State private var shortcutsAllowed = Hotkeys.isTrusted
    @State private var cameraAsked = false
    @State private var microphoneAsked = false
    @State private var splitTested = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Text(String(localized: "VoiceOver Audio Split puts VoiceOver speech in one ear and other sounds in the other. A few permissions are needed first."))
                Text(String(localized: "New to VoiceOver? VoiceOver Lessons, in the app's menu under Learning, teaches it from the beginning."))
            }

            Section(String(localized: "Step 1: Allow the keyboard shortcuts")) {
                Text(shortcutsAllowed
                     ? String(localized: "Done. Keyboard shortcuts are allowed.")
                     : String(localized: "Not allowed yet. Open Accessibility settings and turn on VoiceOver Audio Split."))
                if !shortcutsAllowed {
                    Button(String(localized: "Open Accessibility settings")) {
                        // Asking first puts VoiceOver Audio Split in the list, ready to turn on.
                        Permission.accessibility.ask { NSWorkspace.shared.open(Permission.accessibility.settingsURL) }
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
                Text(String(localized: "This needs one checkbox in VoiceOver Utility, which is a separate app from System Settings. Until it's on, announcements use the Mac's standard voice."))
                VoiceOverAppleScriptSteps()
            }

            Section(String(localized: "Step 4: Camera and microphone")) {
                Text(String(localized: "Your Mac only lists VoiceOver Audio Split under Camera and Microphone in System Settings after the app has asked. Ask now, and choose Allow when your Mac asks. They're used for Scan and Read, the camera readers, the microphone check and voice commands."))
                Button(cameraAsked ? String(localized: "Camera: asked") : String(localized: "Ask for the Camera")) {
                    Permission.camera.ask { cameraAsked = true }
                }
                Button(microphoneAsked ? String(localized: "Microphone: asked") : String(localized: "Ask for the Microphone")) {
                    Permission.microphone.ask { microphoneAsked = true }
                }
                Text(String(localized: "If you chose Don't Allow before, your Mac won't ask again: turn VoiceOver Audio Split on in System Settings, Privacy and Security, Camera or Microphone."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "Step 5, optional: Voice commands")) {
                Text(String(localized: "Turn this on to control the app by voice from anywhere: say Audio Split, then a command, such as Audio Split, turn on VoiceOver, or Audio Split, what time is it. Launch VoiceOver training opens the lessons. Your Mac asks to allow speech recognition and the microphone. Speech is recognized on your Mac and never sent."))
                Toggle(String(localized: "Always listen for \u{201C}Audio Split\u{201D} and \u{201C}Launch VoiceOver training\u{201D}"), isOn: Binding(
                    get: { Preferences.shared.voiceCommand }, set: { Preferences.shared.voiceCommand = $0 }))
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
                Text(String(localized: "I: describe the image under the VoiceOver cursor. A: ask the assistant. These use the AI on this Mac (macOS 27 with Apple Intelligence), or Claude with your Anthropic API key in Settings."))
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
