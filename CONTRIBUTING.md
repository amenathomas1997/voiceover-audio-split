# Contributing

Thank you for helping. VoiceOver Audio Split is built for and with blind and low-vision Mac users, so feedback from people who use VoiceOver every day is the most valuable contribution of all.

## Reporting problems and ideas

- **Bugs:** open an issue with the **Bug report** form. Each field is a plain text box, so it works well with VoiceOver. The most useful details are what you pressed, what you heard, and what you expected.
- **Ideas:** use the **Feature idea** form.
- **TestFlight testers** can also send feedback from the TestFlight app.
- **Security problems:** please email instead of opening an issue (see [SECURITY.md](SECURITY.md)).

## Building the app

You need macOS 14.2 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) **2.45.4**, the version CI uses. For example:

```bash
brew install xcodegen
```

1. Generate the Xcode project. Run this again after adding, renaming or removing files:
   ```bash
   cd App && xcodegen
   ```
2. Open `App/VoiceOverAudioSplit.xcodeproj`, choose your own team under Signing & Capabilities, and run.
3. Development builds use the app ID `com.fullcircleat.VoiceOverAudioSplit.debug`, so they never clash with an installed copy. macOS asks for permissions separately for a development build.

Run the tests with Product > Test, or:

```bash
xcodebuild -project App/VoiceOverAudioSplit.xcodeproj -scheme VoiceOverAudioSplit -destination 'platform=macOS' test
```

To check text recognition and the online services without permission prompts, use a development build:

```bash
open -a "App/build/dd/Build/Products/Debug/VoiceOver Audio Split.app" --args --check-online
```

## Where things are

The [README](README.md#project-layout) describes each file. In short:

- **Audio:** `Splitter.swift` captures sound, and `Mixer.swift` routes and processes it.
- **Commands:** `Commands.swift` lists every command and its key, `Hotkeys.swift` turns key presses into commands, and `Controller.run(_:)` carries them out.
- **Windows:** each one is a SwiftUI view, such as `SettingsView`, `DocReaderView` and `AudioHubView`, opened from `AppDelegate`.

**Adding a command:**
1. Add a case to `Command`, with a title and a default key that isn't already used. The tests check this.
2. Handle it in `Controller.run(_:)`.
3. Add a menu item in `AppDelegate.menuNeedsUpdate`.
4. Add a line to the setup guide's shortcut list and the README's shortcut table.

## Accessibility rules for changes

Every change must work fully with VoiceOver and the keyboard:

- **Labels:** every control needs a text label that VoiceOver reads. Use standard SwiftUI controls.
- **No mouse-only actions:** every action needs a key or a button.
- **Feedback:** every command gives a short spoken confirmation, and a tone where it helps.
- **Testing:** test with VoiceOver on before opening a pull request, and say in the pull request what you tested.

## Pull requests

- Keep each pull request to one change, and describe what it does and how you tested it.
- CI must pass. It checks that the Xcode project matches `project.yml`, builds Debug and Release, runs the unit tests, and builds the script-version installer.
- Add unit tests for any logic that doesn't need hardware or permissions.

## License of contributions

The project is licensed under the [GNU General Public License version 3](LICENSE), with an [additional permission](NOTICE) that allows distribution through the App Store and TestFlight. By contributing, you agree that your contribution is licensed under the same terms, including that additional permission.
