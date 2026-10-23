# Testing checklist for each release

Automated tests and CI cover the logic that needs no hardware: routing, the Text Analyzer, keys, presets, text comparison, color names and more. Everything that depends on real sound, permissions and VoiceOver needs people. Before each TestFlight build goes to external testers, ask a few VoiceOver users, ideally AppleVis members, to go through this list with headphones and send results through TestFlight feedback or a GitHub issue.

Say for each step: **works**, **doesn't work** (what you heard instead), or **not tried**.

## Setup

- [ ] Installer package (if you were sent one instead of TestFlight): after it finishes, the app is in Applications and in Launchpad, and it opens by itself.

- [ ] First launch: the setup guide opens and VoiceOver reads every step.
- [ ] Accessibility, system audio recording, and Automation for VoiceOver can each be allowed from the guide.
- [ ] Settings > About shows the version you were sent.
- [ ] Settings > Permissions shows each permission as allowed or not, and each button opens the right page of System Settings. Turning one on there updates the list within a few seconds.

## Split and sound

- [ ] Right Option + Left Arrow: VoiceOver moves to your left ear and music to the right. Press again: back to normal.
- [ ] Right Option + Up Arrow and Down Arrow change the balance, with a tone and an announcement.
- [ ] Right Option + Q quiets everything but VoiceOver, and pressing it again brings sound back.
- [ ] Right Option + D switches output, and it stays switched (try with AirPods in).
- [ ] Right Option + X mutes and unmutes the microphone. Check it in a call app.
- [ ] During a Zoom, Teams or FaceTime call, call audio follows the Calls setting.

## Keys and help

- [ ] Shortcuts work on a web page in Safari with Quick Nav on. VoiceOver must not catch them.
- [ ] Right Option + Return opens the command palette. Type "battery" and press Return.
- [ ] Right Option + Grave Accent turns input help on. Shortcuts then only describe themselves.
- [ ] The tutorial (in the menu) notices each step.
- [ ] Right Option + M opens the menu, even when the menu bar is full. Each submenu opens with Right Arrow and closes with Left Arrow, and shortcuts are read with their items.

## Reading and seeing

- [ ] Right Option + Z reads a shared screen in a meeting, or a window VoiceOver can't read.
- [ ] Right Option + N, Scan and Read: hold up a letter. The spoken guidance helps, and the text is read.
- [ ] Right Option + O, Doc Reader: words are highlighted as they're read. Save as Word works.
- [ ] The captions (U) and the focus frame (Y) appear and follow VoiceOver.

## Assistive tools

- [ ] Start a FaceTime or Zoom call: "Camera on" and the app using the microphone are announced, and again when it ends.
- [ ] Settings > Apps: give Music "A position you choose" and move it; then change its bass and treble.
- [ ] Label an unlabeled button: the label is spoken when VoiceOver lands on it again, also after restarting the app.
- [ ] Add a place marker on a web page, move away, then choose Next Place Marker: VoiceOver goes back there.
- [ ] Do It for Me: "find the search field" moves VoiceOver there. "Press" asks before pressing.
- [ ] Check a Word document with a picture and no headings, and a scanned PDF: the problems are listed with fixes.
- [ ] Save some text as braille and open the .brf file on a notetaker or braille display.
- [ ] Read a QR code (for example a Wi-Fi code) and a food barcode. Read a medicine bottle while turning it.
- [ ] Identify a banknote (needs an API key).
- [ ] VoiceOver practice in learn and quiz mode: right and wrong keys are recognized, and Escape stops.
- [ ] VoiceOver Lessons: do lessons 2, 6 and 10. In lesson 10, the "show your Downloads folder" task is noticed in Finder. After missing a key twice, the hint says which keys to hold. Missed keys appear under Practice What I Missed.
- [ ] VoiceOver Lessons, earlier check: do lesson 2 and lesson 6. Explanations are clear, wrong keys are named, right keys really work in the practice area and on the practice web page, and the lesson is marked done afterwards. If you use Caps Lock as the VO key, try it with that.
- [ ] Typing trainer: do the first lesson with Quick Nav on. Each key is named with its finger, wrong keys are corrected, and the result gives words per minute. Try the speed test.

## Languages (Spanish, French and German speakers)

- [ ] With your Mac in Spanish, French or German, the menu, Settings and announcements are in your language.
- [ ] Announcements sound natural when VoiceOver speaks them. Note any phrase that sounds wrong, and what it should say.
- [ ] The permission requests (microphone, camera, system audio) are in your language.

## Everyday

- [ ] A finished download is announced, and Right Option + Period opens it.
- [ ] Connecting AirPods is announced.
- [ ] The talking clock, when set, speaks on time.
- [ ] Microphone check (Right Option + Semicolon): the advice matches how you actually sound.
- [ ] Restart VoiceOver (Right Option + K): VoiceOver comes back.
- [ ] Keep audio awake: VoiceOver's first words aren't cut off with AirPods.

## Optional AI (needs an Anthropic API key)

- [ ] Right Option + I describes an image, and follow-up questions work.
- [ ] Right Option + Left Bracket describes a video without leaving it.

## Performance

- [ ] After a few hours with the split on, "App performance" in the command palette reports a small processor share, ideally under 5 percent. Include the number in your feedback.

If something fails, choose **Save a diagnostics report** in the command palette and attach the file. It contains the app's recent log and settings, never your API key or files.
