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
