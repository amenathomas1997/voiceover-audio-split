// LogicTests.swift — checks the parts of the app that need no hardware,
// permissions or VoiceOver, so they can run in CI.

import XCTest
@testable import VoiceOverAudioSplit

final class TextAnalyzerTests: XCTestCase {
    func testCleanTextHasNoProblems() {
        let result = TextAnalyzer.analyze("This is clean text.\nIt has two lines.")
        XCTAssertTrue(result.hasPrefix("No formatting problems found"), result)
    }

    func testFindsEachKindOfProblem() {
        let result = TextAnalyzer.analyze("This  is is a test (with a problem .\nSecond line ")
        XCTAssertTrue(result.hasPrefix("5 problems"), result)
        XCTAssertTrue(result.contains("1 double space, first on line 1"), result)
        XCTAssertTrue(result.contains("space before punctuation"), result)
        XCTAssertTrue(result.contains("1 repeated word"), result)
        XCTAssertTrue(result.contains("line ending in a space, first on line 2"), result)
        XCTAssertTrue(result.contains("unmatched parentheses: 1 opening, 0 closing"), result)
    }

    func testOddStraightQuotes() {
        XCTAssertTrue(TextAnalyzer.analyze("She said \"hello.").contains("odd number of straight quotes"))
    }
}

final class MixerTests: XCTestCase {
    override func tearDown() {
        Mixer.sources = []
        Mixer.speechDeviceChannel = nil
        Mixer.state = Mixer.State()
    }

    func testBalanceOnlyTurnsTheQuieterSideDown() {
        let even = Mixer.gains(balance: 0)
        XCTAssertEqual(even.speech, 1)
        XCTAssertEqual(even.others, 1)

        let speechLouder = Mixer.gains(balance: 6)
        XCTAssertEqual(speechLouder.speech, 1)
        XCTAssertEqual(speechLouder.others, powf(10, -6.0 / 20), accuracy: 0.0001)

        let othersLouder = Mixer.gains(balance: -12)
        XCTAssertEqual(othersLouder.others, 1)
        XCTAssertEqual(othersLouder.speech, powf(10, -12.0 / 20), accuracy: 0.0001)
    }

    func testSpeechLeftOtherSoundsRight() {
        Mixer.sources = [.speech, .others]
        Mixer.state = Mixer.State(split: .left)
        // Speech (mono) only in the left channel.
        XCTAssertEqual(Mixer.route(source: 0, channel: 0).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 1).fromLeft, 0)
        // Other sounds, mixed to mono, only in the right channel.
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 0)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromRight, 0.5)
    }

    func testSplitOffPlaysEverythingInBothEarsInStereo() {
        Mixer.sources = [.speech, .others]
        Mixer.state = Mixer.State(split: nil)
        XCTAssertEqual(Mixer.route(source: 0, channel: 0).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 1).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 1)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromRight, 1)
    }

    func testQuietAndSilenceMuteTheRightSources() {
        Mixer.sources = [.speech, .others]
        Mixer.state = Mixer.State(split: .right, quietAll: true)
        XCTAssertEqual(Mixer.route(source: 0, channel: 1).fromLeft, 0.5, "VoiceOver stays audible in quiet mode")
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 0, "other sounds are silent in quiet mode")

        Mixer.state = Mixer.State(split: .right, speechMuted: true)
        XCTAssertEqual(Mixer.route(source: 0, channel: 1).fromLeft, 0, "VoiceOver is silent when silenced")
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 0.5, "other sounds keep playing")
    }

    func testAppRuleVolumeMuteAndEar() {
        Mixer.sources = [.speech, .others, .app("com.example.music")]
        var rule = AppRule(name: "Music", bundleID: "com.example.music", volume: -6, ear: .right)
        Mixer.state = Mixer.State(split: nil, appRules: [rule])
        XCTAssertEqual(Mixer.route(source: 2, channel: 0).fromLeft, 0)
        XCTAssertEqual(Mixer.route(source: 2, channel: 1).fromLeft, 0.5 * powf(10, -6.0 / 20), accuracy: 0.0001)

        rule.muted = true
        Mixer.state = Mixer.State(split: nil, appRules: [rule])
        XCTAssertEqual(Mixer.route(source: 2, channel: 1).fromLeft, 0)
    }

    func testSpeechOnItsOwnDevice() {
        Mixer.sources = [.speech, .others]
        Mixer.speechDeviceChannel = 2
        Mixer.state = Mixer.State(split: .left)
        // Speech goes to both channels of the second device only.
        XCTAssertEqual(Mixer.route(source: 0, channel: 0).fromLeft, 0)
        XCTAssertEqual(Mixer.route(source: 0, channel: 2).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 3).fromLeft, 0.5)
        // Other sounds stay on the main device, in stereo.
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 1)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromRight, 1)
    }
}

