# Releasing VoiceOver Audio Split

Text to paste into App Store Connect, and the steps for the TestFlight beta (by email invitation) and the App Store.

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
- **Support URL:** https://github.com/amenathomas1997/voiceover-audio-split#readme (public, with the feedback email; opening an issue would need a GitHub account)
- **Contact email:** amena.thomas@fullcircleat.com
- **Copyright:** 2026 Full Circle AT LLC
- **License agreement:** choose a custom agreement and paste the text from [LICENSE-AGREEMENT.md](LICENSE-AGREEMENT.md). It keeps the GPL's rights and adds the terms Apple requires.
- **Promotional text (up to 170 characters):** VoiceOver's speech in one ear, everything else in the other. Plus sound control, reading tools and spoken VoiceOver lessons, all from the keyboard.
- **Keywords (up to 100 characters):** voiceover,screen reader,blind,low vision,accessibility,audio,split,speech,braille,lessons,hearing
- **Description:**

> VoiceOver Audio Split puts VoiceOver's speech in one ear and everything else in the other, like the audio split in JAWS. Listen to a meeting, a video or music while VoiceOver keeps talking, without the two getting in each other's way. It also brings favorite features from JAWS, NVDA and SuperNova to the Mac, and every one of them works from the keyboard.
>
> AUDIO SPLIT
> • Speech in one ear and other sounds in the other, or speech in both ears with other sounds in one.
> • Adjust the balance between speech and other sounds with one key.
> • Calls from Zoom, Teams and FaceTime can stay in both ears or follow the split.
> • Send VoiceOver to a separate device, such as a speaker or a second headset.
>
> CONTROL YOUR MAC'S SOUND
> • Quiet everything except VoiceOver, instantly.
> • Set the volume, ear and tone of individual apps.
> • Switch output devices, and mute every microphone with one key.
> • Presets that switch automatically for each app or website.
> • Keep audio awake, so headphones don't cut off VoiceOver's first words.
>
> HEARING AND CLARITY
> • A speech clarity boost, a leveler for loud media, a volume limit, one-ear mode and ear balance.
> • A hearing profile, from an audiogram or a two-minute listening test, boosts the frequencies you hear less well in each ear.
>
> CALLS AND MEETINGS
> • In Zoom, Teams and FaceTime: hear whether you're muted, mute, switch the camera, raise your hand, read the chat and leave, without leaving where you are.
> • Call captions show what the other people say in large print, recognized on your Mac.
>
> SPEECH AND READING
> • Speech history, captions of what VoiceOver says, and system status on demand.
> • Doc Reader: large-print reading with the spoken word highlighted, in high-contrast colors.
> • Scan and Read: read printed text with the camera.
> • Screen OCR: read and click text in apps built without accessibility, in shared screens and in videos.
> • An audio hub for radio, podcasts, audiobooks and news.
>
> EVERYDAY TOOLS
> • Read barcodes, QR codes and medicine labels with the camera, and find an object or a word on a sign.
> • Identify colors, and detect light.
> • Timers and reminders, a clipboard history, a window switcher and a resource monitor.
> • Check Word documents and PDFs for accessibility problems, and make accessible PDFs from scans.
> • Save text as a braille file (.brf) for embossers and notetakers.
> • Record the screen with the Mac's sound and VoiceOver.
> • Hear when an app turns on the camera or microphone, when downloads finish and when devices connect.
>
> WORKING WITH APPS
> • Give your own names to unlabeled buttons, and hear them when VoiceOver reaches them.
> • Place markers to jump back to a spot on a web page.
>
> LEARN VOICEOVER
> • VoiceOver Lessons: 30 spoken lessons from the very beginning, up to Mail, Pages, Numbers, Keynote, Safari, Messages, Calendar, Finder, Zoom and Teams, braille displays and VoiceOver Utility.
> • Learn on your own, with detailed feedback and hints, or with a trainer, with a session report.
> • Daily practice that brings keys back on a schedule, and a one-minute challenge.
> • VoiceOver practice and a talking typing trainer.
>
> VOICE COMMANDS
> • Say "Audio Split" and a command, such as "quiet everything" or "what time is it?". Speech is recognized on your Mac.
>
> OPTIONAL AI
> • Describe images and videos, ask questions about what's on screen, identify money, or ask for a control by name, with Apple Intelligence on your Mac, or with Claude and your own Anthropic API key. Everything else works without it.
>
> BUILT FOR THE KEYBOARD
> • Every command is Right Option and a key, and you can change any key. A command palette finds every command by typing, and a setup guide walks you through each permission.
>
> PRIVATE BY DESIGN
> • No accounts, no analytics, no tracking. Audio is processed on your Mac and never recorded.
>
> Available in English, Spanish, French and German. Free and open source under the GNU General Public License.

