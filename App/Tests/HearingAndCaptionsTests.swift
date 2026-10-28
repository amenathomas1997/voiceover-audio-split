import XCTest
@testable import VoiceOverAudioSplit

final class HearingProfileTests: XCTestCase {
    func testHalfGainRuleWithLimit() {
        // Normal hearing (up to 20 dB) needs no boost; then half the loss, up to 25 dB.
        XCTAssertEqual(HearingProfile.gains(for: [0, 20, 30, 50, 70, 90]), [0, 0, 5, 15, 25, 25])
    }

    func testMalformedProfilesAreFlat() {
        XCTAssertEqual(HearingProfile.valid(nil), [0, 0, 0, 0, 0, 0])
        XCTAssertEqual(HearingProfile.valid([10, 20]), [0, 0, 0, 0, 0, 0], "the wrong number of bands")
        XCTAssertEqual(HearingProfile.valid([-5, 200, .nan, 10, 20, 30]), [0, 90, 0, 10, 20, 30], "kept between 0 and 90")
    }

    func testListeningTestResultsAreRelativeToTheBestBand() {
        let losses = HearingProfile.losses(fromThresholds: [-60, -60, -65, -50, -40, -30], best: -65)
        XCTAssertEqual(losses, [5, 5, 0, 15, 25, 35])
    }

    func testSummaryNamesBoostedBands() {
        let summary = HearingProfile.summary(left: [0, 0, 0, 30, 40, 50], right: [0, 0, 0, 0, 0, 0])
        XCTAssertTrue(summary.contains("2 kHz") && summary.contains("8 kHz"), summary)
        XCTAssertTrue(summary.contains("no boost needed"), summary)
    }

    func testBandNames() {
        XCTAssertEqual(HearingProfile.name(250), "250 Hz")
        XCTAssertEqual(HearingProfile.name(4000), "4 kHz")
    }
}

final class CallCaptionsTests: XCTestCase {
    func testNoCallAppsMeansNothingToCaption() {
        XCTAssertTrue(CallCaptions.callProcesses(prefixes: ["com.example.not-a-real-call-app"]).isEmpty)
    }

    func testVoiceCommandsReachCaptionsAndHearing() {
        let all = VoiceCommands.all
        XCTAssertEqual(VoiceCommands.match("call captions", in: all)?.name, "Call captions")
        XCTAssertEqual(VoiceCommands.match("what did they say", in: all)?.name, "What did they say?")
        XCTAssertEqual(VoiceCommands.match("hearing test", in: all)?.name, "Hearing profile")
    }
}

final class NewVoiceRoutingTests: XCTestCase {
    func testObjectRequestsDontTakeDoItForMe() {
        XCTAssertEqual(VoiceCommands.objectRequest(in: "look for my cup"), "look for my cup")
        XCTAssertEqual(VoiceCommands.objectRequest(in: "Where are my glasses?"), "where are my glasses")
        XCTAssertNotNil(VoiceCommands.objectRequest(in: "look for the word exit"))
        XCTAssertNil(VoiceCommands.objectRequest(in: "find the search field"), "find stays with Do It for Me")
        XCTAssertNil(VoiceCommands.objectRequest(in: "look for"))
    }

    func testRemindersAreRecognized() {
        XCTAssertTrue(VoiceCommands.isReminder("set a timer for 10 minutes"))
        XCTAssertTrue(VoiceCommands.isReminder("remind me at 3 to call the doctor"))
        XCTAssertTrue(VoiceCommands.isReminder("pon un temporizador de 5 minutos"))
        XCTAssertFalse(VoiceCommands.isReminder("what time is it"))
    }

    func testMeetingAndToolPhrases() {
        let all = VoiceCommands.all
        XCTAssertEqual(VoiceCommands.match("am i muted", in: all)?.name, "Am I muted?")
        XCTAssertEqual(VoiceCommands.match("raise my hand", in: all)?.name, "Raise my hand")
        XCTAssertNotNil(VoiceCommands.match("leave the meeting", in: all)?.confirm, "leaving asks first")
        XCTAssertEqual(VoiceCommands.match("switch window", in: all)?.name, "Switch window")
        XCTAssertEqual(VoiceCommands.match("unmute my microphone", in: all)?.name, "Unmute", "the microphone command still wins")
    }
}