final class CommandKeyTests: XCTestCase {
    override func tearDown() {
        KeyMap.update(custom: [:])
    }

    func testEveryCommandHasItsOwnDefaultKey() {
        let keys = Command.allCases.compactMap(\.defaultKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two commands share a default key")
    }

    func testDefaultKeysAreAssignableAndAvoidReservedKeys() {
        for command in Command.allCases {
            guard let key = command.defaultKey else { continue }
            XCTAssertNotNil(Key.named(key), "\(command) has a key Settings can't show")
            XCTAssertNil(Key.presetDigits[key], "\(command) uses a preset digit")
            XCTAssertNotEqual(key, Key.slash, "\(command) uses the layer help key")
        }
    }

    func testCustomKeyReplacesDefault() {
        KeyMap.update(custom: [Command.systemStatus.rawValue: 40]) // K
        XCTAssertEqual(KeyMap.commandForKey[40], .systemStatus)
        XCTAssertNil(KeyMap.commandForKey[Command.systemStatus.defaultKey!])
        XCTAssertEqual(KeyMap.key(for: .systemStatus)?.name, "K")
        // K is also the default for restarting VoiceOver: the chosen key wins.
        XCTAssertNil(KeyMap.key(for: .rescueVoiceOver))
    }

    func testLayerHelpListsEveryCommand() {
        let spoken = KeyMap.spokenList
        // Every command with a key is listed; commands without a key can't be reached from the layer.
        for command in Command.allCases where KeyMap.key(for: command) != nil {
            XCTAssertTrue(spoken.contains(command.title), "layer help is missing \(command)")
        }
    }
}

final class SettingsModelTests: XCTestCase {
    func testPresetsSurviveSaving() throws {
        let data = try JSONEncoder().encode(Preset.defaults)
        let decoded = try JSONDecoder().decode([Preset].self, from: data)
        XCTAssertEqual(decoded, Preset.defaults)
        XCTAssertEqual(decoded.map(\.name), ["Meeting", "Music", "Focus"])
    }

    func testAppRuleIsDefaultOnlyWhenNothingChanged() {
        var rule = AppRule(name: "App", bundleID: "com.example.app")
        XCTAssertTrue(rule.isDefault)
        rule.volume = -3
        XCTAssertFalse(rule.isDefault)
        rule.volume = 0
        rule.ear = .left
        XCTAssertFalse(rule.isDefault)
    }

