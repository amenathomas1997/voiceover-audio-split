// Tests for the fixes that followed the third audit: sound work off the main thread,
// stereo pairs, voice commands during calls on loudspeakers, secret clipboard text, the
// installer's version, sentence numbers, counted phrases and network size limits.

import AVFoundation
import CoreAudio
import XCTest
@testable import VoiceOverAudioSplit

final class StereoPairTests: XCTestCase {
    override func tearDown() {
        Mixer.sources = []
        Mixer.speechDeviceChannel = nil
        Mixer.mainStereo = (0, 1)
        Mixer.speechStereo = (0, 1)
        Mixer.state = Mixer.State()
    }

    func testCoreAudioChannelNumbersBecomeOurs() {
        XCTAssertTrue(validStereo(left: 1, right: 2, channels: 2) == (0, 1))
        XCTAssertTrue(validStereo(left: 3, right: 4, channels: 8) == (2, 3))
        XCTAssertTrue(validStereo(left: 2, right: 1, channels: 2) == (1, 0), "swapped ears are respected")
        // Anything odd falls back to the first two.
        XCTAssertTrue(validStereo(left: 0, right: 2, channels: 2) == (0, 1))
        XCTAssertTrue(validStereo(left: 3, right: 3, channels: 8) == (0, 1))
        XCTAssertTrue(validStereo(left: 7, right: 9, channels: 8) == (0, 1))
        XCTAssertTrue(validStereo(left: 1, right: 2, channels: 1) == (0, 1))
    }

    func testEarsGoToTheDevicesStereoPair() {
        Mixer.sources = [.speech, .others]
        Mixer.state = Mixer.State(split: .left)
        Mixer.mainStereo = (2, 3)
        // Speech in the left ear, which is the device's third channel.
        XCTAssertEqual(Mixer.route(source: 0, channel: 2).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 0).fromLeft, 0, "not on the first two channels")
        XCTAssertEqual(Mixer.route(source: 0, channel: 3).fromLeft, 0)
        // Other sounds in the right ear, the fourth.
        XCTAssertEqual(Mixer.route(source: 1, channel: 3).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromLeft, 0)
    }

    func testSpeechDeviceHasItsOwnPair() {
        Mixer.sources = [.speech, .others]
        Mixer.state = Mixer.State(split: .left)
        Mixer.speechDeviceChannel = 2
        Mixer.speechStereo = (2, 3)
        // The speech device starts at channel 2 and plays stereo on its third and fourth.
        XCTAssertEqual(Mixer.route(source: 0, channel: 4).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 5).fromLeft, 0.5)
        XCTAssertEqual(Mixer.route(source: 0, channel: 2).fromLeft, 0)
        // Other sounds stay on the main device, in stereo.
        XCTAssertEqual(Mixer.route(source: 1, channel: 0).fromLeft, 1)
        XCTAssertEqual(Mixer.route(source: 1, channel: 1).fromRight, 1)
    }
}

final class OffMainThreadTests: XCTestCase {
    private let silence: AVAudioSourceNodeRenderBlock = { _, _, _, _ in noErr }

    func testStoppingASplitAnswersWithoutBlocking() {
        let splitter = Splitter(configuration: SplitConfiguration(speechDeviceUID: nil, callMode: .split, callAppPrefixes: [], appRuleIDs: []))
        let stopped = expectation(description: "stopped")
        let began = Date()
        splitter.stop { stopped.fulfill() }
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.5, "stop returns at once")
        wait(for: [stopped], timeout: 10)
        // Waiting at quit comes back as soon as the work is done, well within its limit.
        let waited = Date()
        splitter.stopAndWait(seconds: 5)
        XCTAssertLessThan(Date().timeIntervalSince(waited), 4)
    }

    func testAToneThatCantStartSaysSoOnTheMainThread() {
        let answered = expectation(description: "answered")
        // No sample rate: refused before any sound engine is touched.
        LiveTone("test").start(sampleRate: 0, channels: 2, render: silence, done: { playing in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(playing)
            answered.fulfill()
        })
        wait(for: [answered], timeout: 10)
    }

    func testAToneStoppedBeforeItStartsNeverPlays() {
        let tone = LiveTone("test-overtaken")
        let answered = expectation(description: "answered")
        tone.start(sampleRate: 44100, channels: 2, render: silence, done: { playing in
            XCTAssertFalse(playing, "the stop came first, so no engine was opened")
            answered.fulfill()
        })
        tone.stop()
        wait(for: [answered], timeout: 10)
    }
}