final class StudentVoiceTests: XCTestCase {
    func testStudentNames() {
        XCTAssertEqual(VoiceCommands.studentName(in: "switch student to Maria"), "maria")
        XCTAssertEqual(VoiceCommands.studentName(in: "Change student to José Luis."), "jose luis")
        XCTAssertNil(VoiceCommands.studentName(in: "switch student to"))
        XCTAssertNil(VoiceCommands.studentName(in: "switch window"))
    }
}

final class PermissionHelpTests: XCTestCase {
    func testEveryPermissionButSystemAudioCanAsk() {
        XCTAssertEqual(Permission.allCases.filter { !$0.canAsk }, [.systemAudio], "system audio is asked for by turning the split on")
    }

    func testVoiceOverSetupSaysWhatsMissing() {
        XCTAssertTrue(VoiceOverSetup.message(.voiceOverOff).contains("Command F5"))
        XCTAssertTrue(VoiceOverSetup.message(.notAllowed).contains("Automation"))
        XCTAssertTrue(VoiceOverSetup.message(.appleScriptOff).contains("VoiceOver Utility"))
        XCTAssertTrue(VoiceOverSetup.message(.working).hasPrefix("Working"))
    }
}

final class SoundSafetyTests: XCTestCase {
    override func setUp() {
        SoundSafety.shared.discard()
        SoundSafety.shared.runsInTests = true
    }

    override func tearDown() {
        SoundSafety.shared.runsInTests = false
        SoundSafety.shared.discard()
    }

    func testGoingBackRestoresEverySettingFromBeforeTheChanges() {
        let preferences = Preferences.shared
        let savedEar = preferences.oneEar, savedLimit = preferences.volumeLimitLevel, savedConfirm = preferences.confirmSoundChanges
        defer {
            SoundSafety.shared.runsInTests = false
            preferences.oneEar = savedEar
            preferences.volumeLimitLevel = savedLimit
            preferences.confirmSoundChanges = savedConfirm
        }
        preferences.confirmSoundChanges = true
        preferences.oneEar = .off
        preferences.volumeLimitLevel = -6
        SoundSafety.shared.keep() // Start clean.
        preferences.oneEar = .left
        preferences.oneEar = .right // Changed twice: going back returns to the first value.
        preferences.volumeLimitLevel = -20
        XCTAssertTrue(SoundSafety.shared.isWaiting)
        XCTAssertEqual(SoundSafety.shared.changes, ["one-ear mode", "the volume limit"])
        SoundSafety.shared.undo()
        XCTAssertEqual(preferences.oneEar, .off)
        XCTAssertEqual(preferences.volumeLimitLevel, -6)
        XCTAssertFalse(SoundSafety.shared.isWaiting, "going back doesn't ask about itself")
    }

    func testKeepingKeepsAndAutomaticChangesDontAsk() {
        let preferences = Preferences.shared
        let savedBalance = preferences.earBalance
        defer { preferences.earBalance = savedBalance }
        preferences.earBalance = 3
        SoundSafety.shared.keep()
        XCTAssertEqual(preferences.earBalance, 3)
        XCTAssertFalse(SoundSafety.shared.isWaiting)
        SoundSafety.shared.withoutAsking { preferences.earBalance = 5 }
        XCTAssertFalse(SoundSafety.shared.isWaiting, "automatic presets don't ask")
    }

    func testTurnedOffNeverAsks() {
        let preferences = Preferences.shared
        let saved = (preferences.confirmSoundChanges, preferences.layout)
        defer { preferences.confirmSoundChanges = saved.0; preferences.layout = saved.1 }
        preferences.confirmSoundChanges = false
        preferences.layout = preferences.layout == .opposite ? .speechBoth : .opposite
        XCTAssertFalse(SoundSafety.shared.isWaiting)
    }
}

