# VoiceOver Audio Split

[![CI](https://github.com/amenathomas1997/voiceover-audio-split/actions/workflows/ci.yml/badge.svg)](https://github.com/amenathomas1997/voiceover-audio-split/actions/workflows/ci.yml)

JAWS-style audio splitting for VoiceOver on the Mac. VoiceOver speech plays in one ear and all other sound (music, video, calls, system sounds) plays in the other ear.

## The app (Xcode project, TestFlight)

The main version is a menu bar app in [App/](App/), built with Xcode and distributed through TestFlight. It has no Dock icon. To open its menu, press Right Option + M. The menu is also a headphones icon in the menu bar, which you can reach with VoiceOver by pressing VO-M twice. On Macs with a notch or a full menu bar, macOS may hide that icon for lack of space. The shortcut always works. Opening the app again from Spotlight or Finder opens its Settings window.

| Keys | What it does |
| --- | --- |
| Right Option + Left Arrow | Speech left, other sounds right. Press again to turn the split off. |
| Right Option + Right Arrow | Speech right, other sounds left. Press again to turn the split off. |
| Right Option + Up Arrow | Speech louder (turns the split on if it's off) |
| Right Option + Down Arrow | Other sounds louder (turns the split on if it's off) |
| Right Option + Space | Says what's on, such as "Speech right, other sounds left. Speech 6 decibels louder." |
| Right Option + M | Opens the app's menu wherever you are |
| Right Option + Q | Quiets everything but VoiceOver. Press again to bring it back. |
| Right Option + W | Says which apps are playing, such as "Music and Zoom are playing" |
| Right Option + = or - | Makes the app in front 3 dB louder or quieter |
| Right Option + 0 | Mutes or unmutes the app in front |
| Right Option + D | Switches to the next output device and says its name. Virtual devices such as ZoomAudioDevice are skipped. |
| Right Option + X | Mutes or unmutes every microphone at once |
| Right Option + 1 to 9 | Switches to a preset |

You can change Right Option to Right Command, Right Control or Right Shift in Settings. The key of the same kind on the left keeps working normally. Each change plays a short tone, from the side it describes, and then VoiceOver announces it.

**Menu:** the same commands, plus:
- Audio Split Off
- Layout
- Reset Volume Balance
- Lower Other Sounds While VoiceOver Speaks
- Start at Login
- Settings…
- Setup Guide…
- Quit

**Settings window:**
- **Layout:**
  - speech in one ear, other sounds in the other (like JAWS)
  - speech in both ears, other sounds in one ear
  - other sounds in both ears, speech in one ear
- **Keep other sounds in stereo:** music keeps its stereo sound but leans toward its ear, instead of being mixed to mono.
- **Play speech on:** a different output device. For example, VoiceOver plays on AirPods while other sounds play on the speakers.
- **Volume:**
  - how much each key press changes, 1 to 6 dB
  - the largest difference, 6 to 30 dB
  - lowering other sounds while VoiceOver speaks, and by how much
- **Calls:** audio from call apps can be split like other sounds, kept in both ears, or put with VoiceOver speech. Zoom, Teams, FaceTime, Slack, Discord, Webex and Skype are listed by default. You can add any open app or remove one.
- **Keyboard and sounds:** the shortcut key, and whether to play tones.
- **Clearer speech and hearing:**
  - **Speech clarity boost:** makes VoiceOver easier to understand over loud media by cutting rumble and lifting the frequencies that carry words.
  - **Even out loud media:** turns down sudden loud moments in other sounds.
  - **Volume limit:** keeps all sound below a set level, on top of the Mac's own volume.
  - **One ear:** VoiceOver and all other sound are combined into one ear, for people who hear on one side only. Tones play in that ear too.
  - **Ear balance:** makes one ear up to 12 dB louder than the other.
- **Apps:** give any app its own volume (30 dB quieter to 6 dB louder), mute, or ear (left, right, both, or the same as other sounds). Helper processes count as part of their app, so this also works for apps such as Zoom that play sound from a separate helper. Safari's sound comes from a WebKit process that other apps share, such as Mail, so a Safari setting also applies to them.
- **Presets:** saved combinations of the split, balance, layout, calls, clarity and hearing settings. Switch with Right Option and a number, or from the menu. "Meeting", "Music" and "Focus" are included, and you can save your own from the current settings.

**Setup guide:** opens on first launch, and later from the menu. It walks through the permissions one at a time and checks each one:
1. Accessibility, for the shortcuts.
2. System audio recording, for the split. The guide has a button that turns the split on to trigger the request.
3. VoiceOver's "Allow VoiceOver to be controlled with AppleScript" setting, with a button that tests announcements.

**AirPods automatic switching:** when AirPods are in your ears and an app such as Zoom is using audio, macOS can take the sound back to the AirPods a second or two after you switch away. For 20 seconds after you press D, the app puts your choice back, up to three times. If macOS keeps taking it back, VoiceOver explains how to stop it. In System Settings, open your AirPods and set "Connect to This Mac" to "When Last Connected to This Mac".

**Microphone mute covers every microphone,** because automatic switching can change the active one at any moment. A microphone that connects or becomes active while you're muted is muted straight away. Muting also lasts through a restart of the app.

Capturing audio only runs when something needs it: the split, quiet mode, an app setting, or a clarity or hearing feature. The rest of the time the Mac's sound is untouched. Device switching, microphone mute and "what's playing" never need capture.

The app remembers everything between restarts, except quiet mode, which always ends when the app restarts so sound can't stay muted by accident. VoiceOver announces each change in your own voice settings. If VoiceOver is off or doesn't allow AppleScript control, the app uses the system voice instead.

### Project layout

- `App/Sources/AppDelegate.swift` sets up the menu bar item and menu.
- `App/Sources/Controller.swift` holds the state (ear, balance, start at login), saves it, and applies the settings.
- `App/Sources/Preferences.swift` holds every setting from the Settings window.
- `App/Sources/Splitter.swift` captures the audio, using Core Audio process taps.
- `App/Sources/Mixer.swift` routes each captured sound to each ear or device, and processes it in real time: ducking, speech clarity, leveling, the one-ear mix, ear balance and the volume limit.
- `App/Sources/AudioSystem.swift` handles output device switching, the microphone mute and "what's playing".
- `App/Sources/Tones.swift` plays the confirmation tones.
- `App/Sources/SettingsView.swift` and `App/Sources/SetupGuideView.swift` are the two windows.
- `App/Sources/Hotkeys.swift` handles Right Option + arrow keys.
- `App/Sources/Announcer.swift` sends announcements to VoiceOver.
- `App/project.yml` defines the Xcode project. After you add or rename files, run `xcodegen` in `App/`. The generated `VoiceOverAudioSplit.xcodeproj` opens normally in Xcode.
- `App/Tools/make_icon.swift` redraws the app icon.
- Development builds have a self-test that tries device switching, the microphone mute and app matching inside the sandbox, then puts everything back:
  ```bash
  open -a "App/build/dd/Build/Products/Debug/VoiceOver Audio Split.app" --args --self-test
  ```
  Results go to the system log under `com.fullcircleat.VoiceOverAudioSplit`.

Team: Full Circle AT LLC (9G2D7CDZ5D). Bundle ID: `com.fullcircleat.VoiceOverAudioSplit`. The app is sandboxed, as TestFlight and the App Store require.

### Sending a build to TestFlight

1. **One time:** in [App Store Connect](https://appstoreconnect.apple.com), go to Apps and choose + > New App. Pick macOS, name it VoiceOver Audio Split, and choose the bundle ID `com.fullcircleat.VoiceOverAudioSplit`. Xcode registers that ID the first time you build.
2. Run:
   ```bash
   App/release.sh upload
   ```
   This builds, signs and uploads. It sets the build number from the date and time, so each upload is accepted.
3. In App Store Connect, go to TestFlight. When the build finishes processing, add testers. Internal testers on your team can install right away. External testers need Apple's quick beta review first.
4. Testers install the TestFlight app from the Mac App Store and accept your invitation.

To build without uploading anything, run `App/release.sh`. The package goes to `App/build/export/`. You can also use Xcode itself: open `App/VoiceOverAudioSplit.xcodeproj`, choose Product > Archive, then Distribute App > TestFlight & App Store.

## Older version: scripts and installer package

Before the app, this project was a set of AppleScripts plus two small helper apps, built with `./build.sh` into a standalone installer (`build/VoiceOver Audio Split.pkg`). That version is not sandboxed, so it cannot go through TestFlight, but it can be shared directly. The sections below describe it.

## Why it is not only an AppleScript

AppleScript cannot move a sound to one ear, and macOS has no built-in setting for this. So the project has three parts:

- **VO Audio Split.app** is a small background helper with no window or Dock icon. It uses Core Audio "process taps" (macOS 14.2 or later) to capture VoiceOver's speech and all other audio separately. It turns each into mono and plays speech in one ear and everything else in the other. When the helper quits, sound goes back to normal on its own.
- **VO Audio Split Keys.app** is a second background helper that is always running. It listens for Right Option + arrow keys anywhere on the Mac and runs the matching script.
- **AppleScripts** turn the split on, off or to the other side, change the volume balance, and VoiceOver tells you the result.

## Install (older version)

```bash
./build.sh
```

This builds `build/VoiceOver Audio Split.pkg`, which anyone can double-click to install. No admin password is needed, because everything goes into the user's own account. Because the package isn't signed with a Developer ID, other Macs block it the first time. The user then goes to System Settings > Privacy & Security and chooses Open Anyway. Run `./build.sh install` to install it on this Mac.

Older builds installed these pieces directly:
- `~/Applications/VO Audio Split.app`
- `~/Applications/VO Audio Split Keys.app`, plus `~/Library/LaunchAgents/local.voaudiosplit.keys.plist`, which starts it at login and restarts it if it stops
- `~/Library/Scripts/VoiceOver Audio Split/`, which holds:
  - **Cycle Audio Split** (off, then speech left, then speech right, then off)
  - **Speech Left**
  - **Speech Right**
  - **Audio Split Off**
  - **Speech Louder** (3 dB per press, up to 30 dB)
  - **Other Sounds Louder** (3 dB per press, up to 30 dB)
  - **Reset Volume Balance** (sets speech and other sounds to equal volume)
  - **Toggle Start at Login**

The scripts are generated from `Scripts/make_scripts.py`. To change them, edit that file and run `./build.sh` again.

## Keyboard shortcuts

| Keys | What it does |
| --- | --- |
| Right Option + Left Arrow | Speech left, other sounds right. Press again to turn the split off. |
| Right Option + Right Arrow | Speech right, other sounds left. Press again to turn the split off. |
| Right Option + Up Arrow | Speech 3 dB louder |
| Right Option + Down Arrow | Other sounds 3 dB louder |

Only the right Option key triggers these. Left Option + arrows still move by word in text. VoiceOver's own Option Key commander (VoiceOver Utility > Commands) must stay off, because it also uses Right Option.

The other scripts (Cycle, Off, Reset Volume Balance, Toggle Start at Login) have no shortcut. You can run them from the script menu, or add more shortcuts in `Sources/Keys/main.swift`.

## Volume balance

Speech Louder and Other Sounds Louder change the volume balance right away, even while the split is running. Only the quieter side is turned down, and the louder side always stays at full volume, so the sound never distorts. Your balance is saved and used the next time the split starts.

## Start at login

Toggle Start at Login turns automatic startup on or off. When it is on, the split starts when you log in, using the last ear you picked (left if you never picked one). macOS may show a "Background item added" notice the first time. The login setting is saved in `~/Library/LaunchAgents/local.voaudiosplit.login.plist`.

## One-time setup

1. **Allow audio capture.** The first time the split starts, macOS asks whether VO Audio Split can record system audio. Choose Allow. If you missed the prompt, go to System Settings > Privacy & Security > Screen & System Audio Recording and turn on VO Audio Split under "System Audio Recording Only".
2. **Let scripts speak through VoiceOver.** Open VoiceOver Utility (VO-F8), go to General, and check "Allow VoiceOver to be controlled with AppleScript". Without this, the scripts use the system voice for their announcements.
3. **Allow the shortcuts.** Go to System Settings > Privacy & Security > Accessibility and turn on VO Audio Split Keys. The shortcuts start working within two seconds, with no restart needed. After you run `./build.sh` again, macOS may treat the rebuilt app as new. If the shortcuts stop working, turn VO Audio Split Keys off and back on in that list.

## Notes

- Use headphones. On speakers the split is hard to hear.
- Stereo audio such as music becomes mono in its ear. JAWS works the same way.
- If you plug in headphones or change the output device, the helper moves to the new device automatically. It also notices when VoiceOver restarts.
- If the shortcuts don't respond, check `~/Library/Logs/VOAudioSplitKeys.log`. It says "Listening" once permission is granted.
- To see which audio processes the helper treats as speech:
  ```bash
  ~/Applications/"VO Audio Split.app"/Contents/MacOS/VOAudioSplit --list
  ```