    func testAppleScriptQuotingEscapesQuotesAndBackslashes() {
        XCTAssertEqual(VoiceOverText.quoted(#"Say "hi" \ bye"#), #""Say \"hi\" \\ bye""#)
    }
}

final class ReadingTests: XCTestCase {
    func testDocReaderStepsBySentenceAndParagraph() {
        let text = "First sentence. Second sentence.\nNew paragraph here. And more."
        let layout = TextLayout(text)
        XCTAssertEqual(layout.paragraphs.count, 2)
        XCTAssertEqual(layout.sentences.count, 4)
        let second = TextLayout.step(layout.sentences, from: 0, by: 1)
        XCTAssertEqual(second.map { (text as NSString).substring(from: $0) }?.hasPrefix("Second"), true)
        let nextParagraph = TextLayout.step(layout.paragraphs, from: 0, by: 1)
        XCTAssertEqual(nextParagraph.map { (text as NSString).substring(from: $0) }?.hasPrefix("New paragraph"), true)
        XCTAssertNil(TextLayout.step(layout.paragraphs, from: 0, by: -1), "nothing before the first paragraph")
    }

    func testScanGuidance() {
        XCTAssertNotNil(TextRecognition.guidance(for: []))
        XCTAssertNil(TextRecognition.guidance(for: [CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)]), "well placed")
        let cutLeft = TextRecognition.guidance(for: [CGRect(x: 0, y: 0.2, width: 0.6, height: 0.6)])
        XCTAssertEqual(cutLeft?.contains("to your left"), true, "image left edge means move the page left")
        let small = TextRecognition.guidance(for: [CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)])
        XCTAssertEqual(small?.contains("closer"), true)
    }

    func testRSSFeedReadsTitlesSummariesAndAudio() {
        let xml = """
        <rss><channel><title>Show</title>
        <item><title>Episode 1</title><description><![CDATA[<p>Hello &amp; welcome</p>]]></description>
        <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/></item>
        <item><title>Headline</title><description>Plain summary</description></item>
        </channel></rss>
        """
        let items = RSSFeed.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Episode 1")
        XCTAssertEqual(items[0].summary, "Hello & welcome")
        XCTAssertEqual(items[0].audio, URL(string: "https://example.com/1.mp3"))
        XCTAssertNil(items[1].audio)
        XCTAssertEqual(items[1].summary, "Plain summary")
    }
}

final class PainPointTests: XCTestCase {
    func testCompareFindsChangesAddsAndRemovals() {
        let changes = TextCompare.changes(from: "I went their today. It was very good.",
                                          to: "I went there today. It was good. Thanks.")
        XCTAssertEqual(changes.map(\.kind), [
            .changed(from: "their", to: "there"),
            .removed("very"),
            .added("Thanks."),
        ])
        XCTAssertEqual(changes.map(\.sentence), [1, 2, 3])
        XCTAssertTrue(TextCompare.summary(changes).hasPrefix("3 changes."))
        XCTAssertTrue(TextCompare.changes(from: "Same text.", to: "Same text.").isEmpty)
    }

    func testTextCheckerNamesTheSentence() {
        let issues = TextAnalyzer.issues(in: "This is fine. This has has a repeat. And (one more.")
        let repeated = issues.first { $0.problem == "repeated word" }
        XCTAssertEqual(repeated?.sentenceNumber, 2)
        XCTAssertEqual(repeated?.sentence, "This has has a repeat.")
        XCTAssertTrue(issues.contains { $0.problem.contains("unmatched parentheses") && $0.sentence == nil })
    }

    func testWebsiteRulesMatchSubdomains() {
        let rules = ["youtube.com": "quiet"]
        XCTAssertEqual(SitePresets.match(host: "www.youtube.com", in: rules), "quiet")
        XCTAssertEqual(SitePresets.match(host: "m.YouTube.com", in: rules), "quiet")
        XCTAssertNil(SitePresets.match(host: "notyoutube.com", in: rules))
        XCTAssertEqual(SitePresets.normalize("https://www.YouTube.com/watch?v=1"), "youtube.com")
        XCTAssertEqual(SitePresets.normalize(" www.bbc.co.uk "), "bbc.co.uk")
    }

