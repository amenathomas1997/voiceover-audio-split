# Privacy Policy

**VoiceOver Audio Split** · Full Circle AT LLC · Last updated October 23, 2026

VoiceOver Audio Split does not collect, store or share any personal information. It has no accounts, no analytics, no advertising and no tracking. This policy explains what the app does with the things it can access, and which features connect to the internet.

## What stays on your Mac

- **Sound.** To split, lower or adjust sound, the app captures your Mac's audio and plays it back immediately. Nothing is recorded or saved.
- **VoiceOver's speech text.** Speech history and captions read what VoiceOver has just said. This text is kept in memory only, never written to disk, and cleared when the app quits.
- **Camera.** The camera framing check, Scan and Read, the color identifier, the light detector, the barcode and QR code reader and the medicine label reader analyze camera pictures on your Mac with Apple's Vision framework. Pictures are not saved or sent anywhere. The money identifier is the exception: it sends one camera picture to Anthropic (see below).
- **Camera and microphone alerts.** If these are on, the app checks once a second whether another app is using the camera, and which apps are using the microphone, to say when that changes. It only reads whether they are in use; it never sees or hears what they capture, and nothing is stored.
- **Other apps' controls.** Custom labels, place markers and Do It for Me read the names, roles and positions of controls in other apps through the macOS accessibility interface, the same way VoiceOver does. Labels and place markers save only what is needed to find that control again (its app, role, name or identifier, and position) in your settings on your Mac.
- **Files you open or save.** Doc Reader and Scan and Read read only the files you choose, and save text only where you choose.
- **Microphone.** The microphone check listens for about five seconds and measures how loud your voice and the background are. The sound is never recorded or saved.
- **Downloads folder.** If download announcements are on, the app notices new files in your Downloads folder and says their names. It never opens or reads them unless you ask it to open the latest download.
- **Screen.** Reading the front window and describing a video take a picture of that window. Window text is recognized on your Mac. Video descriptions send the picture to Anthropic, the same as image descriptions.
- **Websites.** If you set presets for websites, the app asks Safari or Chrome for the address of the current tab every two seconds while the browser is in front, and compares it with your list on your Mac. Addresses are never stored or sent anywhere.
- **Clipboard.** Say Clipboard, the Text Analyzer, Doc Reader and Translate read the clipboard only when you use them. If you turn on "Say what you copy", the app checks whether the clipboard changed twice a second and speaks the start of what was copied, except passwords and other items a password manager marks as concealed. It's never stored or sent.
- **Translation.** Translate uses Apple's on-device translation. Text isn't sent anywhere, though macOS may download a language the first time.
- **Your commands.** Scripts and Shortcuts you add run only when you press their key or choose them. They can do whatever they were written to do, so only add scripts you trust.
- **Diagnostics reports.** A diagnostics report contains the app's recent log, version and settings (never your API key or files). It's saved only where you choose, and never sent automatically.
- **Voice commands.** If you turn on voice commands, the app listens through the Mac's built-in microphone for "Audio Split" followed by a command, and for "Launch VoiceOver training", using Apple's speech recognition on your Mac (on-device only). What you say is never recorded or saved, and only those phrases do anything. The one exception: "Audio Split, find…" or "go to…" uses Do It for Me, so the name you said is sent to Anthropic with the front window's control names, as below. Only the name of the command that ran is written to the app's log, never what you said. With "Listen for a Voice Command" on a key instead, it listens only for a few seconds after you press it. The microphone indicator stays on while it listens. It's off unless you turn it on.
- **Call captions.** If you turn them on, the app captures the sound of your call apps (the ones listed in Settings, under Calls) without changing what you hear, and recognizes the speech on your Mac with Apple's on-device speech recognition. The captions are kept in memory until you turn captions off, so you can copy them; nothing is recorded, saved or sent.
- **Hearing profile.** The hearing loss values you type in or measure with the listening test are stored in your settings on your Mac and used only to adjust the sound.
- **Meeting helpers.** Am I Muted, Raise My Hand and the other meeting commands read the names of the buttons in your Zoom, Teams or FaceTime window through the accessibility interface. If you turn on reading new chat messages, the app reads the meeting's chat list every two seconds while a meeting app is open, speaks new messages, and keeps nothing.
- **Clipboard history.** If you turn it on, the last 20 things you copy are kept in memory only, never on disk, and are cleared when the app quits or you turn it off. Items a password manager marks as concealed are left out.
- **Timers and reminders.** What you ask to be reminded about is saved in your settings on your Mac until it's due, so reminders survive a restart. If you allow notifications, macOS shows them on screen.
- **Object finder and accessible PDFs.** The object finder analyzes camera pictures on your Mac with Apple's Vision framework and never saves them. Scanning to an accessible PDF recognizes text on your Mac and saves the PDF only where you choose.
- **Window switcher.** The window list is read through the accessibility interface when you open it, and isn't kept.
- **Mouse.** The audio mouse follows the pointer's position only while it's on, to play its tone.
- **Keyboard.** The app watches for its own shortcuts (the right-hand Option key with a command key). Other keystrokes are passed on untouched and never stored. While you use VoiceOver practice or the typing trainer, the keys you press are checked against the lesson and then forgotten.
- **Settings.** Your settings, presets and app volumes are stored on your Mac. If you add an Anthropic API key, it is stored in your Mac's Keychain.

