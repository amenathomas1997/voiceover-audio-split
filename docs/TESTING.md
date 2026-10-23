# Testing checklist for each release

Automated tests and CI cover the logic that needs no hardware: routing, the Text Analyzer, keys, presets, text comparison, color names and more. Everything that depends on real sound, permissions and VoiceOver needs people. Before each TestFlight build goes to external testers, ask a few VoiceOver users, ideally AppleVis members, to go through this list with headphones and send results through TestFlight feedback or a GitHub issue.

Say for each step: **works**, **doesn't work** (what you heard instead), or **not tried**.

## Setup

- [ ] First launch: the setup guide opens and VoiceOver reads every step.
- [ ] Accessibility, system audio recording, and Automation for VoiceOver can each be allowed from the guide.
- [ ] Settings > About shows the version you were sent.

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
- [ ] Right Option + M opens the menu, even when the menu bar is full.

## Reading and seeing

- [ ] Right Option + Z reads a shared screen in a meeting, or a window VoiceOver can't read.
- [ ] Right Option + N, Scan and Read: hold up a letter. The spoken guidance helps, and the text is read.
- [ ] Right Option + O, Doc Reader: words are highlighted as they're read. Save as Word works.
- [ ] The captions (U) and the focus frame (Y) appear and follow VoiceOver.

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