final class VoiceGuardTests: XCTestCase {
    private let headphones: UInt32 = 0x6864_706E, speakers: UInt32 = 0x6973_706B

    func testWhatCountsAsHeadphones() {
        let builtIn = kAudioDeviceTransportTypeBuiltIn, bluetooth = kAudioDeviceTransportTypeBluetooth
        let usb = kAudioDeviceTransportTypeUSB, display = kAudioDeviceTransportTypeDisplayPort
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "MacBook Pro Speakers", transport: builtIn, dataSource: speakers))
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "MacBook Pro-Lautsprecher", transport: builtIn, dataSource: speakers))
        XCTAssertTrue(VoiceGuard.isHeadphones(name: "External Headphones", transport: builtIn, dataSource: 0))
        XCTAssertTrue(VoiceGuard.isHeadphones(name: "Built-in Output", transport: builtIn, dataSource: headphones))
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "Built-in Output", transport: builtIn, dataSource: speakers))
        XCTAssertTrue(VoiceGuard.isHeadphones(name: "G435 Wireless Gaming Headset", transport: usb, dataSource: 0))
        XCTAssertTrue(VoiceGuard.isHeadphones(name: "Amena's AirPods Pro", transport: bluetooth, dataSource: 0))
        XCTAssertTrue(VoiceGuard.isHeadphones(name: "WH-1000XM5", transport: bluetooth, dataSource: 0), "Bluetooth is mostly headsets")
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "JBL Flip 6 Speaker", transport: bluetooth, dataSource: 0))
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "Jabra Speak 510", transport: usb, dataSource: 0))
        // Not clearly headphones: treated as loudspeakers, the careful way to be wrong.
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "Scarlett 2i2", transport: usb, dataSource: 0))
        XCTAssertFalse(VoiceGuard.isHeadphones(name: "LG UltraFine", transport: display, dataSource: 0))
    }

    func testRiskyCommandsAreMarked() {
        let guarded = Set(VoiceCommands.all.filter(\.guarded).flatMap(\.phrases))
        for phrase in ["unmute me", "camera on", "toggle mute", "record the screen", "leave the meeting", "unmute", "next output device"] {
            XCTAssertTrue(guarded.contains(phrase), phrase)
        }
        // Commands that hide you or only tell you something stay available.
        for phrase in ["mute me", "camera off", "stop recording", "am i muted", "quiet everything"] {
            XCTAssertFalse(guarded.contains(phrase), phrase)
        }
    }

    func testAFileCantSwitchTheGuardOff() {
        XCTAssertTrue(SettingsTransfer.isHeld("voiceCommandGuard", false, current: nil))
        XCTAssertFalse(SettingsTransfer.isHeld("voiceCommandGuard", true, current: false))
    }
}