    func testVoiceOverCommandSearch() {
        XCTAssertTrue(VoiceOverCommands.search("rotor").contains { $0.keys == "VO U" })
        XCTAssertTrue(VoiceOverCommands.search("next heading").first?.keys.hasPrefix("VO Command H") ?? false)
        XCTAssertEqual(VoiceOverCommands.search("").count, VoiceOverCommands.all.count)
        XCTAssertTrue(VoiceOverCommands.search("zzzz").isEmpty)
    }
}

final class EverydayToolTests: XCTestCase {
    func testColorNames() {
        XCTAssertEqual(ColorNames.name(red: 0.05, green: 0.05, blue: 0.05), "black")
        XCTAssertEqual(ColorNames.name(red: 0.95, green: 0.95, blue: 0.95), "white")
        XCTAssertEqual(ColorNames.name(red: 0.5, green: 0.5, blue: 0.52), "gray")
        XCTAssertEqual(ColorNames.name(red: 0.9, green: 0.1, blue: 0.1), "red")
        XCTAssertEqual(ColorNames.name(red: 0.1, green: 0.15, blue: 0.4), "navy blue")
        XCTAssertEqual(ColorNames.name(red: 0.2, green: 0.4, blue: 0.9), "blue")
        XCTAssertEqual(ColorNames.name(red: 0.45, green: 0.28, blue: 0.1), "brown")
        XCTAssertEqual(ColorNames.name(red: 0.1, green: 0.6, blue: 0.2), "green")
        XCTAssertEqual(ColorNames.name(red: 0.95, green: 0.7, blue: 0.75), "light pink")
        XCTAssertEqual(ColorNames.name(red: 0.9, green: 0.2, blue: 0.6), "pink")
    }

    func testMicrophoneAdvice() {
        XCTAssertEqual(MicCheck.advice(for: .init(speechLevel: -20, noiseLevel: -65, clipped: false)),
                       "You sound clear, with little background noise.")
        XCTAssertTrue(MicCheck.advice(for: .init(speechLevel: -45, noiseLevel: -70, clipped: false)).contains("too quiet"))
        XCTAssertTrue(MicCheck.advice(for: .init(speechLevel: -15, noiseLevel: -70, clipped: true)).contains("too loud"))
        XCTAssertTrue(MicCheck.advice(for: .init(speechLevel: -25, noiseLevel: -35, clipped: false)).contains("background noise"))
        XCTAssertTrue(MicCheck.advice(for: .init(speechLevel: -70, noiseLevel: -75, clipped: false)).contains("couldn't hear"))
        let measured = MicCheck.measure(levels: [-60, -58, -59, -20, -18, -22, -19, -61, -21, -20], peak: 0.5)
        XCTAssertGreaterThan(measured.speechLevel, -23)
        XCTAssertLessThan(measured.noiseLevel, -55)
    }

    func testTalkingClockLandsOnTheBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10, minute: 17))!
        func minuteHour(_ date: Date?) -> [Int] {
            let parts = calendar.dateComponents([.hour, .minute], from: date!)
            return [parts.hour!, parts.minute!]
        }
        XCTAssertEqual(minuteHour(SystemEvents.nextClockTime(after: start, every: 15, calendar: calendar)), [10, 30])
        XCTAssertEqual(minuteHour(SystemEvents.nextClockTime(after: start, every: 30, calendar: calendar)), [10, 30])
        XCTAssertEqual(minuteHour(SystemEvents.nextClockTime(after: start, every: 60, calendar: calendar)), [11, 0])
    }

    func testPartialDownloadsAreIgnored() {
        XCTAssertTrue(SystemEvents.isPartial("report.pdf.download"))
        XCTAssertTrue(SystemEvents.isPartial("movie.mp4.crdownload"))
        XCTAssertTrue(SystemEvents.isPartial("file.zip.part"))
        XCTAssertTrue(SystemEvents.isPartial(".DS_Store"))
        XCTAssertFalse(SystemEvents.isPartial("report.pdf"))
    }

    func testLightDetectorPitchRisesWithLight() {
        XCTAssertEqual(LightDetector.tone(forBrightness: 0), 220, accuracy: 0.01)
        XCTAssertEqual(LightDetector.tone(forBrightness: 1), 1760, accuracy: 0.01)
        XCTAssertLessThan(LightDetector.tone(forBrightness: 0.3), LightDetector.tone(forBrightness: 0.6))
    }
}

