# Contributing

Thank you for helping. VoiceOver Audio Split is built for and with blind and low-vision Mac users, so feedback from people who use VoiceOver every day is the most valuable contribution of all.

## Reporting problems and ideas

- **Bugs:** open an issue with the **Bug report** form. Each field is a plain text box, so it works well with VoiceOver. The most useful details are what you pressed, what you heard, and what you expected.
- **Ideas:** use the **Feature idea** form.
- **Shortcuts** that do nothing or clash with VoiceOver: use the **Keyboard shortcut problem** form.
- **Translations:** use the **Translation fix or new language** form. No code needed.
- **Beta testers:** after going through the [testing checklist](docs/TESTING.md), send results with the **Beta test report** form.
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

To build an installer package that puts the app in Applications, run `./build.sh` (without `sudo`); see the README's "Installer package" section.

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
1. Add a case to `Command`, with a title. Every letter key is taken, so most new commands have no default key (`nil`); people can give them one in Settings. A default key must not already be used; the tests check this.
2. Handle it in `Controller.run(_:)`.
3. Add a menu item to the submenu it belongs in, in `AppDelegate.menuNeedsUpdate`. Keep the top of the menu for the split.
4. If it has a key, add a line to the setup guide's shortcut list and the README's shortcut table. Describe it in the README either way, and add a step to `docs/TESTING.md`.

## Translations

The app is in English, Spanish, French and German. Every phrase is in `App/Resources/Localizable.xcstrings`, a String Catalog; the permission requests are in `App/Resources/InfoPlist.xcstrings`.

- **Fixing a phrase:** open the catalog in Xcode, choose the language, and edit the translation. Or open an issue with the Translation form and we'll make the change.
- **Adding a language:** in Xcode, select the project, then under Info > Localizations press Add. Xcode adds the language to both catalogs, and you translate each phrase there.
- **Placeholders:** keep `%@` (a name or text) and `%lld` (a number) exactly as they are. If your language needs them in a different order, use `%1$@`, `%2$lld` and so on. A unit test checks that every translation has the same placeholders as the English.
- **Spoken text:** most phrases are spoken by VoiceOver, so keep them short and natural, and avoid symbols and abbreviations that read badly.
- **Short lowercase phrases,** such as "move closer" or "red", are inserted into longer sentences; keep them lowercase where your language allows.

**New text in code:** wrap anything the app shows or speaks in `String(localized:)`, and write whole sentences with interpolation, such as `String(localized: "Copied \(count) phrases")`, rather than joining pieces with `+`, because word order differs between languages. Interpolate whole strings: older versions of Xcode, like the one CI uses, reject a `Substring` (such as `text.dropFirst(4)`) inside `String(localized:)`, so wrap it in `String(...)`. Don't wrap technical text such as bundle IDs, AppleScript, file paths or log messages. The build lists new phrases in the catalog automatically when you open it in Xcode.

## Accessibility rules for changes

Every change must work fully with VoiceOver and the keyboard:

- **Labels:** every control needs a text label that VoiceOver reads. Use standard SwiftUI controls.
- **No mouse-only actions:** every action needs a key or a button.
- **Feedback:** every command gives a short spoken confirmation, and a tone where it helps.
- **Testing:** test with VoiceOver on before opening a pull request, and say in the pull request what you tested.

## Pull requests

- Keep each pull request to one change, and describe what it does and how you tested it.
- CI must pass. It checks that the Xcode project matches `project.yml`, builds Debug and Release, runs the unit tests, and builds the installer package.
- Add unit tests for any logic that doesn't need hardware or permissions.

## License of contributions

The project is licensed under the [GNU General Public License version 3](LICENSE), with an [additional permission](NOTICE) that allows distribution through the App Store and TestFlight. By contributing, you agree that your contribution is licensed under the same terms, including that additional permission.
