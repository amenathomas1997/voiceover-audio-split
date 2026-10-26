// MeetingHelpersTests.swift — the name matching and state reading behind the
// Zoom, Teams and FaceTime commands, in several languages. No meeting app needed.

import XCTest
@testable import VoiceOverAudioSplit

final class MeetingHelpersTests: XCTestCase {
    // MARK: Normalizing

    func testNormalizeDropsShortcutHintsAccentsAndCase() {
        XCTAssertEqual(MeetingHelpers.normalize("Mute (⌘+Shift+M)"), "mute")
        XCTAssertEqual(MeetingHelpers.normalize("  Réactiver   le son. "), "reactiver le son")
        XCTAssertEqual(MeetingHelpers.normalize("Unmute audio, Command Shift A"), "unmute audio")
        XCTAssertEqual(MeetingHelpers.normalize("Désactiver l’audio"), "desactiver l'audio")
        XCTAssertEqual(MeetingHelpers.normalize("Leave - ⌘⇧H"), "leave")
    }

    func testAppsFromBundleIDs() {
        XCTAssertEqual(MeetingApp(bundleID: "us.zoom.xos"), .zoom)
        XCTAssertEqual(MeetingApp(bundleID: "com.microsoft.teams2"), .teams)
        XCTAssertEqual(MeetingApp(bundleID: "com.microsoft.teams"), .teams)
        XCTAssertEqual(MeetingApp(bundleID: "com.apple.FaceTime"), .faceTime)
        XCTAssertNil(MeetingApp(bundleID: "com.apple.Safari"))
    }

    // MARK: Mute state