final class PowerToolTests: XCTestCase {
    override func tearDown() {
        KeyMap.update(custom: [:])
    }

    func testPaletteFindsCommandsPresetsAndKeys() {
        XCTAssertTrue(PaletteEntry.search("system status").contains { $0.action == .command(.systemStatus) })
        XCTAssertTrue(PaletteEntry.search("preset meeting").contains { $0.title == "Preset: Meeting" })
        XCTAssertFalse(PaletteEntry.search("").contains { $0.action == .command(.commandPalette) },
                       "the palette doesn't list itself")
        XCTAssertTrue(PaletteEntry.search("qqqqzzzz").isEmpty)
    }

    func testCommandsWithoutDefaultKeysAndNoKeyChoice() {
        XCTAssertNil(KeyMap.key(for: .diagnostics), "no default key")
        KeyMap.update(custom: [Command.speechLeft.rawValue: Key.none])
        XCTAssertNil(KeyMap.key(for: .speechLeft), "user chose no key")
        XCTAssertNil(KeyMap.commandForKey[123])
    }

    func testUserCommandKeysNeverTakeBuiltInKeys() {
        let free = UserCommand(name: "Mine", kind: .shortcut, target: "Mine", key: 123) // Left Arrow, used by speech left
        KeyMap.update(custom: [:], userCommands: [free])
        XCTAssertNil(KeyMap.userCommandForKey[123])
        KeyMap.update(custom: [Command.speechLeft.rawValue: Key.none], userCommands: [free])
        XCTAssertEqual(KeyMap.userCommandForKey[123], free.id, "usable once the built-in command gives the key up")
    }

    func testSettingsExportAndImportRoundTrip() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "balanceStep")
        defer { defaults.set(saved, forKey: "balanceStep") }
        defaults.set(4, forKey: "balanceStep")
        let data = try SettingsTransfer.exportData()
        defaults.set(2, forKey: "balanceStep")
        XCTAssertGreaterThan(try SettingsTransfer.importData(data), 0)
        XCTAssertEqual(defaults.integer(forKey: "balanceStep"), 4)
        XCTAssertThrowsError(try SettingsTransfer.importData(Data("not settings".utf8)))
        XCTAssertFalse(SettingsTransfer.portableKeys.contains("allowImageUpload"), "consent stays on each Mac")
    }

    func testAudioMouseMapsPositionToPitchAndEar() {
        XCTAssertEqual(AudioMouse.tone(x: 0, y: 0).frequency, 200, accuracy: 0.01)
        XCTAssertEqual(AudioMouse.tone(x: 0, y: 1).frequency, 1600, accuracy: 0.01)
        XCTAssertEqual(AudioMouse.tone(x: 0, y: 0.5).pan, -1)
        XCTAssertEqual(AudioMouse.tone(x: 1, y: 0.5).pan, 1)
        XCTAssertEqual(AudioMouse.tone(x: 0.5, y: 0.5).pan, 0, accuracy: 0.0001)
    }

    func testTutorialStepsUseRealCommands() {
        XCTAssertFalse(Tutorial.lessons.isEmpty)
        for lesson in Tutorial.lessons {
            XCTAssertNotNil(KeyMap.key(for: lesson.command), "\(lesson.command) has a key to practice")
        }
    }
}

/// The Spanish, French and German translations are in the app, and every
/// translation keeps the same placeholders as the English phrase.
final class LocalizationTests: XCTestCase {
    private let languages = ["es", "fr", "de"]