final class ExceptionCatchingTests: XCTestCase {
    func testObjectiveCExceptionsBecomeErrors() {
        var error: NSError?
        let ok = VOACatchException({
            NSException(name: .invalidArgumentException, reason: "required condition is false: format", userInfo: nil).raise()
        }, &error)
        XCTAssertFalse(ok)
        XCTAssertEqual(error?.localizedDescription, "required condition is false: format")
        XCTAssertTrue(VOACatchException({ _ = 1 + 1 }, nil))
    }
}

final class OnDeviceAITests: XCTestCase {
    func testClaudeMessagesBecomeOnePromptWithPictures() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let png = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
        let messages: [[String: Any]] = [
            ["role": "user", "content": [["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]],
                                         ["type": "text", "text": "Describe this."]]],
            ["role": "assistant", "content": [["type": "text", "text": "A red square."]]],
            ["role": "user", "content": "What color is it?"],
        ]
        let parts = OnDeviceAI.parts(of: messages)
        XCTAssertEqual(parts.count, 4)
        guard case .image = parts[0] else { return XCTFail("the picture comes first") }
        guard case .text(let answer) = parts[2], case .text(let last) = parts[3] else { return XCTFail("texts") }
        XCTAssertTrue(answer.hasSuffix("A red square.") && answer != "A red square.", "earlier turns are labelled")
        XCTAssertEqual(last, "What color is it?", "the newest message as it is")
    }

    func testLongRequestsAreTrimmedKeepingTheNewest() {
        let old = String(repeating: "a", count: 8000), new = String(repeating: "b", count: 5000)
        let kept = OnDeviceAI.trimmed([.text(old), .text(new)])
        let total = kept.reduce(0) { sum, part in if case .text(let t) = part { sum + t.count } else { sum } }
        XCTAssertLessThanOrEqual(total, OnDeviceAI.maxCharacters + 2)
        guard case .text(let last) = kept.last else { return XCTFail() }
        XCTAssertEqual(last, new, "the newest text is kept whole")
    }

    func testTheModelIsToldTheRealVoiceOverKeys() {
        XCTAssertTrue(OnDeviceAI.voiceOverKeys.contains("VO U opens the rotor"))
        XCTAssertTrue(OnDeviceAI.voiceOverKeys.contains("don't guess"))
    }

    func testAutoDescribeSkipsIconsAndRemembersPictures() {
        XCTAssertFalse(AutoDescribe.isPictureSized(CGSize(width: 32, height: 32)))
        XCTAssertFalse(AutoDescribe.isPictureSized(CGSize(width: 300, height: 40)))
        XCTAssertTrue(AutoDescribe.isPictureSized(CGSize(width: 200, height: 150)))
        let frame = CGRect(x: 10.4, y: 20, width: 200, height: 150)
        XCTAssertEqual(AutoDescribe.key(pid: 7, frame: frame, name: "Beach"), AutoDescribe.key(pid: 7, frame: frame.offsetBy(dx: 0.3, dy: 0), name: "Beach"))
        XCTAssertNotEqual(AutoDescribe.key(pid: 7, frame: frame, name: "Beach"), AutoDescribe.key(pid: 7, frame: frame, name: "Dog"))
    }

    func testRecordingNamesSortByTime() {
        let morning = ScreenRecorder.fileName(at: Date(timeIntervalSince1970: 1_800_000_000))
        let later = ScreenRecorder.fileName(at: Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertTrue(morning.hasPrefix("Recording ") && morning.hasSuffix(".mov"))
        XCTAssertLessThan(morning, later)
        XCTAssertTrue(ScreenRecorder.folder.path.hasSuffix("Movies/VoiceOver Audio Split Recordings"))
        XCTAssertFalse(ScreenRecorder.folder.path.contains("/Containers/"), "the real Movies folder, not the app's own")
    }

    func testNewVoicePhrases() {
        let all = VoiceCommands.all
        XCTAssertEqual(VoiceCommands.match("can you see me", in: all)?.name, "Can you see me?")
        XCTAssertEqual(VoiceCommands.match("start recording", in: all)?.name, "Record the screen")
        XCTAssertEqual(VoiceCommands.match("describe images automatically", in: all)?.name, "Describe images automatically")
    }
}