    func testZoomMuteStateInEachLanguage() {
        let cases: [(String, MuteState)] = [
            ("Mute audio", .unmuted), ("Unmute audio", .muted), ("Mute my microphone", .unmuted),
            ("Unmute My Audio", .muted),
            ("Silenciar", .unmuted), ("Reactivar audio", .muted), ("Activar audio", .muted),
            ("Couper le son", .unmuted), ("Réactiver le son", .muted), ("Désactiver l'audio", .unmuted),
            ("Activer l’audio", .muted),
            ("Stummschalten", .unmuted), ("Stummschaltung aufheben", .muted), ("Audio-Stummschaltung aufheben", .muted),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: name, app: .zoom), expected, name)
        }
    }

    func testTeamsMuteStateFromNamesWithShortcuts() {
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mute (⌘+Shift+M)", app: .teams), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Unmute (⌘+Shift+M)", app: .teams), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Unmute mic", app: .teams), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Désactiver le micro", app: .teams), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Activer le micro", app: .teams), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Silenciar micrófono", app: .teams), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Reactivar micrófono", app: .teams), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mikrofon stummschalten", app: .teams), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Stummschaltung aufheben", app: .teams), .muted)
    }

    func testTeamsMicToggleUsesItsValue() {
        // The new Teams' "Mic" toggle: on (1) means you can be heard.
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mic", app: .teams, value: 1), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mic", app: .teams, value: 0), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mikrofon", app: .teams, value: 0), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Micrófono", app: .teams, value: 1), .unmuted)
        XCTAssertNil(MeetingHelpers.muteState(fromButtonName: "Mic", app: .teams), "no value, no state")
    }

    func testFaceTimeMuteToggle() {
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mute", app: .faceTime, value: 1), .muted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Mute", app: .faceTime, value: 0), .unmuted)
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Stummschalten", app: .faceTime, value: 1), .muted)
        XCTAssertNil(MeetingHelpers.muteState(fromButtonName: "Mute", app: .faceTime))
        XCTAssertEqual(MeetingHelpers.muteState(fromButtonName: "Unmute", app: .faceTime), .muted)
    }

    func testOtherPeoplesMuteButtonsAreNotYours() {
        for name in ["Mute all", "Mute participant", "Unmute all", "Ask all to unmute", "Silenciar a todos",
                     "Couper le son de tous", "Alle stummschalten", "Mute notifications"] {
            for app in MeetingApp.allCases {
                XCTAssertNil(MeetingHelpers.muteState(fromButtonName: name, app: app), "\(name) in \(app)")
            }
        }
    }

    func testMostSpecificNameWins() {
        let specific = MeetingHelpers.matchIndex(.mute, names: ["Unmute audio"], app: .zoom)!
        let generic = MeetingHelpers.matchIndex(.mute, names: ["Unmute"], app: .zoom)!
        XCTAssertLessThan(specific, generic)
    }

    func testAnyOfSeveralNamesCanMatch() {
        // Title empty, description is the name, help has something else.
        XCTAssertEqual(MeetingHelpers.state(of: .mute, names: ["", "Unmute audio", "Click to unmute"], value: nil, app: .zoom), true)
    }

    // MARK: Video, hand, chat, leave

    func testVideoState() {
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Stop video"], value: nil, app: .zoom), true)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Start Video"], value: nil, app: .zoom), false)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Arrêter la vidéo"], value: nil, app: .zoom), true)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Iniciar video"], value: nil, app: .zoom), false)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Video beenden"], value: nil, app: .zoom), true)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Turn camera off (⌘+Shift+O)"], value: nil, app: .teams), true)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Kamera einschalten"], value: nil, app: .teams), false)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Camera"], value: 1, app: .teams), true)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Caméra"], value: 0, app: .teams), false)
        XCTAssertEqual(MeetingHelpers.state(of: .video, names: ["Video"], value: 1, app: .faceTime), true)
    }

    func testHandState() {
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Raise hand"], value: nil, app: .zoom), false)
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Lower hand"], value: nil, app: .zoom), true)
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Bajar la mano"], value: nil, app: .zoom), true)
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Lever la main"], value: nil, app: .teams), false)
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Raise (⌘+Shift+K)"], value: nil, app: .teams), false)
        XCTAssertEqual(MeetingHelpers.state(of: .hand, names: ["Hand senken"], value: nil, app: .teams), true)
        XCTAssertNil(MeetingHelpers.matchIndex(.hand, names: ["Raise hand"], app: .faceTime), "FaceTime has no hands")
    }

    func testChatAndLeaveButtonsAreFoundButHaveNoState() {
        XCTAssertNotNil(MeetingHelpers.matchIndex(.chat, names: ["Chat"], app: .zoom))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.chat, names: ["Show conversation"], app: .teams))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.chat, names: ["Afficher la conversation"], app: .teams))
        XCTAssertNil(MeetingHelpers.state(of: .chat, names: ["Chat"], value: 1, app: .zoom))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.leave, names: ["Leave (⌘+Shift+H)"], app: .teams))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.leave, names: ["Colgar"], app: .teams))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.leave, names: ["End"], app: .zoom))
        XCTAssertNotNil(MeetingHelpers.matchIndex(.leave, names: ["Beenden"], app: .faceTime))
        XCTAssertNil(MeetingHelpers.matchIndex(.leave, names: ["Leave breakout room"], app: .zoom))
    }

    func testLeaveConfirmationNeverEndsTheMeetingForEveryone() {
        XCTAssertTrue(MeetingHelpers.isLeaveConfirmation(["Leave Meeting"]))
        XCTAssertTrue(MeetingHelpers.isLeaveConfirmation(["Quitter la réunion"]))
        XCTAssertTrue(MeetingHelpers.isLeaveConfirmation(["Salir de la reunión"]))
        XCTAssertTrue(MeetingHelpers.isLeaveConfirmation(["Meeting verlassen"]))
        XCTAssertFalse(MeetingHelpers.isLeaveConfirmation(["End Meeting for All"]))
        XCTAssertFalse(MeetingHelpers.isLeaveConfirmation(["Finalizar la reunión para todos"]))
        XCTAssertFalse(MeetingHelpers.isLeaveConfirmation(["Leave"]), "the toolbar button would close the question")
    }

    func testEveryTableEntryIsNormalizedAndUnique() {
        for (app, controls) in MeetingHelpers.patterns {
            for (control, table) in controls {
                let texts = table.map(\.text)
                XCTAssertEqual(Set(texts).count, texts.count, "duplicate in \(app) \(control)")
                for text in texts { XCTAssertEqual(MeetingHelpers.normalize(text), text) }
                // A name can't say both a state and depend on the value.
                for pattern in table { XCTAssertFalse(pattern.state != nil && pattern.whenValueIsOne != nil) }
            }
        }
    }

    func testShortcutsMatchTheDocumentedKeys() {
        let zoomMute = MeetingHelpers.shortcuts[.zoom]?[.mute]
        XCTAssertEqual(zoomMute?.keyCode, 0) // A
        XCTAssertEqual(zoomMute?.flags, [.maskCommand, .maskShift])
        XCTAssertEqual(MeetingHelpers.shortcuts[.zoom]?[.hand]?.flags, [.maskAlternate])
        XCTAssertEqual(MeetingHelpers.shortcuts[.teams]?[.mute]?.keyCode, 46) // M
        XCTAssertNil(MeetingHelpers.shortcuts[.zoom]?[.leave], "no shortcut that might end the meeting for all")
        XCTAssertTrue(MeetingHelpers.shortcuts[.faceTime]?.isEmpty ?? true)
    }

    // MARK: Choosing the app and window

    func testRankingPrefersFrontThenLastUsedThenRecent() {
        let now = Date()
        let zoom = MeetingCandidate(bundleID: "us.zoom.xos", lastActive: now.addingTimeInterval(-60))
        let teams = MeetingCandidate(bundleID: "com.microsoft.teams2", lastActive: now)
        let faceTime = MeetingCandidate(bundleID: "com.apple.FaceTime")
        XCTAssertEqual(MeetingHelpers.rank([zoom, faceTime, teams]).map(\.bundleID),
                       ["com.microsoft.teams2", "us.zoom.xos", "com.apple.FaceTime"])

        var frontFaceTime = faceTime
        frontFaceTime.isFront = true
        XCTAssertEqual(MeetingHelpers.rank([zoom, teams, frontFaceTime]).first?.bundleID, "com.apple.FaceTime")

        var lastUsedZoom = zoom
        lastUsedZoom.isLastUsed = true
        XCTAssertEqual(MeetingHelpers.rank([teams, lastUsedZoom]).first?.bundleID, "us.zoom.xos")

        // Never seen active: Zoom, Teams, FaceTime; other apps are left out.
        let unseen = ["com.apple.FaceTime", "com.microsoft.teams", "com.apple.Safari", "us.zoom.xos"]
            .map { MeetingCandidate(bundleID: $0) }
        XCTAssertEqual(MeetingHelpers.rank(unseen).map(\.bundleID), ["us.zoom.xos", "com.microsoft.teams", "com.apple.FaceTime"])
    }

    func testMeetingWindowTitles() {
        XCTAssertTrue(MeetingHelpers.windowTitleLooksLikeMeeting("Zoom Meeting", app: .zoom))
        XCTAssertTrue(MeetingHelpers.windowTitleLooksLikeMeeting("Reunión de Zoom", app: .zoom))
        XCTAssertFalse(MeetingHelpers.windowTitleLooksLikeMeeting("Zoom Workplace", app: .zoom))
        XCTAssertTrue(MeetingHelpers.windowTitleLooksLikeMeeting("Weekly sync | Meeting | Microsoft Teams", app: .teams))
        XCTAssertTrue(MeetingHelpers.windowTitleLooksLikeMeeting("Réunion | Microsoft Teams", app: .teams))
    }

    func testChatListNames() {
        XCTAssertTrue(MeetingHelpers.isChatListName("Meeting Chat"))
        XCTAssertTrue(MeetingHelpers.isChatListName("Chat messages"))
        XCTAssertTrue(MeetingHelpers.isChatListName("Mensajes"))
        XCTAssertTrue(MeetingHelpers.isChatListName("Besprechungschat"))
        XCTAssertFalse(MeetingHelpers.isChatListName("Participants"))
    }

    // MARK: Who is talking

    func testSpeakersInEachLanguage() {
        XCTAssertEqual(MeetingHelpers.speaker(in: "Ana López, speaking, muted"), "Ana López")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Bob Smith is talking"), "Bob Smith")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Active speaker: Chen Wei"), "Chen Wei")
        XCTAssertEqual(MeetingHelpers.speaker(in: "María está hablando"), "María")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Orador activo: Luis"), "Luis")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Élodie parle"), "Élodie")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Jean est en train de parler"), "Jean")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Jürgen spricht"), "Jürgen")
        XCTAssertEqual(MeetingHelpers.speaker(in: "Aktiver Sprecher: Petra"), "Petra")
    }

    func testThingsThatAreNotSpeakers() {
        XCTAssertNil(MeetingHelpers.speaker(in: "Ana, not speaking"))
        XCTAssertNil(MeetingHelpers.speaker(in: "Jean ne parle pas"))
        XCTAssertNil(MeetingHelpers.speaker(in: "Speaking time"))
        XCTAssertNil(MeetingHelpers.speaker(in: "Speaking"))
        XCTAssertNil(MeetingHelpers.speaker(in: "Le parlement"), "only whole words")
        XCTAssertNil(MeetingHelpers.speaker(in: "Mute audio"))
    }

    func testSpeakersAreListedOnce() {
        XCTAssertEqual(MeetingHelpers.speakers(in: ["Ana, speaking", "Mute audio", "Ana is speaking", "Bob, Speaking"]),
                       ["Ana", "Bob"])
        XCTAssertEqual(MeetingHelpers.speakers(in: ["Chat", "Leave"]), [])
    }

    // MARK: Chat

    func testChatLinesInEachLanguage() {
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "From Ana López to Everyone: Can you hear me?"),
                       ChatMessage(name: "Ana López", text: "Can you hear me?"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "De Luis a Todos: hola a todos"),
                       ChatMessage(name: "Luis", text: "hola a todos"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "De Élodie à Tout le monde : bonjour"),
                       ChatMessage(name: "Élodie", text: "bonjour"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "Von Jürgen an Alle: Hallo"),
                       ChatMessage(name: "Jürgen", text: "Hallo"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "Bob: see you at 10:30"),
                       ChatMessage(name: "Bob", text: "see you at 10:30"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromLine: "Chen Wei said Thanks everyone"),
                       ChatMessage(name: "Chen Wei", text: "Thanks everyone"))
        XCTAssertNil(MeetingHelpers.chatMessage(fromLine: "10:30 meeting starts"))
        XCTAssertNil(MeetingHelpers.chatMessage(fromLine: "Just some text"))
    }

    func testChatRowsWithSeveralTexts() {
        XCTAssertEqual(MeetingHelpers.chatMessage(fromParts: ["Ana López", "10:32 AM", "Hello there"]),
                       ChatMessage(name: "Ana López", text: "Hello there"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromParts: ["From Bob to Everyone:", "11:02", "Running late"]),
                       ChatMessage(name: "Bob", text: "Running late"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromParts: ["Luis", "to Everyone", "14h05", "Bonjour", "Edited"]),
                       ChatMessage(name: "Luis", text: "Bonjour"))
        XCTAssertEqual(MeetingHelpers.chatMessage(fromParts: ["Petra", "Petra", "Hallo"]),
                       ChatMessage(name: "Petra", text: "Hallo"))
        XCTAssertNil(MeetingHelpers.chatMessage(fromParts: ["10:32 AM"]))
        XCTAssertNil(MeetingHelpers.chatMessage(fromParts: []))
    }

    func testSpokenChatMessage() {
        XCTAssertEqual(ChatMessage(name: "Ana", text: "Hi").spoken, "Ana: Hi")
    }

    func testOwnMessagesAreRecognized() {
        XCTAssertTrue(MeetingHelpers.isOwnMessage(ChatMessage(name: "Me", text: "hi")))
        XCTAssertTrue(MeetingHelpers.isOwnMessage(ChatMessage(name: "Moi", text: "salut")))
        XCTAssertFalse(MeetingHelpers.isOwnMessage(ChatMessage(name: "Ana", text: "hi")))
    }

    func testNewMessages() {
        // The first look reads nothing: no reading the whole history on joining.
        XCTAssertEqual(MeetingHelpers.newMessages(previous: [], current: ["a", "b"]), [])
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["a", "b"], current: ["a", "b"]), [])
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["a", "b"], current: ["a", "b", "c", "d"]), ["c", "d"])
        // Older rows scrolled off the top.
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["a", "b", "c"], current: ["b", "c", "d"]), ["d"])
        // The same text again ("ok" twice) still counts as new.
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["x", "ok"], current: ["x", "ok", "ok"]), ["ok"])
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["ok", "y", "ok"], current: ["ok", "y", "ok", "z", "ok"]), ["z", "ok"])
        // Everything seen is gone: at most five unseen ones.
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["a"], current: ["1", "2", "3", "4", "5", "6"]),
                       ["2", "3", "4", "5", "6"])
        XCTAssertEqual(MeetingHelpers.newMessages(previous: ["a"], current: []), [])
    }

    func testChatAnnouncementsAreOffByDefault() {
        let key = MeetingHelpers.chatAnnounceKey
        XCTAssertEqual(key, "meetingChatAnnounce")
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(MeetingHelpers.chatAnnounceEnabled)
    }

    func testMuteStateWords() {
        XCTAssertEqual(MuteState.muted.spoken, "You're muted")
        XCTAssertEqual(MuteState.unmuted.spoken, "You're unmuted")
        XCTAssertEqual(MeetingHelpers.noMeeting, "No Zoom, Teams or FaceTime meeting is open.")
    }
}