    private func table(_ language: String) -> [String: String] {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: language) else { return [:] }
        return NSDictionary(contentsOfFile: path) as? [String: String] ?? [:]
    }

    private func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(@|lld|ld|d|f|\\.\\d+f)")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { (text as NSString).substring(with: $0.range(at: 1)) }.sorted()
    }

    func testTranslationsAreBundled() {
        for language in languages {
            XCTAssertGreaterThan(table(language).count, 800, language)
        }
    }

    func testPlaceholdersMatch() {
        for language in languages {
            for (key, value) in table(language) {
                XCTAssertEqual(placeholders(key), placeholders(value), "\(language): \(key)")
            }
        }
    }

    func testSpanishIsUsed() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj"))
        let spanish = try XCTUnwrap(Bundle(path: path))
        XCTAssertNotEqual(spanish.localizedString(forKey: "Speech louder", value: nil, table: nil), "Speech louder")
    }
}

final class AppSoundTests: XCTestCase {
    func testPanKeepsLoudnessEven() {
        for position in stride(from: -100, through: 100, by: 25) {
            let routes = Mixer.pan(position)
            let left = routes[0]!.fromLeft * 2, right = routes[1]!.fromLeft * 2
            XCTAssertEqual(left * left + right * right, 1, accuracy: 0.001, "position \(position)")
        }
        XCTAssertEqual(Mixer.pan(-100)[1]!.fromLeft, 0, accuracy: 0.001)
        XCTAssertEqual(Mixer.pan(100)[0]!.fromLeft, 0, accuracy: 0.001)
    }

    func testOldAppRulesStillLoad() throws {
        let old = #"[{"name":"Music","bundleID":"com.apple.Music","volume":-6,"muted":false,"ear":"right"}]"#
        let rules = try JSONDecoder().decode([AppRule].self, from: Data(old.utf8))
        XCTAssertEqual(rules.first?.ear, .right)
        XCTAssertEqual(rules.first?.volume, -6)
        XCTAssertEqual(rules.first?.bass, 0)
    }

    func testToneMakesRuleNotDefault() {
        var rule = AppRule(name: "App", bundleID: "com.example.app")
        XCTAssertTrue(rule.isDefault)
        rule.treble = 3
        XCTAssertFalse(rule.isDefault)
    }

    func testShelfFilterBoostsLowSound() {
        let filter = Biquad()
        filter.setLowShelf(frequency: 250, gainDB: 12, sampleRate: 48000)
        var peak: Float = 0
        for i in 0..<48000 {
            let y = filter.process(sinf(2 * .pi * 50 * Float(i) / 48000))
            if i > 24000 { peak = max(peak, abs(y)) }
        }
        XCTAssertEqual(20 * log10f(peak), 12, accuracy: 1)
    }
}

final class BrailleAndDocumentTests: XCTestCase {
    func testUncontractedBraille() {
        XCTAssertEqual(Braille.translate("Hello, world."), ",hello1 world4")
        XCTAssertEqual(Braille.translate("NASA 2026"), ",,nasa #bjbf")
        XCTAssertEqual(Braille.translate("3.5 or 2a"), "#c4e or #b;a")
        XCTAssertEqual(Braille.translate("\"Yes\" (no)"), "8,yes0 \"<no\">")
    }

    func testBrfPages() {
        let text = Array(repeating: "word", count: 400).joined(separator: " ")
        let pages = Braille.brf(text, width: 40, height: 25).components(separatedBy: "\u{0C}")
        XCTAssertGreaterThan(pages.count, 1)
        for page in pages {
            let lines = page.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            XCTAssertLessThanOrEqual(lines.count, 25)
            XCTAssertTrue(lines.allSatisfy { $0.count <= 40 })
        }
        XCTAssertTrue(pages[1].hasPrefix(String(repeating: " ", count: 38) + "#b"))
    }

    func testUnicodeBraille() {
        XCTAssertEqual(Braille.unicode("abc"), "\u{2801}\u{2803}\u{2809}")
        XCTAssertEqual(Braille.unicode("#"), "\u{283C}")
    }