## 3. App privacy ("nutrition label")

Answer **Data Not Collected**. The app has no accounts, analytics or tracking, and the developer receives no data. Optional features send requests directly from the user's Mac to third-party services, using the user's own API key for Anthropic. Those aren't collected by the developer. See PRIVACY.md.

## 4. TestFlight: beta app description

> VoiceOver Audio Split puts VoiceOver's speech in one ear and every other sound in the other, like the audio split in JAWS. It also lets you control your Mac's sound from the keyboard: quiet everything but VoiceOver, set the volume of individual apps, switch output devices, mute the microphone, and use presets that switch automatically for each app or website.
>
> It adds hearing and clarity options, speech on demand and speech history, large-print reading and captions, camera text reading, and an audio hub for radio, podcasts, audiobooks and news. Everyday tools read barcodes, QR codes, medicine labels and money, check documents for accessibility, and save braille files. Custom labels, place markers and camera and microphone alerts help with other apps.
>
> VoiceOver Lessons teach VoiceOver from the very beginning in 30 spoken lessons, up to Mail, Pages, Numbers, Keynote, Safari, Zoom and Teams, with a mode for learning on your own and one for learning with a trainer. VoiceOver practice and a talking typing trainer help you build speed. Voice commands work hands-free: say "Audio Split" and a command, recognized on your Mac.
>
> Everything works from the keyboard with Right Option and a key, and a setup guide walks you through each permission. Spanish, French and German are included.

## 5. TestFlight: what to test

> Please try the split with headphones: Right Option + Left Arrow or Right Arrow. Then try Right Option + Space to hear what's on, and Right Option + M for the menu, where everything else is grouped in submenus.
>
> New in this build: VoiceOver Lessons (in the menu under Learning), with a spoken welcome that asks whether you're learning on your own or with a trainer. Voice commands: turn them on in Settings, under Voice command, then say "Audio Split, what can I say?" or "Launch VoiceOver training". Many fixes from a full code review, including lessons working with Caps Lock as the VO key, and copy and paste in text fields.
>
> We'd especially like to hear how it works with your headphones, during Zoom, Teams or FaceTime calls, with your own VoiceOver settings, and how the lessons work for someone new to VoiceOver. Send feedback from the TestFlight app, or email amena.thomas@fullcircleat.com.

## 6. Beta App Review and App Review: notes

The **Review Notes** box holds 4,000 characters. Paste the short version into it, and attach the full version below it as a text file (App Review Information > Attachment). Reviewers often ask about these permissions.

### Short version, for the Review Notes box

