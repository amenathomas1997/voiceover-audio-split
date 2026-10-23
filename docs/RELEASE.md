# Releasing VoiceOver Audio Split

Text to paste into App Store Connect, and the steps for a public TestFlight beta and the App Store.

## 1. Before each upload

1. In `App/project.yml`, set a higher `CURRENT_PROJECT_VERSION`. The date and time works well, for example `202610221631`. For a new public version, also raise `MARKETING_VERSION`, for example to `1.1`. Then run `xcodegen` in `App/`.
2. Make sure CI passes on the commit.
3. In Xcode, choose Product > Archive, then Distribute App, then App Store Connect. Or run `App/release.sh upload`.
4. Add a section for the version to `CHANGELOG.md`.

## 2. App Store Connect: app information

- **Name:** VoiceOver Audio Split
- **Subtitle (up to 30 characters):** Audio control for VoiceOver
- **Category:** Utilities. Secondary category: Productivity.
- **Privacy policy URL:** https://github.com/amenathomas1997/voiceover-audio-split/blob/main/PRIVACY.md
- **Support URL:** https://github.com/amenathomas1997/voiceover-audio-split/issues
- **Contact email:** amena.thomas@fullcircleat.com
- **Copyright:** 2026 Full Circle AT LLC

## 3. App privacy ("nutrition label")

Answer **Data Not Collected**. The app has no accounts, analytics or tracking, and the developer receives no data. Optional features send requests directly from the user's Mac to third-party services, using the user's own API key for Anthropic. Those aren't collected by the developer. See PRIVACY.md.

## 4. TestFlight: beta app description

> VoiceOver Audio Split puts VoiceOver's speech in one ear and every other sound in the other, like the audio split in JAWS. It also lets you control your Mac's sound from the keyboard: quiet everything but VoiceOver, set the volume of individual apps, switch output devices, and mute the microphone. It adds hearing and clarity options, speech on demand and speech history, large-print reading and captions, camera text reading, and an audio hub for radio, podcasts, audiobooks and news. Everyday tools read barcodes, QR codes, medicine labels and money, check documents for accessibility, and save braille files. Custom labels, place markers and camera and microphone alerts help with other apps, and VoiceOver practice and a talking typing trainer help you learn. Spanish, French and German are included. Everything works from the keyboard with Right Option and a key, and a setup guide walks you through each permission.

## 5. TestFlight: what to test

> Please try the split with headphones: Right Option + Left Arrow or Right Arrow. Then try Right Option + Space to hear what's on, and Right Option + M for the menu, where everything else is grouped in submenus. New in this build: the Camera, Learning and Reading and Text submenus have barcode and label readers, VoiceOver practice, a typing trainer, a document check and braille files. We'd especially like to hear how it works with your headphones, during Zoom, Teams or FaceTime calls, and with your own VoiceOver settings. Send feedback from the TestFlight app, or open an issue on GitHub.

## 6. Beta App Review and App Review: notes

Paste this into **Review Notes**. Reviewers often ask about these permissions:

> VoiceOver Audio Split is an accessibility tool for blind and low-vision people who use the VoiceOver screen reader. It runs as a menu bar app. Open its menu with Right Option + M; a setup guide opens on first launch.
>
> Why each permission is needed:
> - Accessibility: global keyboard shortcuts with the right Option key, so users can control the app from anywhere without a mouse. Only the app's own shortcut keys are acted on; all other keystrokes pass through untouched and are never stored. The accessibility interface is also used, like VoiceOver uses it, to speak the user's own names for unlabeled controls (custom labels), to return to saved spots on web pages (place markers), and for "Do It for Me", which moves the VoiceOver cursor to a control the user asks for and only presses it after the user confirms. During VoiceOver practice and the typing trainer, which the user starts, key presses are caught so the user can practice them; nothing typed is stored.
> - System audio recording (Core Audio process taps): VoiceOver's speech and other apps' sound are captured separately and played back immediately into different ears. Nothing is recorded or stored.
> - Apple Events to VoiceOver (com.apple.security.temporary-exception.apple-events for com.apple.VoiceOver): VoiceOver ignores accessibility announcements from background apps, so the app asks VoiceOver to speak its status messages ("Speech left, other sounds right") in the user's own VoiceOver voice. It also reads VoiceOver's last phrase and cursor position for speech history, captions and the focus frame. These are VoiceOver's own documented AppleScript commands. No other app is controlled.
> - Screen recording: only when the user asks to describe the image under the VoiceOver cursor, read the text in the front window (on-device text recognition, for shared screens in meetings and apps without accessibility), or describe a video frame.
> - Apple Events to Safari and Chrome (temporary exception): only if the user sets presets for websites; the app asks the browser for the current tab's address to switch the user's audio preset. Addresses are not stored or sent.
> - Microphone: a five-second microphone check before calls that reports the voice and background noise levels. Nothing is recorded.
> - Downloads folder (read-only): announcing when a download finishes and opening the latest download.
> - Camera: on-device text reading (Scan and Read), a framing check before video calls, a color identifier, a light detector, a barcode and QR code reader, and a medicine label reader. Pictures are never saved or sent, except that the optional money identifier sends one picture to Anthropic with the user's own API key, after the user has allowed image descriptions. The app also tells blind users when another app turns the camera or microphone on, by checking whether those devices are in use; it never receives what they capture.
> - Network: optional lookups (Wikipedia, weather, product barcodes in Open Food Facts), the audio hub (radio, podcasts, LibriVox, news), and optional image descriptions with the user's own Anthropic API key.
> - Continuity Camera: the camera tools can use a nearby iPhone (NSCameraUseContinuityCameraDeviceType).
> - User scripts: the user can add their own AppleScripts to the app's Application Scripts folder (run with NSUserAppleScriptTask) or name a Shortcut (run with the shortcuts:// URL scheme). Nothing runs unless the user adds it.
> - User-selected files (read and write): opening documents in the large-print Doc Reader, and saving recognized text as a text or Word file where the user chooses.
>
> To test without VoiceOver: open the menu with Right Option + M, choose Speech Left, and play any audio. With VoiceOver on (Command + F5), VoiceOver's voice moves to the left ear and the other audio moves to the right ear.

## 7. Installer package (outside the App Store)

For Macs that can't use TestFlight, `./build.sh` makes `build/VoiceOver Audio Split.pkg`, which installs the app in Applications. To share it, sign it with Developer ID certificates and notarize it; see the README's "Installer package" section. The App Store and TestFlight builds don't use it.

## 8. Export compliance

The app's Info.plist sets `ITSAppUsesNonExemptEncryption` to `NO`. It uses only Apple's standard HTTPS, so no export documentation is needed.

## 9. Public TestFlight link

1. In App Store Connect, go to TestFlight > External Testing, and add a group, such as "Public beta".
2. Add the build, and fill in the beta description, what to test, and the review notes above.
3. Submit it for Beta App Review. This usually takes about a day.
4. After it's approved, turn on **Public Link** for the group, and use that link in the announcement and on the website.

## 10. App Store release

When the beta is stable, go to App Store Connect > the app > the version, then:
1. Add screenshots. For a menu bar app, use screenshots of the Settings, Doc Reader and Audio Hub windows.
2. Add the description and the review notes above.
3. Choose the build, and submit for review.