    func testWordChecks() {
        let document = """
        <w:document><w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Intro</w:t></w:r></w:p>
        <w:p/><w:p/><w:p/>
        <w:p><w:r><w:drawing><wp:docPr id="1" name="Picture 1"/></w:drawing></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:hyperlink r:id="x"><w:r><w:t>click here</w:t></w:r></w:hyperlink></w:p>
        </w:body></w:document>
        """
        let findings = DocumentCheck.checkWord(["word/document.xml": Data(document.utf8)]).map(\.problem)
        XCTAssertTrue(findings.contains("The document has no title."))
        XCTAssertTrue(findings.contains("The first heading is level 2, not level 1."))
        XCTAssertTrue(findings.contains("1 picture has no description."))
        XCTAssertTrue(findings.contains("1 table has no header row."))
        XCTAssertTrue(findings.contains("Blank lines are used for spacing in 1 places."))
        XCTAssertTrue(findings.contains("1 link has unclear text."))
    }

    func testZipReader() throws {
        // A zip holding "a.txt" with "hi", stored without compression.
        let bytes: [UInt8] = [
            0x50, 0x4b, 0x03, 0x04, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xac, 0x2a, 0x93, 0xd8, 2, 0, 0, 0, 2, 0, 0, 0, 5, 0, 0, 0,
            0x61, 0x2e, 0x74, 0x78, 0x74, 0x68, 0x69,
            0x50, 0x4b, 0x01, 0x02, 0x14, 0, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xac, 0x2a, 0x93, 0xd8, 2, 0, 0, 0, 2, 0, 0, 0,
            5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x61, 0x2e, 0x74, 0x78, 0x74,
            0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0, 1, 0, 1, 0, 0x33, 0, 0, 0, 0x25, 0, 0, 0, 0, 0,
        ]
        let files = try XCTUnwrap(Zip.entries(Data(bytes)))
        XCTAssertEqual(files["a.txt"].map { String(decoding: $0, as: UTF8.self) }, "hi")
    }
}

final class AssistiveToolTests: XCTestCase {
    func testQRCodeDescriptions() {
        XCTAssertEqual(CodeReader.describe("https://www.example.com/menu?table=4"), "Link to example.com. Copied to the clipboard.")
        XCTAssertEqual(CodeReader.describe("WIFI:S:Cafe Guest;T:WPA;P:secret;;"), "Wi-Fi network Cafe Guest. The details are copied to the clipboard.")
        XCTAssertEqual(CodeReader.describe("tel:+15551234567"), "Phone number +15551234567. Copied to the clipboard.")
        XCTAssertEqual(CodeReader.describe("Table 12"), "Code says: Table 12. Copied to the clipboard.")
    }

    func testProductDescription() {
        XCTAssertEqual(CodeReader.productDescription(["product_name": "Rolled oats", "brands": "Quaker, PepsiCo", "quantity": "500 g"]),
                       "Rolled oats by Quaker, 500 g")
        XCTAssertNil(CodeReader.productDescription(["product_name": ""]))
        XCTAssertNil(CodeReader.productDescription(nil))
    }

    func testLabelReadsLargestTextFirst() {
        let lines: [(String, CGRect)] = [
            ("Take 1 tablet daily", CGRect(x: 0, y: 0.5, width: 0.5, height: 0.04)),
            ("IBUPROFEN 200 mg", CGRect(x: 0, y: 0.3, width: 0.8, height: 0.12)),
            ("Rx 4471", CGRect(x: 0, y: 0.8, width: 0.3, height: 0.03)),
        ]
        XCTAssertEqual(LabelReader.ordered(lines), ["IBUPROFEN 200 mg", "Rx 4471", "Take 1 tablet daily"])
    }