> VoiceOver Audio Split is an accessibility tool for blind and low-vision people who use the VoiceOver screen reader. It runs in the menu bar: open its menu with Right Option + M. A setup guide opens on first launch. There is no account or sign-in, and nothing to buy.
>
> To test: open the menu (Right Option + M), choose Speech Left, and play any audio. With VoiceOver on (Command + F5), VoiceOver's voice moves to the left ear and other audio to the right. Also try menu > Learning > VoiceOver Lessons, and the command palette (Right Option + Return, type "battery", press Return). AI features that use the user's own Anthropic API key can be skipped; everything else works without one.
>
> Why each permission is needed:
> - Accessibility: global shortcuts with the right Option key (only the app's own shortcuts are acted on; other keys pass through and are never stored); speaking the user's own labels for unlabeled controls; and, only on the user's command, pressing a meeting app's mute, camera or leave button, a control the user asked for by name, or the text chosen in Screen OCR.
> - System audio recording (Core Audio process taps): VoiceOver's speech and other apps' sound are captured separately and played straight back into different ears; call captions recognize call audio on the Mac. Nothing is recorded or stored.
> - Apple Events to VoiceOver (temporary exception for com.apple.VoiceOver): VoiceOver ignores announcements from background apps, so the app asks VoiceOver to speak its status messages in the user's own voice, and reads VoiceOver's last phrase and cursor position for speech history, captions and the focus frame, with VoiceOver's documented AppleScript commands.
> - Apple Events to Safari and Chrome (temporary exception): only if the user sets presets for websites; the app asks for the current tab's address to switch the audio preset. Addresses are not stored or sent.
> - Screen recording: only when the user asks to describe an image, read the front window's text (recognized on the Mac), use Screen OCR, or record the screen (saved in the user's Movies folder; the microphone is left out unless the user turns it on).
> - Microphone and Speech Recognition: a five-second microphone check; optional voice commands (off by default, recognized on the Mac only); the user's voice in a screen recording if turned on. Audio is never stored or sent.
> - Camera: reading text, barcodes, colors, light and finding objects, all on the Mac. Pictures are never saved; one picture goes to Anthropic only for the optional money identifier, with the user's own key and consent.
> - Downloads folder (read-only): announcing finished downloads. Movies folder: saving the user's own screen recordings. User-selected files: opening documents and saving text where the user chooses.
> - Network: optional lookups (Wikipedia, weather, Open Food Facts), internet radio, podcasts, audiobooks and news, and optional AI requests with the user's own Anthropic API key. With Apple Intelligence, the AI features run on the Mac.
> - Notifications: timers and reminders the user sets.
> - This build doesn't download or install code; updates come only through the App Store.
>
> The attached file explains each item in more detail.

### Full version, to attach as a file

