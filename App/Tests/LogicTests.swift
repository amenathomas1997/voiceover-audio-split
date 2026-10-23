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
        let keys = Command.allCases.map(\.defaultKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two commands share a default key")
    }

    func testDefaultKeysAreAssignableAndAvoidReservedKeys() {
        for command in Command.allCases {
            XCTAssertNotNil(Key.named(command.defaultKey), "\(command) has a key Settings can't show")
            XCTAssertNil(Key.presetDigits[command.defaultKey], "\(command) uses a preset digit")
            XCTAssertNotEqual(command.defaultKey, Key.slash, "\(command) uses the layer help key")
        }
    }

    func testCustomKeyReplacesDefault() {
        KeyMap.update(custom: [Command.systemStatus.rawValue: 40]) // K
        XCTAssertEqual(KeyMap.commandForKey[40], .systemStatus)
        XCTAssertNil(KeyMap.commandForKey[Command.systemStatus.defaultKey])
        XCTAssertEqual(KeyMap.key(for: .systemStatus)?.name, "K")
        // K is also the default for restarting VoiceOver: the chosen key wins.
        XCTAssertNil(KeyMap.key(for: .rescueVoiceOver))
    }

    func testLayerHelpListsEveryCommand() {
        let spoken = KeyMap.spokenList
        for command in Command.allCases {
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