    func testDrillKeys() {
        let heading = Drill.all.first { $0.keyCode == 4 && $0.command }!
        XCTAssertTrue(heading.matches(keyCode: 4, flags: [.maskControl, .maskAlternate, .maskCommand]))
        XCTAssertFalse(heading.matches(keyCode: 4, flags: [.maskControl, .maskAlternate]))
        XCTAssertFalse(heading.matches(keyCode: 4, flags: [.maskAlternate, .maskCommand]))
        // No two drills use the same keys.
        let keys = Drill.all.map { "\($0.keyCode)-\($0.shift)-\($0.command)" }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testElementSignatureMatching() {
        let saved = ElementSignature(bundleID: "com.example", role: "AXButton", windowTitle: "Inbox", frame: CGRect(x: 100, y: 40, width: 24, height: 24))
        XCTAssertTrue(saved.matches(ElementSignature(bundleID: "com.example", role: "AXButton", windowTitle: "Inbox",
                                                     frame: CGRect(x: 103, y: 41, width: 24, height: 24))))
        XCTAssertFalse(saved.matches(ElementSignature(bundleID: "com.example", role: "AXButton", windowTitle: "Inbox",
                                                      frame: CGRect(x: 140, y: 40, width: 24, height: 24))))
        let named = ElementSignature(bundleID: "com.example", role: "AXButton", identifier: "send")
        XCTAssertTrue(named.matches(ElementSignature(bundleID: "com.example", role: "AXButton", identifier: "send", frame: CGRect(x: 500, y: 9, width: 1, height: 1))))
        XCTAssertFalse(named.matches(ElementSignature(bundleID: "com.other", role: "AXButton", identifier: "send")))
    }

    func testPlaceMarkerPages() {
        XCTAssertEqual(PlaceMarkers.page(for: "https://www.example.com/news/today?id=4#top"), "example.com/news/today")
        XCTAssertEqual(PlaceMarkers.page(for: "https://example.com/"), "example.com")
    }

    func testDoItChoiceParsing() {
        let choice = DoItModel.Choice("Here you go: {\"element\": 3, \"action\": \"press\", \"say\": \"Pressing Play.\"}")
        XCTAssertEqual(choice?.element, 3)
        XCTAssertEqual(choice?.action, "press")
        XCTAssertEqual(DoItModel.Choice("{\"element\": null, \"action\": \"delete\", \"say\": \"x\"}")?.action, "none")
        XCTAssertNil(DoItModel.Choice("no json here"))
    }

    func testPositionWords() {
        XCTAssertEqual(Controller.describe(position: 0), "middle")
        XCTAssertEqual(Controller.describe(position: -50), "left 50")
        XCTAssertEqual(Controller.describe(position: 100), "fully right")
    }
}

final class ProductNameTests: XCTestCase {
    func testBrandAndWeightMark() {
        XCTAssertEqual(CodeReader.productDescription(["product_name": "Nutella", "brands": "Nutella,Ferrero", "quantity": "400 g e"]), "Nutella, 400 g")
    }
}

final class TypingTrainerTests: XCTestCase {
    func testLessonsOnlyUseTaughtKeys() {
        for lesson in TypingLesson.all where lesson.kind == .keys {
            let allowed = lesson.allowed
            for item in lesson.items() {
                XCTAssertTrue(item.allSatisfy(allowed.contains), "\(lesson.id): \(item)")
            }
            XCTAssertEqual(lesson.items().count, 20, lesson.id)
        }
    }

    func testHints() {
        XCTAssertEqual(KeyHints.hint("f"), "Left index finger, home row. It has a bump.")
        XCTAssertEqual(KeyHints.hint(";"), "Right pinky, home row.")
        XCTAssertEqual(KeyHints.hint("Q"), "Left pinky, top row. Hold Shift with your right pinky.")
        XCTAssertEqual(KeyHints.hint("6"), "Right index finger, number row.")
        XCTAssertEqual(KeyHints.hint(" "), "Either thumb.")
        XCTAssertEqual(KeyHints.phonetic("m"), "mike")
    }

    func testPrompts() {
        let trainer = TypingTrainer()
        XCTAssertEqual(trainer.prompt(for: "sad"), "sad: s, a, d")
        XCTAssertEqual(trainer.prompt(for: "f"), "f, foxtrot. Left index finger, home row. It has a bump.")
        XCTAssertEqual(trainer.prompt(for: "f"), "f, foxtrot")
    }
}