> VoiceOver Audio Split is an accessibility tool for blind and low-vision people who use the VoiceOver screen reader. It runs as a menu bar app. Open its menu with Right Option + M; a setup guide opens on first launch.
>
> Why each permission is needed:
> - Accessibility: global keyboard shortcuts with the right Option key, so users can control the app from anywhere without a mouse. Only the app's own shortcut keys are acted on; all other keystrokes pass through untouched and are never stored. The accessibility interface is also used, like VoiceOver uses it, to speak the user's own names for unlabeled controls (custom labels), to return to saved spots on web pages (place markers), and for "Do It for Me", which moves the VoiceOver cursor to a control the user asks for and only presses it after the user confirms. During VoiceOver Lessons, VoiceOver practice and the typing trainer, which the user starts, key presses are caught only while that window is in front, so the user can practice them; nothing typed is stored.
> - System audio recording (Core Audio process taps): VoiceOver's speech and other apps' sound are captured separately and played back immediately into different ears. Nothing is recorded or stored.
> - Apple Events to VoiceOver (com.apple.security.temporary-exception.apple-events for com.apple.VoiceOver): VoiceOver ignores accessibility announcements from background apps, so the app asks VoiceOver to speak its status messages ("Speech left, other sounds right") in the user's own VoiceOver voice. It also reads VoiceOver's last phrase and cursor position for speech history, captions and the focus frame. These are VoiceOver's own documented AppleScript commands. No other app is controlled.
> - Screen recording: only when the user asks to describe the image under the VoiceOver cursor, read the text in the front window (on-device text recognition, for shared screens in meetings and apps without accessibility), describe a video frame, or record the screen. Screen OCR, which the user starts, takes one picture of the front window or the screen and recognizes its text on the Mac; the arrow keys then move through the lines and Return clicks the text in the app (a click made with the Accessibility permission, after checking that the window is still there and nothing covers it). The keys are held only while that mode is on, and it ends by itself after a click, after two minutes without a key, and on sleep or lock. Record the Screen, which the user starts and stops with one command, saves a movie in the user's Movies folder; the microphone is left out unless the user turns it on in Settings, and each recording says as it starts whether it is included.
> - Calls and meetings: when the user asks ("Am I muted?", "Mute", "Leave the meeting"), the accessibility interface is used to read and press the meeting app's own buttons in Zoom, Teams or FaceTime; leaving always asks first. Call captions, which the user turns on, listen to the call apps' sound with a Core Audio process tap and recognize speech on the Mac (SFSpeechRecognizer, on-device only); nothing is recorded, stored or sent.
> - Notifications: timers and reminders the user sets are spoken, and also posted as notifications.
> - Clipboard: "say what you copy" and the clipboard history (the last 20 items, in memory only) are off until the user turns them on, and skip what password managers mark as concealed.
> - Apple Events to Safari and Chrome (temporary exception): only if the user sets presets for websites; the app asks the browser for the current tab's address to switch the user's audio preset. Addresses are not stored or sent.
> - Microphone: a five-second microphone check before calls that reports the voice and background noise levels. Nothing is recorded.
> - Speech Recognition and Microphone (optional, off by default): if the user turns on voice commands in Settings, the app listens for the wake word "Audio Split" followed by a command (such as "quiet everything" or "turn on VoiceOver"), and for "Launch VoiceOver training" to open its lessons, using SFSpeechRecognizer with requiresOnDeviceRecognition, through the built-in microphone. Audio is never recorded, stored or sent. The one exception is the user's own request "Audio Split, find…", which goes to Do It for Me (below) as text, with the user's API key. Commands that change something important ask for a spoken yes first.
> - Downloads folder (read-only): announcing when a download finishes and opening the latest download.
> - Camera: on-device text reading (Scan and Read), a framing check before video calls, a color identifier, a light detector, a barcode and QR code reader, and a medicine label reader. Pictures are never saved or sent, except that the optional money identifier sends one picture to Anthropic with the user's own API key, after the user has allowed image descriptions. The app also tells blind users when another app turns the camera or microphone on, by checking whether those devices are in use; it never receives what they capture.
> - Network: optional lookups (Wikipedia, weather, product barcodes in Open Food Facts), with NSAllowsArbitraryLoadsForMedia only so internet radio and podcast audio that is served over plain http can play, the audio hub (radio, podcasts, LibriVox, news), and optional image descriptions with the user's own Anthropic API key.
> - Continuity Camera: the camera tools can use a nearby iPhone (NSCameraUseContinuityCameraDeviceType).
> - User scripts: the user can add their own AppleScripts to the app's Application Scripts folder (run with NSUserAppleScriptTask) or name a Shortcut (run with the shortcuts:// URL scheme). Nothing runs unless the user adds it.
> - User-selected files (read and write): opening documents in the large-print Doc Reader, and saving recognized text as a text or Word file where the user chooses.
> - Movies folder (com.apple.security.assets.movies.read-write): Record the Screen saves the user's own screen recordings, which the user starts and stops, in Movies, VoiceOver Audio Split Recordings, where they can find them. The app reads nothing else there.
> - On-device AI: with Apple Intelligence, image descriptions, the assistant and Do It for Me use Apple's on-device Foundation Models framework; nothing is sent. "Describe images automatically", off by default, describes the picture under the VoiceOver cursor with the on-device model only.
> - Anthropic API (optional): image and video descriptions, the assistant, Do It for Me and the money identifier use the user's own Anthropic API key, entered in Settings. Nothing is sent without that key, pictures are sent only after the user allows it once, and each request is made only when the user asks. No account with us is needed; the app has no sign-in.
> - Updates: this App Store build doesn't download or install code. Updates come only through the App Store.
>
> To test without VoiceOver: open the menu with Right Option + M, choose Speech Left, and play any audio. With VoiceOver on (Command + F5), VoiceOver's voice moves to the left ear and the other audio moves to the right ear.
>
> Other features to try:
> - VoiceOver Lessons: menu > Learning > VoiceOver Lessons. A spoken welcome asks whether you're learning on your own (press 1) or with a trainer (press 2); Return starts the first lesson. Escape twice stops a lesson.
> - Voice commands: Settings > Voice command > turn on "Always listen for “Audio Split” and “Launch VoiceOver training”". Then say "Audio Split, what can I say?" or "Audio Split, what time is it?". It's off by default.
> - Command palette: Right Option + Return, then type a word such as "battery" and press Return.
> - Features that need an Anthropic API key (described above) can be skipped; everything else works without one.

