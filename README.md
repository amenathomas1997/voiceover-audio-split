# VoiceOver Audio Split

[![CI](https://github.com/amenathomas1997/voiceover-audio-split/actions/workflows/ci.yml/badge.svg)](https://github.com/amenathomas1997/voiceover-audio-split/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**JAWS-style audio splitting, and much more, for VoiceOver on the Mac.** VoiceOver's speech plays in one ear and everything else plays in the other. The app also brings over favorite features from JAWS, NVDA and SuperNova. Everything works from the keyboard.

- **Audio split:** speech in one ear and other sounds in the other, with layouts, a volume balance, call handling and speech on a separate device.
- **Sound control:** quiet everything but VoiceOver, set the volume of individual apps, switch output devices, mute the microphone, and use presets that switch automatically for each app.
- **Hearing and clarity:** a speech clarity boost, leveling for loud media, a volume limit, one-ear mode and ear balance.
- **Speech tools:** speech on demand, speech history, captions, say clipboard, and system status.
- **Reading and low vision:** a large-print Doc Reader, camera text reading (Scan and Read), captions and a focus frame.
- **Everyday tools:** barcode, QR code, medicine label and money readers, a color identifier and light detector, a document accessibility check, braille files, and camera and microphone alerts.
- **Working with apps:** custom labels for unlabeled controls, place markers on web pages, and Do It for Me.
- **Learning:** a tutorial, input help, VoiceOver practice and a talking typing trainer.
- **Fixes for problems AppleVis users report:**
- **Keep audio awake** (in Settings or the menu) plays silence, so headphones and Bluetooth devices like AirPods don't sleep between phrases and cut off VoiceOver's first words.
- **Presets for websites** (in Settings) switch to a preset on a site in Safari or Chrome, which VoiceOver's own activities don't do. While a browser is in front and website presets exist, the app checks the current address every two seconds. The first time, macOS asks to let the app see which site is open.
- **Keys you choose always win.** If a later version adds a command whose default key you already use, the new command waits for you to give it a key.

**Spoken events and clock** (Settings): the app says when a download finishes, when headphones or speakers connect or disconnect, when the network drops or comes back, when the battery is low or charging starts or stops, and, optionally, when the screen locks. A talking clock chimes and says the time every hour, half hour or quarter hour. Scan and Read and the Doc Reader can save text as a text or Word file.

**Find, learn and extend:**
- The **command palette** finds every command, preset and user command by typing. Commands without a key, such as Tutorial, Audio Mouse, Export Settings or App Performance, live there and in the menu, and you can give any of them a key in Settings > Command keys, or choose "No key".
- **Input help** and a spoken **tutorial** (in the menu) teach the keys by practice.
- **Your commands** (Settings): put AppleScripts in the app's scripts folder (Settings > Open Scripts Folder; `~/Library/Application Scripts/com.fullcircleat.VoiceOverAudioSplit`), or name any Shortcut from the Shortcuts app, and give them keys. A script that returns text has it spoken.
- **Export and import settings** (Settings > Backup and diagnostics, or the menu) moves keys, presets, app and website rules and everything else to another Mac in one `.voasettings` file. Consent settings, such as allowing image uploads, stay on each Mac.

**More tools:** **beeps** while VoiceOver is silenced; **say what you copy**; the **audio mouse**, a tone that follows the pointer, higher at the top of the screen, and left and right in your ears; on-device **translation** of the clipboard or the item under the VoiceOver cursor; and the camera tools prefer a nearby **iPhone** through Continuity Camera.

**Assistive tools** (in the menu and the command palette; give any of them a key in Settings > Command keys):
- **Camera and microphone alerts:** the app says when another app turns the camera on or off, and names each app that starts or stops using the microphone, since you can't see the green or orange light. "Camera and Microphone in Use" says what's on now.
- **Sound for each app:** besides its own volume and ear, an app can sit anywhere between your ears (Settings > Apps, "A position you choose") and have its own bass and treble.
- **Custom labels:** put the VoiceOver cursor on an unlabeled button, choose "Label Item Under VoiceOver Cursor", and type a name. The name is spoken whenever VoiceOver lands on it again.
- **Place markers:** save a spot on a web page, or in an app, with "Add a Place Marker", and come back to it with "Next Place Marker", like JAWS PlaceMarkers.
- **Do it for me:** type what you want, such as "the search field" or "press Play", and Claude finds the control in the front window and moves the VoiceOver cursor there. It only presses something after you confirm, and never chooses to press anything that sends, buys, posts or deletes. Needs an Anthropic API key.
- **Document accessibility check:** checks a Word document or PDF for a missing title, missing or skipped headings, pictures without descriptions, tables without header rows, blank lines used for spacing, unclear links, and for PDFs, scanned pages without text, missing tags or language. Each problem comes with how to fix it.
- **Save as braille:** turns text into uncontracted (grade 1) Unified English Braille and saves a paged `.brf` file for embossers and notetakers. Contracted braille isn't available yet.
- **Barcode and QR code reader:** reads QR codes (links, Wi-Fi details, phone numbers, text) and copies them, and looks up product barcodes in Open Food Facts.
- **Medicine label reader:** reads the largest text first, usually the medicine's name, then the rest, and keeps reading new text as you turn the bottle. Everything it read is copied when you stop.
- **Identify money:** Claude names the banknotes or coins in a camera picture. Needs an API key and image descriptions allowed.
- **VoiceOver practice:** the app names a task, such as "go to the next heading", and you press the VoiceOver keys for it. Learn mode says the keys; quiz mode keeps score. Keys are caught while you practice, so nothing moves.
- **Typing trainer:** a talking typing tutor, like Talking Typer or TypingClub. Sixteen lessons add a few keys at a time from the home row, then capitals, numbers, punctuation, words and sentences. Each key is named with its finger and row. A right key plays a soft click (or a soft tone, or nothing, as you choose), and a wrong one plays a gentle low sound and says what you pressed and what to type. Each lesson ends with words per minute and accuracy, your best speed is kept, and there's a one-minute speed test. Finger hints are for the US English keyboard, and the practice words are English. Quick Nav can stay on.

**Languages:** English, Spanish, French and German. The app uses your Mac's language (System Settings, General, Language and Region). The translations are new, so please report anything that reads oddly. To add a language, open `App/Resources/Localizable.xcstrings` in Xcode.

**Diagnostics and performance:** "Save a Diagnostics Report" writes the app's recent log, version and settings (never the API key) to a file you choose, for bug reports. "App Performance" says how much processor time and memory the app uses. The [testing checklist](docs/TESTING.md) is for VoiceOver users testing each release.

**Audio hub:** internet radio, podcasts, LibriVox audiobooks and news.

**Optional AI:** image descriptions, video descriptions, an assistant, Do It for Me and the money identifier use Claude with your own API key. Everything else works without it.

**Get it:** the public beta is on TestFlight. The link will be here when the beta is approved. To install it without TestFlight, build the [installer package](#installer-package-outside-the-app-store). It needs macOS 14.2 or later, and headphones are recommended.

**Privacy:** nothing is collected or recorded. See the [privacy policy](PRIVACY.md).

**Help and feedback:** [open an issue](https://github.com/amenathomas1997/voiceover-audio-split/issues/new/choose), or see [CONTRIBUTING.md](CONTRIBUTING.md) to help build it. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

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
| Right Option + S | Silences VoiceOver's voice while VoiceOver keeps working (speech on demand). Press again to bring it back. |
| Right Option + R | Speaks the item under the VoiceOver cursor, even while VoiceOver is silenced |
| Right Option + H | Opens Speech History: what VoiceOver said recently, newest first, to review and copy |
| Right Option + C | Says what's on the clipboard: text, file names, or "An image" |
| Right Option + F | Checks camera framing before a video call: whether your face is centered, at a good distance, and well lit |
| Right Option + L | Layer: press the next key on its own to run its command. Slash lists the layer keys; Escape cancels. |
| Right Option + I | Describes the image under the VoiceOver cursor using Claude, with follow-up questions in the Assistant window (like JAWS Picture Smart AI) |
| Right Option + A | Opens the Assistant to ask about using the Mac and VoiceOver (like FS Companion) |
| Right Option + T | Text Checker: finds formatting problems in the clipboard text, each with its sentence, to step through with Command + Up and Down Arrow (like JAWS Text Analyzer) |
| Right Option + G | Opens Research It: dictionary definitions, Wikipedia summaries, and weather |
| Right Option + B | System status: time, battery, network, output device and volume, microphone |
| Right Option + O | Doc Reader: large-print reading window that reads aloud and highlights each word (like SuperNova Doc Reader) |
| Right Option + N | Scan and Read: hold a page up to the camera and hear its text, with spoken guidance; also reads image files and PDFs |
| Right Option + U | Large-print captions of what VoiceOver says, in a floating strip |
| Right Option + Y | Focus frame: a thick, colored frame that follows the VoiceOver cursor |
| Right Option + P | Audio hub: internet radio, podcasts, LibriVox audiobooks, news headlines (like SuperNova Connect) |
| Right Option + J | Play or pause the audio hub |
| Right Option + K | Restarts VoiceOver, the usual fix when Quick Nav stops working or focus gets stuck. Progress is spoken in the system voice while VoiceOver is off. |
| Right Option + E | Compare text: press once with the original copied, then again with the new version copied, to hear every change. Useful after Writing Tools proofreading, which VoiceOver can't review. |
| Right Option + V | Finds a VoiceOver command: type "heading" or "rotor" and hear the keys |
| Right Option + Comma | Reports a bug to Apple: adds your Mac's details to your description, for Feedback Assistant or accessibility@apple.com |
| Right Option + Z | Reads the text in the front window, such as slides shared in a Zoom or Teams meeting or an app VoiceOver can't read, with on-device text recognition |
| Right Option + Left Bracket | Describes what's happening in a video right now, using the optional AI, without leaving the video |
| Right Option + Semicolon | Microphone check: say a sentence, then hear whether you sound clear, too quiet, too loud or noisy |
| Right Option + Period | Opens the latest download |
| Right Option + Right Bracket | Identifies the color of something held up to the camera |
| Right Option + Backslash | Light detector: a tone that rises with the light the camera sees |
| Right Option + Return | Command palette: type a few letters of any command, preset or your own command, then press Return |
| Right Option + Grave Accent | Input help: shortcuts say what they do instead of doing it. Press again to stop. |
| Right Option + Apostrophe | Translates the clipboard on your Mac (macOS 15 or later) |

Every letter key is in use, so newer commands start without a key: the tutorial, VoiceOver practice, the typing trainer, the audio mouse, beeps, custom labels, place markers, Do It for Me, the document check, braille, the barcode, label and money readers, camera and microphone status, export and import, diagnostics and app performance. They're in the menu and the command palette.

Every key can be changed in Settings, under Command keys (like JAWS Keyboard Manager), including giving a key to a command that has none. Choosing a key another command uses swaps the two commands' keys. Digits 1 to 9 always switch presets, and slash always lists the layer keys.

You can change Right Option to Right Command, Right Control or Right Shift in Settings. The key of the same kind on the left keeps working normally. Each change plays a short tone, from the side it describes, and then VoiceOver announces it.

**Menu** (Right Option + M). The split is at the top, and everything else is grouped in submenus; with VoiceOver, Right Arrow opens a submenu and Left Arrow closes it. Each item shows its shortcut, if it has one.
- At the top: what's on now, Speech Left, Speech Right, Audio Split Off, What's On, the balance, Speech Louder, Other Sounds Louder, Quiet Everything But VoiceOver, and the Command Palette
- **Sound and Devices:** Layout, Reset Volume Balance, Lower Other Sounds While VoiceOver Speaks, the app in front (louder, quieter, mute), What's Playing, Next Output Device, Mute Microphone, Microphone Check, Camera and Microphone in Use, **Hearing and Clarity**, and the Audio Hub
- **Presets:** your presets, by number
- **Speech:** Silence VoiceOver, Beeps While VoiceOver Is Silenced, Read Item, Speech History, Say Clipboard, System Status, Large-Print Captions
- **Reading and Text:** Doc Reader, Scan and Read, Read Text in Front Window, Check Clipboard Text, Compare Text, Translate, Check a Document's Accessibility, Save as Braille, Focus Frame
- **Camera:** barcode and QR code reader, medicine label reader, Identify Money, Identify a Color, Light Detector, Check Camera Framing
- **Assistant and Research:** Describe Image, Describe What's Happening in Video, Ask the Assistant, Do It for Me, Research It
- **VoiceOver Help:** Restart VoiceOver, Keep Audio Awake, Find a VoiceOver Command, custom labels, place markers, Report a Bug to Apple
- **Learning:** Tutorial, Input Help, VoiceOver Practice, Typing Trainer
- **Everyday Tools:** Open Latest Download, Audio Mouse
- **Your Commands**, once you've added some
- At the bottom: Start at Login, **Backup and Diagnostics** (export, import, diagnostics report, app performance), Settings, Setup Guide and Quit

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
- **Apps:** give any app its own volume (30 dB quieter to 6 dB louder), mute, ear (left, right, both, the same as other sounds, or a position you choose anywhere from fully left to fully right), and bass and treble (12 dB either way). Helper processes count as part of their app, so this also works for apps such as Zoom that play sound from a separate helper. Safari's sound comes from a WebKit process that other apps share, such as Mail, so a Safari setting also applies to them.
- **Presets:** saved combinations of the split, balance, layout, calls, clarity and hearing settings. Switch with Right Option and a number, or from the menu. "Meeting", "Music" and "Focus" are included, and you can save your own from the current settings.
- **Automatic presets** and **presets for websites** (see below).
- **Spoken events and clock:** downloads, devices, network, battery, screen lock, camera and microphone use, and the talking clock, each on or off.
- **Low vision:** reading colors, Doc Reader and caption text sizes, and the focus frame's color, thickness and flash.
- **Your commands:** AppleScripts and Shortcuts on keys.
- **Custom labels and place markers:** the count of each, place markers to delete, and a button to manage labels.
- **Command keys:** a key for every command, or No key.
- **Assistant and image descriptions:** the Anthropic API key and whether pictures may be sent.
- **Backup and diagnostics**, and **About** (version, license, source code, privacy policy).

**Setup guide:** opens on first launch, and later from the menu. It walks through the permissions one at a time and checks each one:
1. Accessibility, for the shortcuts.
2. System audio recording, for the split. The guide has a button that turns the split on to trigger the request.
3. VoiceOver's "Allow VoiceOver to be controlled with AppleScript" setting, with a button that tests announcements.

**Automatic presets:** in Settings, under Automatic presets, choose a preset for any app, such as Meeting for Zoom. The app switches to it whenever that app comes to the front. You can also choose a preset for all other apps.

**Assistant and image descriptions** use Claude (`claude-opus-5-5`) through the Anthropic API. Add an API key from console.anthropic.com in Settings. It's stored in your Keychain, and requests are billed to that account. Image descriptions send a picture of only the item under the VoiceOver cursor, only when you ask, and only after you allow it once. The picture is taken before the window opens, so VoiceOver's cursor stays on the image. Taking the picture needs screen recording permission. Requests use Anthropic's server-side fallback, so a safety decline is retried on another model instead of failing. **Research It** uses the Mac's built-in dictionary (offline), Wikipedia, and Open-Meteo for weather (free, no account). **Text Analyzer** and **system status** work entirely on the Mac.

**Reading and low vision (inspired by SuperNova):**
- **Doc Reader** shows text in large print in your choice of colors: yellow on black, white on black, black on white, or black on yellow. It reads the text aloud and highlights each word as it's spoken. Command + Return reads or pauses. Command + Left and Right Arrow move by sentence, and Command + Up and Down Arrow move by paragraph. It opens text, Word, RTF, HTML and PDF files, or reads the clipboard.
- **Scan and Read** watches the camera and gives spoken guidance, such as "Text is cut off. Move the page to your left" or "hold the page closer". It reads the text once the page is steady. It also reads image files and PDFs, including scanned pages. All text recognition runs on the Mac with Apple's Vision framework.
- **Captions** and the **focus frame** float above every window and let clicks through. They're left out of screen pictures, so they never appear in image descriptions. Both settings are kept after a restart. Settings > Low vision has the colors, caption size, and frame color and thickness, plus an option to flash the frame when it moves.

**Audio hub:** one window for internet radio (the free Radio Browser directory), podcasts (Apple's podcast directory, then each show's episodes), free audiobooks (LibriVox, chapter by chapter, found by title or author) and news headlines (RSS feeds you can add to; BBC and NPR are included). It needs no accounts. The app can't capture its own sound, because that would feed back into itself, so hub audio isn't moved by the split. It does go silent in quiet mode and follows the balance between speech and other sounds.

**Features inspired by JAWS:** silencing VoiceOver with Read Item on request works like JAWS speech on demand. While VoiceOver is silenced, the app's own announcements use the system voice. Speech history works like the JAWS speech history: it reads VoiceOver's last phrase a few times a second, keeps up to 300 phrases in memory, and never saves them to disk. The camera check works like JAWS Face in View. Pictures are analyzed on the Mac with Apple's Vision framework and never saved or sent anywhere. Speech history and Read Item need "Allow VoiceOver to be controlled with AppleScript".

**AirPods automatic switching:** when AirPods are in your ears and an app such as Zoom is using audio, macOS can take the sound back to the AirPods a second or two after you switch away. For 20 seconds after you press D, the app puts your choice back, up to eight times. If macOS keeps taking it back, VoiceOver explains how to stop it. In System Settings, open your AirPods and set "Connect to This Mac" to "When Last Connected to This Mac".

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
- `App/Sources/SpeechTools.swift` has speech history, Read Item and Say Clipboard. It also sends every AppleScript request to VoiceOver through one queue, because NSAppleScript isn't safe to use from several threads at once.
- `App/Sources/Commands.swift` lists every command, its default key, and the keys it can move to. `App/Sources/Hotkeys.swift` turns key presses into commands.
- `App/Sources/Assistant.swift` has the Claude client, the API key in the Keychain, the screen capture, and the Assistant window. `App/Sources/Research.swift` is Research It. `App/Sources/SystemStatus.swift` has system status and the Text Analyzer.
- `App/Sources/Sensors.swift` (camera and microphone alerts), `App/Sources/AXTools.swift` (reading other apps' controls), `App/Sources/Labels.swift` (custom labels and place markers), `App/Sources/DoItForMe.swift`, `App/Sources/DocumentCheck.swift`, `App/Sources/Braille.swift`, `App/Sources/Readers.swift` (barcode, medicine label and money readers), `App/Sources/Practice.swift` and `App/Sources/TypingTrainer.swift`.
- `App/Sources/Palette.swift` (command palette, input help, tutorial), `App/Sources/Extend.swift` (your commands, settings export and import), `App/Sources/Extras.swift` (beeps, clipboard announcements, audio mouse, translation) and `App/Sources/Diagnostics.swift`.
- `App/Sources/Events.swift` (spoken events and the talking clock), `App/Sources/MicCheck.swift`, `App/Sources/ScreenText.swift` (reading the front window) and `App/Sources/CameraTools.swift` (color identifier and light detector).
- `App/Sources/Rescue.swift` (keep audio awake and restarting VoiceOver), `App/Sources/TextTools.swift` (compare text and the Text Checker) and `App/Sources/Helpers.swift` (the VoiceOver command finder and bug reports).
- `App/Sources/DocReader.swift`, `App/Sources/ScanReader.swift`, `App/Sources/LowVision.swift` (captions and the focus frame) and `App/Sources/AudioHub.swift` are the reading, low-vision and audio hub features.
- Development builds can check text recognition and the online services without any permission prompts:
  ```bash
  open -a "App/build/dd/Build/Products/Debug/VoiceOver Audio Split.app" --args --check-online
  ```
- `App/Sources/FaceCheck.swift` is the camera framing check, and `App/Sources/HistoryView.swift` is the Speech History window.
- `App/Sources/Tones.swift` plays the confirmation tones and the typing trainer's sounds.
- `App/Sources/SettingsView.swift` and `App/Sources/SetupGuideView.swift` are the Settings window and the setup guide.
- `App/Sources/Announcer.swift` sends announcements to VoiceOver.
- `App/Resources/Localizable.xcstrings` and `App/Resources/InfoPlist.xcstrings` hold the Spanish, French and German translations.
- `App/project.yml` defines the Xcode project. After you add or rename files, run `xcodegen` in `App/` (version 2.45.4, the version CI uses). The generated `VoiceOverAudioSplit.xcodeproj` opens normally in Xcode.
- `App/Tools/make_icon.swift` redraws the app icon.
- `App/Tests/` has unit tests for the logic that needs no hardware or permissions: routing for each layout, app positions and tone, balance, quiet and silence modes, command keys and presets, the Text Analyzer and text comparison, Doc Reader and Scan and Read, braille and the document check, QR codes and product names, typing lessons and VoiceOver practice, translations, and more. Run them with Product > Test in Xcode, or:
  ```bash
  xcodebuild -project App/VoiceOverAudioSplit.xcodeproj -scheme VoiceOverAudioSplit -destination 'platform=macOS' test
  ```
- **CI** (GitHub Actions, `.github/workflows/ci.yml`) runs on every push and pull request. It checks that the Xcode project matches `project.yml`, builds the app in Debug and Release, runs the unit tests, and builds the app's installer package (checking that it installs into Applications) and the script-version package. Test results and both packages are attached to each run. Packages built by CI aren't signed with a Developer ID.
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

## Installer package (outside the App Store)

To install the app without TestFlight, for example on your own Macs, build an installer package:

```bash
./build.sh
```

Run it without `sudo`. It needs Xcode, and makes `build/VoiceOver Audio Split.pkg`. Double-click the package: it asks for your password, puts the app in the Applications folder, removes the older script version if it's installed, and opens the app so the setup guide starts. `./build.sh install` builds it and installs it straight away.

- **On the Mac that built it**, the package installs without any warnings.
- **For other Macs**, sign it with your Developer ID. In Xcode, go to Settings > Accounts > Manage Certificates and add a **Developer ID Application** and a **Developer ID Installer** certificate; `build.sh` finds them by itself. To notarize as well, save your notary details once with `xcrun notarytool store-credentials VoiceOverAudioSplit`, then run `NOTARY_PROFILE=VoiceOverAudioSplit ./build.sh`. Without this, other Macs block the package.
- If `build.sh` says the build folder belongs to another account, it was once run with `sudo`. Remove it with `sudo rm -rf build` and run `./build.sh` again.

## Older version: scripts and installer package

Before the app, this project was a set of AppleScripts plus two small helper apps, built with `./build-script-version.sh` into a standalone installer (`build/VoiceOver Audio Split (script version).pkg`). It has none of the app's newer features, and installing the app removes it. That version is not sandboxed, so it cannot go through TestFlight, but it can be shared directly. The sections below describe it.

## Why it is not only an AppleScript

AppleScript cannot move a sound to one ear, and macOS has no built-in setting for this. So the project has three parts:

- **VO Audio Split.app** is a small background helper with no window or Dock icon. It uses Core Audio "process taps" (macOS 14.2 or later) to capture VoiceOver's speech and all other audio separately. It turns each into mono and plays speech in one ear and everything else in the other. When the helper quits, sound goes back to normal on its own.
- **VO Audio Split Keys.app** is a second background helper that is always running. It listens for Right Option + arrow keys anywhere on the Mac and runs the matching script.
- **AppleScripts** turn the split on, off or to the other side, change the volume balance, and VoiceOver tells you the result.

## Install (older version)

```bash
./build-script-version.sh
```

This builds `build/VoiceOver Audio Split (script version).pkg`, which anyone can double-click to install. No admin password is needed, because everything goes into the user's own account. Because the package isn't signed with a Developer ID, other Macs block it the first time. The user then goes to System Settings > Privacy & Security and chooses Open Anyway. Run `./build-script-version.sh install` to install it on this Mac.

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

The scripts are generated from `Scripts/make_scripts.py`. To change them, edit that file and run `./build-script-version.sh` again.

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
3. **Allow the shortcuts.** Go to System Settings > Privacy & Security > Accessibility and turn on VO Audio Split Keys. The shortcuts start working within two seconds, with no restart needed. After you run `./build-script-version.sh` again, macOS may treat the rebuilt app as new. If the shortcuts stop working, turn VO Audio Split Keys off and back on in that list.

## Notes

- Use headphones. On speakers the split is hard to hear.
- Stereo audio such as music becomes mono in its ear. JAWS works the same way.
- If you plug in headphones or change the output device, the helper moves to the new device automatically. It also notices when VoiceOver restarts.
- If the shortcuts don't respond, check `~/Library/Logs/VOAudioSplitKeys.log`. It says "Listening" once permission is granted.
- To see which audio processes the helper treats as speech:
  ```bash
  ~/Applications/"VO Audio Split.app"/Contents/MacOS/VOAudioSplit --list
  ```

## License

Copyright (C) 2026 Full Circle AT LLC.

VoiceOver Audio Split is free software under the [GNU General Public License version 3](LICENSE) or later. It includes an [additional permission](NOTICE) that allows distribution through the App Store and TestFlight.