## Features that use the internet

These connect only when you use them, and send only what is needed:

| Feature | Sent to | What is sent |
| --- | --- | --- |
| Describe image, describe a video, Ask the assistant (optional, off until you add your own API key) | Anthropic | A picture of the item under the VoiceOver cursor, or of the front window for a video, only when you ask and only after you allow it once; your questions and the conversation. Sent with your own API key and covered by [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy). |
| Do It for Me (optional, needs your own API key) | Anthropic | Your request, and the names and roles of the controls in the front window of the app you chose, only when you ask |
| Identify money (optional, needs your own API key and image descriptions allowed) | Anthropic | One camera picture, only when you ask |
| Barcode reader: product lookup | Open Food Facts | The barcode number of the product you scan |
| Research It: Wikipedia | Wikipedia (Wikimedia Foundation) | The topic you look up |
| Research It: weather | Open-Meteo | The city you look up |
| Audio hub: radio | Radio Browser | Your search words; then the station you choose streams to you |
| Audio hub: podcasts | Apple (iTunes Search) and the podcast's own host | Your search words; then the show's feed and episodes you choose |
| Audio hub: audiobooks | LibriVox | Your search words; then the book's chapters you choose |
| Check for updates (on by default, once a day; turn it off in Settings, Updates) | GitHub | A request for the latest release's details; if you choose to install it, the download of the installer. Not used by TestFlight or App Store copies. |
| Audio hub: news | The news feeds listed in the app (BBC and NPR by default, or ones you add) | A request for the headlines |

Like any internet request, these services can see your IP address. Dictionary definitions use the Mac's built-in dictionary and don't use the internet.

## Permissions the app asks for

| Permission | Used for |
| --- | --- |
| Accessibility | The keyboard shortcuts, custom labels, place markers and Do It for Me |
| System audio recording | Splitting and adjusting sound |
| Screen recording | Describe image (the item under the VoiceOver cursor), reading the front window's text, and describing a video |
| Microphone | The microphone check, and the voice command if you turn it on |
| Speech Recognition | Voice commands ("Audio Split" and a command, and "Launch VoiceOver training"), if you turn them on; recognized on your Mac only |
| Downloads folder (read only) | Saying when a download finishes, and opening the latest download |
| Camera | Camera framing check, Scan and Read, color identifier, light detector, barcode and QR code reader, medicine label reader, money identifier |
| Automation (VoiceOver) | Speaking announcements in your VoiceOver voice, speech history, captions, Read Item, the focus frame, restarting VoiceOver, and moving the VoiceOver cursor for place markers and Do It for Me |
| Automation (Safari, Chrome) | Presets for websites, only if you set any |
| Files you choose | Opening files in Doc Reader and Scan and Read, and saving text |

You can turn any of these off in System Settings > Privacy & Security. Features that need them will tell you what is missing.

## Children

The app does not knowingly collect information from anyone, including children.

## Changes

Changes to this policy will be posted in this file, with a new "Last updated" date.

## Contact

Questions about privacy: amena.thomas@fullcircleat.com