## 7. Installer package (outside the App Store)

For Macs that can't use TestFlight, `./build.sh` makes `build/VoiceOver Audio Split.pkg`, which installs the app in Applications. To share it, sign it with Developer ID certificates and notarize it; see the README's "Installer package" section. The App Store and TestFlight builds don't use it.

To publish a new version, raise `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new version number) in `App/project.yml`, commit and push, then run:

```
NOTARY_PROFILE=VoiceOverAudioSplit ./build.sh publish
```

It builds, signs and notarizes the installer, and creates a GitHub release with the changelog's "Next" section as its notes. **Check for Updates** in installed copies then finds it. It relies on two things the script takes care of: the installer is always called `VoiceOver-Audio-Split.pkg`, and the notes end with `Build` and the build number, so a new build of the same version still counts as newer. The website's download button links to `releases/latest/download/VoiceOver-Audio-Split.pkg`, so it always gets the newest one.

## 8. Export compliance

The app's Info.plist sets `ITSAppUsesNonExemptEncryption` to `NO`. It uses only Apple's standard HTTPS, so no export documentation is needed.

## 9. TestFlight testers, by email invitation

There's no public link: people ask to join by email, with the email address of their Apple Account (Apple ID), and you add them. The website and README ask for this.

1. Once: in App Store Connect, go to TestFlight > External Testing, and add a group, such as "Beta testers". Add the build, fill in the beta description, what to test and the review notes above, and submit it for Beta App Review (usually about a day). Later builds of the same version usually don't need a new review.
2. For each request: in that group, choose Testers, the add button, then Add New Testers, and enter their name and the Apple Account email they sent. TestFlight emails them an invitation.
3. They install the free TestFlight app from the Mac App Store, open the invitation on their Mac, and choose Accept, then Install.
4. Reply to let them know the invitation is on its way, and that it comes from TestFlight to the address they gave. If they don't see it, check that the email they sent is the one their Apple Account uses, and look in their junk mail.

An external group can have up to 10,000 testers. Internal testing is only for people on your App Store Connect team.

## 10. App Store release

When the beta is stable, go to App Store Connect > the app > the version (its number must match the build's, for example 1.2), then:
1. Add screenshots (16:10, for example 2880 by 1800). For a menu bar app, use screenshots of the Settings, Doc Reader and Audio Hub windows.
2. Add the promotional text, description, keywords, support URL and copyright from section 2, and the review notes from section 6, with your contact name, phone and email for the reviewer.
3. Under App Information: the subtitle, the categories, the privacy policy URL, the license agreement and the age rating questions (no restricted content; the app has no web browser, no user-generated content and no purchases).
4. Under App Privacy: Data Not Collected (section 3).
5. Under Pricing and Availability: Free, in every country or region.
6. Choose the build, choose whether to release it yourself or automatically once approved, and submit for review.
