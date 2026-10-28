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
- [ ] By voice, "Audio Split, press Play" asks "Press it? Say yes or no"; silence for 8 seconds cancels.
- [ ] With voice commands on and speakers (not headphones), opening Settings doesn't trigger a command when VoiceOver reads "VoiceOver Audio Split Settings".
- [ ] In a lesson, open the rotor (VO U), type letters and press Escape: the rotor closes and the lesson keeps going. Escape twice stops the lesson.
- [ ] With Caps Lock switched on for capitals, lesson keys (Return, R, B, H, S) still work.
- [ ] Copy and paste (Command C, V) work in the Assistant and Settings text fields.
- [ ] Check for Updates (menu) says "You have the latest version" on the newest build. With an older installed build, it offers the update, downloads it, and Installer opens; after installing, the app opens again.
- [ ] Check a Word document with a picture and no headings, and a scanned PDF: the problems are listed with fixes.
- [ ] Save some text as braille and open the .brf file on a notetaker or braille display.
- [ ] Read a QR code (for example a Wi-Fi code) and a food barcode. Read a medicine bottle while turning it.
- [ ] Identify a banknote (needs an API key).
- [ ] VoiceOver practice in learn and quiz mode: right and wrong keys are recognized, and Escape stops.
- [ ] Voice commands: with voice commands on, try "Audio Split, what time is it?", "Audio Split, quiet everything", "Audio Split, sound back", "Audio Split, where am I?", "Audio Split, what can I say?" and "Audio Split, restart VoiceOver" (it asks yes or no). Ordinary talking without "Audio Split" does nothing. With voice commands off, give Listen for a Voice Command a key and try it.
- [ ] Voice command: turn on voice commands in Settings, allow speech recognition and the microphone, then say "Launch VoiceOver training" from another app: the lessons open. With AirPods in, their sound stays full quality.
- [ ] VoiceOver Lessons, spoken welcome: opening the lessons asks on your own (1) or with a trainer (2); Return then starts the next lesson.
- [ ] VoiceOver Lessons, both modes: do lesson 2 on your own (wrong keys are explained exactly, hints build up, and the recap is spoken at the end), then with a trainer (prompts are short, trainer notes are in the window, and a report appears at the end). Announcements aren't cut off by VoiceOver, and show on a braille display if you have one.
- [ ] VoiceOver Lessons, Going further: do lesson 16 (answer with the number keys), lesson 19 in Numbers (the save task is noticed), and lesson 23 in Safari (the new-tab and close-tab tasks are noticed; bookmark tasks end with Return). Try Daily Practice the next day, and the One-Minute Challenge.
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

## New in this version

- [ ] AI on this Mac (macOS 27 with Apple Intelligence): with no API key, Describe Image Under VoiceOver Cursor and Ask the Assistant answer, with no upload consent asked. Settings, Use AI, switches between this Mac and Claude.
- [ ] Describe images automatically (Settings, or the Assistant menu): in Photos, move through photos with VoiceOver; about a second after landing on each one, you hear a short description. Icons aren't described. Coming back to a photo repeats its description straight away.
- [ ] Record the Screen (give it a key in Command keys): start, do something with VoiceOver speaking, stop. The movie in Movies, VoiceOver Audio Split Recordings has the picture, the Mac's sound with VoiceOver, and your voice if the microphone is included.
- [ ] "Audio Split, can you see me?" checks the camera framing and says whether your face is centered.

- [ ] Keep this sound setting: switch the output device (Right Option + D) and do nothing. The window asks, says it goes back in 60 seconds, warns at 15 seconds, then switches back by itself. Try again and press Return: it's kept. Change one-ear mode in Settings and press Escape: it goes back.

- [ ] Call captions (menu > Calls and Meetings): in a Zoom, Teams or FaceTime call, what others say appears in the large-print strip within a second or two. Your own sound isn't changed. "Read the Last Caption" speaks the newest line; "Copy the Call Transcript" copies them all.
- [ ] Meeting helpers, in a real Zoom and a real Teams meeting: Am I Muted gives the right answer; Mute or Unmute, Camera On or Off and Raise or Lower Hand work and say the new state; Who's Talking and Read the Chat say something sensible or that they can't tell; Leave the Meeting asks first. Please report the exact button names if any of these don't work: they're matched by name.
- [ ] Hearing profile: the listening test plays tones in the correct ear, and Return records each one; with the profile on, the boosted frequencies sound clearer and nothing distorts.
- [ ] Contracted braille: Save as Braille with "Contracted (grade 2)" makes a .brf file that reads correctly on an embosser or notetaker.
- [ ] "Audio Split, set a timer for 1 minute": after a minute you hear the tones and the reminder, also after the Mac slept. "Remind me at (time) to (something)" works.
- [ ] Clipboard history (turn it on in Settings, Everyday tools): copy three things, open Clipboard History, and copy the oldest back.
- [ ] Switch to a Window: the list names every open window; typing filters it; Return brings that window to the front.
- [ ] Object finder: "Audio Split, look for a cup" (or a person) gives left, ahead or right as you move the camera. "Look for the word exit" finds printed text.
- [ ] Scan Pages to an Accessible PDF, and Make a Picture or PDF Accessible: the saved PDF opens in Preview with selectable text, and Check a Document's Accessibility finds no problems.
- [ ] VoiceOver Lessons: the six new lessons (Messages, Calendar, Finder, Zoom and Teams, braille displays, VoiceOver Utility) teach keys that work on your Mac. Import a Lesson accepts the sample lesson file; add a second student, finish a lesson, and export the report.

## Performance

- [ ] After a few hours with the split on, "App performance" in the command palette reports a small processor share, ideally under 5 percent. Include the number in your feedback.

If something fails, choose **Save a diagnostics report** in the command palette and attach the file. It contains the app's recent log and settings, never your API key or files.