final class SecretClipboardTests: XCTestCase {
    func testPasswordManagersMarksAreSecret() {
        XCTAssertTrue(Clipboard.isSecret(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(Clipboard.isSecret(types: ["com.agilebits.onepassword"]))
        XCTAssertFalse(Clipboard.isSecret(types: ["public.utf8-plain-text"]))
        // Passing through (a text expander's snippet) isn't secret: asked for, it's read.
        XCTAssertFalse(Clipboard.isSecret(types: ["public.utf8-plain-text", "org.nspasteboard.TransientType"]))
    }
}

final class InstallerVersionTests: XCTestCase {
    /// Two tiny archives made with the system's own xar tool, each holding a Distribution
    /// file: one stored compressed, as installer packages are, and one stored plain.
    private let compressed = "eGFyIQAcAAEAAAAAAAACVQAAAAAAAAcJAAAAAXja7FVNj5swEL3vr0DcKfYAtokc9tBqr72kl94cewhWA0TgbLP762sD2XS1yaqt1J56Ymb8/Ib5eLK8P7X76BGH0fbdOqYfSBxhp3tju906/rJ5SER8X93Jkxqqu0i6XvtPJPWAyvkbibMtVkCAJZQmABsCq5ysAGT6GjJdalB/G49tNLqnPa7jsVE0DieR7Ot6RFcRmS7WFB3tcyCX6WQEivTMMXm13WNkzTqGhcYopyYrknvsdq6pSpku1hxe6Cnjr1ItuegllQ+d+3D+X3U47K2eikpPye7ZHuL0DD25QWmHJrleJKU1U0agLkBBKXK1Vao2XGfbgrKCZFwUGgj3bXvLtKRQg27s480MvMw1KwwHVucCRF4w8PwllJRqToxgKDIE9M18QzT3Ln1pnnywncHhYxggbpbp+XCnun5E3XdmDJP62Z0B06RpSUhCaELIhparwi9DLtPzDvg0V8mlvrVIX/3ML7fbd2DtBabegakLbDf0x0P1vUHcy3R25rg1ocDwmfzjiEOlWuyUa/pWjTKdIvOZBxXEL87xjG57gxVhuS97MufNxEersevD5nEOmad/CU0A2wVsLkq/DYFu9qcj93TAKuy672Mw7+Zh+Co+uwaHMIlFYWlAvZYGvSkNmvPr4gByVRui+FvqgDpDqkxpMkJgC5nKM6LzQjHBaKFVvdUso1ywP1cHaEKV5kIwyKjhLNO1KMCrTxhT1hyoUNr/RPkv1QGwKtiKkP/q+E11kF9Uxyc7usFuj2Elr4jE48NrJtPpbfsBAAD//wMAoMoTMBSVPUwdxKaWOjy3gO98IqROkyt0eNptjkEKwjAQRfeeIsR10zQKKqQB8QAuCt2X6bQMppmQJj2/irpz/Xjvf0thzYP3mKq5ULVCopjFQqGLCD2mlTi0spHOxsdcJZwEja0EXtRUvAdK4HHIqmcCvG+YrmUk7qKnrF6CFNsvcVFnZbQ56UYbfdBHKTjcOIAvHx44oHT7Ica3aOvvnLP1v4du9wTA/0AfeNqrAAAAeQB5"
    private let plain = "eGFyIQAcAAEAAAAAAAAB1QAAAAAAAAP0AAAAAXjarFNNk9sgDL3nV3h8d/nwR5wMYQ/t7C9IL70RkGOmNmQMSbP99QVsb7qz2z31hCSeHk9IYk/3cchuMDltzSEnX3CegZFWaXM+5N+Pz0WbP/ENu4uJbzLmrQxHxuQEwoeMwusROMW0KQgpKD1iuq/wnlKG3kJSUg/yp7uOmfMvAxxy1wuSx5uM2a5z4DlmaLFS1OnfkZyhZEQKtHIkr9MDZFoF2QuNEl4kK2MDmLPvOWlrhhZ7vlirW1WIy2XQMklFVnrwhfNB+pijJWFRRN+KW9Ql/lVeZL/7SQQWVXxcLe1KIELtVIkxPdFSVCWWVS2atiG1FN1JNiXZtg1D75mWJ8Qke337Dy+8I5o/Eb3+InvWRsH0NXYSjksbQ9gIYx1Ia5SLLfvbnQGp5WSHcYFJgfGR0n3d7HHArsMQnvmQnMl/TdSP0PxH9vgJbHzAxCcw8YCdJ3u98F89wMDQ7MxxrWKB8Uj+1cHExQhG+N6OwjGUIvNdANWYhNCKHq0CjpuqCpKiOY8o3LQEYzlpttstLQP9aygBtInYqt3VuIw/Nvvpyr9cgMehD/8Yzc3cjFDFNx2GVp+ucYpjQ5aNQxEc9xalxWUorfEfAAAA//8DAIFRK/cvWxkfdzEXouUrUQapaIC8yWNhcTxpbnN0YWxsZXItZ3VpLXNjcmlwdCBtaW5TcGVjVmVyc2lvbj0iMSI+PHBrZy1yZWYgaWQ9ImNvbS5mdWxsY2lyY2xlYXQuVm9pY2VPdmVyQXVkaW9TcGxpdC5wa2ciIHZlcnNpb249IjkuOC4yMDI3MDEwMjAzMDQiIG9uQ29uY2x1c2lvbj0ibm9uZSI+I2FwcC5wa2c8L3BrZy1yZWY+PC9pbnN0YWxsZXItZ3VpLXNjcmlwdD4K"

    private func file(_ base64: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).pkg")
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testVersionIsReadStraightFromThePackage() throws {
        for archive in [compressed, plain] {
            let url = try file(archive)
            let text = try XCTUnwrap(Xar.file(named: "Distribution", in: url).flatMap { String(data: $0, encoding: .utf8) })
            XCTAssertTrue(text.hasPrefix("<installer-gui-script"))
            XCTAssertEqual(UpdateCheck.packageVersion(of: url), "9.8.202701020304")
            XCTAssertNil(Xar.file(named: "Missing", in: url))
        }
    }

    func testAnythingElseIsUnreadable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).pkg")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try Data("not a package at all, just some text that is long enough".utf8).write(to: url)
        XCTAssertNil(UpdateCheck.packageVersion(of: url))
        // The right first four bytes, then nonsense.
        try (Data("xar!".utf8) + Data(repeating: 0xFF, count: 64)).write(to: url)
        XCTAssertNil(UpdateCheck.packageVersion(of: url))
        // A real archive cut short.
        try XCTUnwrap(Data(base64Encoded: compressed)).prefix(200).write(to: url)
        XCTAssertNil(UpdateCheck.packageVersion(of: url))
        XCTAssertNil(UpdateCheck.packageVersion(of: url.appendingPathExtension("missing")))
    }

