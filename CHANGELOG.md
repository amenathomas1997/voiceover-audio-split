# Changelog

## Next

- **Keep audio awake,** so the first words VoiceOver says aren't cut off by sleeping headphones.
- **Restart VoiceOver** with one key (Right Option + K).
- **Compare text** to hear every change between two versions (Right Option + E).
- **Text Checker** steps through each formatting problem with its sentence (Right Option + T).
- **Presets for websites** in Safari and Chrome.
- **Find a VoiceOver command** (Right Option + V), and **report a bug to Apple** (Right Option + Comma).
- Keys you choose are no longer replaced when a new command uses the same default key.
- **Spoken events:** downloads finished, devices connected and disconnected, network lost and back, low battery and charging, and screen locked. Also a **talking clock**.
- **Read the front window's text** (Right Option + Z), for shared screens and apps without accessibility.
- **Describe what's happening in a video** (Right Option + Left Bracket).
- **Microphone check** (Right Option + Semicolon) and **open the latest download** (Right Option + Period).
- **Color identifier** (Right Option + Right Bracket) and **light detector** (Right Option + Backslash).
- Save scanned or Doc Reader text as a text or Word file.
- **Command palette** (Right Option + Return), **input help** (Right Option + Grave Accent) and a spoken **tutorial**.
- **Your commands:** AppleScripts and Shortcuts on keys. **Export and import settings.**
- **Beeps** while VoiceOver is silenced, **say what you copy**, the **audio mouse**, and **on-device translation** (Right Option + Apostrophe, macOS 15).
- Camera tools prefer a nearby **iPhone** (Continuity Camera).
- **Diagnostics report**, **app performance**, and a testing checklist for VoiceOver testers.
- Any command can be set to "No key"; some new commands have no key by default.
- **Camera and microphone alerts:** hear when another app turns the camera on or off, or starts or stops using the microphone, and which app it is.
- **Sound for each app:** a position anywhere between your ears, and bass and treble.
- **Custom labels** for unlabeled controls, and **place markers** to jump back to a spot on a web page.
- **Do it for me:** ask for a control by name and the VoiceOver cursor goes there; pressing always asks first.
- **Document accessibility check** for Word documents and PDFs, and **save as braille** (.brf, uncontracted UEB).
- **Barcode and QR code reader**, **medicine label reader** and **money identifier**.
- **VoiceOver practice:** learn and quiz modes for VoiceOver's keys.
- **Typing trainer:** talking lessons from the home row up, finger hints, words per minute and accuracy, best scores, and a one-minute speed test. A soft click for each right key (or a soft tone, or no sound), and a gentle low sound for a wrong one.
- **In Spanish, French and German:** the app follows your Mac's language. Translations are new; corrections from native speakers are welcome.

- **VoiceOver Lessons, on your own or with a trainer:**
  - **On your own:** fuller explanations, step numbers, exact feedback on wrong keys, hints that build up, praise that names the keys, recaps, and advice on what to do next.
  - **With a trainer:** short prompts, hints on request, trainer notes for every lesson, and a session report that can be copied.
  - **Both modes:** every lesson states its goals, ends its quick check with one more round on anything missed, and lets you go back (B), get a hint (H) or skip (S). Lessons speak through VoiceOver's announcement queue, so they also appear on braille displays and don't cut VoiceOver off.
- **VoiceOver Lessons:** a 24-lesson course in four levels for learning VoiceOver from the beginning, through Finder, Safari, dialogs, Spotlight, Mail, customizing VoiceOver, what VoiceOver's descriptions mean, TextEdit, Pages, Numbers, Keynote, System Settings, and Safari tabs, bookmarks, Reading List and history. It adds multiple-choice questions, daily spaced practice and a one-minute challenge. It has explanations, real practice in a practice area and on a practice web page, real tasks it notices you doing in any app, step-by-step hints after two misses, quick checks, remembered mistakes with Practice What I Missed, a glossary, links to more help, and saved progress. VoiceOver Lessons and VoiceOver Practice go by the letter typed, so French (AZERTY) and German (QWERTZ) keyboards work. The setup guide points new VoiceOver users to it.
- **Fixes from a full code audit:**
  - Sound: AirPods in a call (and other one-channel devices) no longer lose one ear; silencing VoiceOver no longer silences calls set to go with speech; connecting a device rebuilds the sound once instead of several times; a split that can't start now says so; choosing speakers yourself is no longer undone.
  - Keys: held shortcut keys no longer leak repeats to VoiceOver; closing VoiceOver practice or the typing trainer always gives the keys back; practice can't score twice, and the trainer only takes keys while its window is in front.
  - Camera: tools can't leave the camera on when stopped quickly, can't start twice while macOS asks for permission, and say so if the camera sends no picture.
  - Reading and documents: the medicine label reader no longer skips dosing lines; the document check reads PDF tags and language properly, finds headings in non-English Word documents, and no longer reports empty table cells, page breaks or decorative pictures; large or damaged Word files can't crash it.
  - Other: pictures sent for descriptions are sized to fit, plain-http radio streams and podcast feeds play, playback failures are announced, "Say what you copy" never reads passwords copied from a password manager, Firefox downloads are announced when they finish, "C++" searches work, and Do It for Me always acts on the app you came from and can't press twice.
- **Permissions in Settings:** see what the app is allowed to do, and open the right page of System Settings for each permission.
- **An easier menu:** the split stays at the top, and everything else is grouped in submenus: Sound and Devices, Presets, Speech, Reading and Text, Camera, Assistant and Research, VoiceOver Help, Learning and Everyday Tools.
- **Installer package for the app:** `./build.sh` now builds an installer that puts the app in the Applications folder and removes the older script version, whose shortcuts clashed. The older script version is retired and its source removed.

## 1.0 (beta), October 2026

First public beta.

- **Audio split:** VoiceOver in one ear and other sounds in the other. Layouts with speech or other sounds in both ears, stereo other sounds, VoiceOver on a separate device such as AirPods, lowering other sounds while VoiceOver speaks, and call apps kept in both ears or with VoiceOver.
- **Sound control:** quiet everything but VoiceOver, volume, mute and ear for each app, what's playing, output device switching, muting all microphones, and presets that switch automatically for each app.
- **Hearing and clarity:** a speech clarity boost, leveling for loud media, a volume limit, one-ear mode and ear balance.
- **Inspired by JAWS and NVDA:** speech on demand (silence VoiceOver, then Read Item), speech history, say clipboard, camera framing check, Text Analyzer, Research It, system status, layer key, and customizable keys.
- **Optional AI:** describe the image under the VoiceOver cursor, and an assistant for Mac and VoiceOver questions, using Claude with your own Anthropic API key.
- **Reading and low vision, inspired by SuperNova:** Doc Reader, Scan and Read, large-print captions and a focus frame.
- **Audio hub:** internet radio, podcasts, LibriVox audiobooks and news headlines.
- A setup guide, spoken confirmations and tones, and every command available from the keyboard and the menu.