    func testTooBigForItsLimitIsRefused() throws {
        let url = try file(compressed)
        XCTAssertNil(Xar.file(named: "Distribution", in: url, limit: 50))
    }
}

final class SentenceNumberTests: XCTestCase {
    func testAbbreviationsDontStartSentences() {
        XCTAssertEqual(TextCompare.sentenceNumbers(ofWordsIn: "Dr. Lee came home. He slept."), [1, 1, 1, 1, 2, 2])
        XCTAssertEqual(TextCompare.sentenceNumbers(ofWordsIn: "We met at 3 p.m. today. It rained."), [1, 1, 1, 1, 1, 1, 2, 2])
        XCTAssertEqual(TextCompare.sentenceNumbers(ofWordsIn: "  One.\n\nTwo? Three!  "), [1, 2, 3])
        XCTAssertEqual(TextCompare.sentenceNumbers(ofWordsIn: ""), [])
    }

    func testAChangeIsReportedInItsOwnSentence() {
        let changes = TextCompare.changes(from: "Dr. Lee came home. He slept.", to: "Dr. Lee came home. He rested.")
        XCTAssertEqual(changes.map(\.sentence), [2], "the second sentence, not the third")
    }
}

final class CountedPhraseTests: XCTestCase {
    func testOneOfSomethingIsSingular() {
        XCTAssertEqual(String(localized: "\(1) changes"), "1 change")
        XCTAssertEqual(String(localized: "\(2) changes"), "2 changes")
        XCTAssertEqual(String(localized: "\(0) changes"), "0 changes")
    }

    func testTheNumberNeedNotComeFirst() {
        XCTAssertEqual(String(localized: "\("Notes") loaded. \(1) paragraphs."), "Notes loaded. 1 paragraph.")
        XCTAssertEqual(String(localized: "\("Notes") loaded. \(4) paragraphs."), "Notes loaded. 4 paragraphs.")
        XCTAssertEqual(String(localized: "\(1) of \(12) lessons done"), "1 of 12 lessons done")
    }

    func testTwoNumbersEachDecideTheirOwnWord() {
        XCTAssertEqual(String(localized: "\(3) labels, \(1) place markers"), "3 labels, 1 place marker")
        XCTAssertEqual(String(localized: "\(1) labels, \(2) place markers"), "1 label, 2 place markers")
        XCTAssertEqual(String(localized: "Battery \(80) percent, about \(1) hours \(1) minutes left"),
                       "Battery 80 percent, about 1 hour 1 minute left")
    }

    func testOtherLanguagesToo() throws {
        func bundle(_ language: String) throws -> Bundle {
            try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))))
        }
        let german = Locale(identifier: "de"), french = Locale(identifier: "fr"), spanish = Locale(identifier: "es")
        XCTAssertEqual(String(localized: "\(1) changes", bundle: try bundle("de"), locale: german), "1 Änderung")
        XCTAssertEqual(String(localized: "\(3) changes", bundle: try bundle("de"), locale: german), "3 Änderungen")
        XCTAssertEqual(String(localized: "\("Notizen") loaded. \(1) paragraphs.", bundle: try bundle("de"), locale: german),
                       "Notizen geladen. 1 Absatz.")
        // French counts none as one.
        XCTAssertEqual(String(localized: "\(0) changes", bundle: try bundle("fr"), locale: french), "0 modification")
        XCTAssertEqual(String(localized: "\(2) changes", bundle: try bundle("fr"), locale: french), "2 modifications")
        XCTAssertEqual(String(localized: "\(1) labels, \(2) place markers", bundle: try bundle("es"), locale: spanish),
                       "1 etiqueta, 2 marcadores de lugar")
    }
}

final class NetLimitTests: XCTestCase {
    func testAnAnswerOverItsLimitIsRefused() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x20, count: 5000).write(to: url)
        let whole = try await Net.data(from: url, limit: 5000)
        XCTAssertEqual(whole.count, 5000)
        do {
            _ = try await Net.data(from: url, limit: 4999)
            XCTFail("more than the limit came through")
        } catch {
            XCTAssertTrue(error is Net.TooLarge)
        }
    }
}
