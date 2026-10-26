// VoiceCommands.swift — what "Audio Split, …" can do. Say the wake word, then a
// command, such as "Audio Split, quiet everything" or "Audio Split, what time is it?".
// "Launch VoiceOver training" works without the wake word. Commands work in the Mac's
// language: each has English phrases and the same in Spanish, French or German.
// Risky ones (restarting VoiceOver, switching the output) ask for a yes or no first.

import AppKit

struct VoiceAction {
    /// How it's named in "What can I say?".
    let name: String
    /// Ways to say it, normalized: any one of them in the command picks this action.
    let phrases: [String]
    /// A question to confirm first, or nil to act straight away.
    var confirm: String?
    let perform: () -> Void
}

enum VoiceCommands {
    static let wakeWords = ["audio split", "audiosplit", "audio splits", "audio-split"]

    /// Lowercase, without accents or punctuation, single spaces.
    static func normalize(_ text: String) -> String {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let letters = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// What was said after the last "Audio Split", or nil if it wasn't said.
    static func command(after text: String) -> String? {
        let words = normalize(text).replacingOccurrences(of: "audiosplit", with: "audio split")
        guard let range = words.range(of: "audio split", options: .backwards) else { return nil }
        // "VoiceOver Audio Split" is the app's name, as VoiceOver reads it in window titles.
        if words[..<range.lowerBound].hasSuffix("voiceover ") || words[..<range.lowerBound].hasSuffix("voice over ") { return nil }
        var rest = String(words[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("s ") { rest.removeFirst(2) } // "audio splits"
        return rest
    }

    /// A phrase list: English always, plus the Mac's language, separated by "|".
    static func phrases(_ english: String, _ localized: String) -> [String] {
        Set((english + "|" + localized).split(separator: "|").map { normalize(String($0)) }.filter { !$0.isEmpty }).sorted()
    }

    static let yes = phrases("yes|yeah|yep|confirm|do it|ok|okay",
                             String(localized: "yes|okay|confirm", comment: "Voice answers meaning yes, separated by |"))
    static let no = phrases("no|nope|cancel|stop|never mind",
                            String(localized: "no|cancel|never mind", comment: "Voice answers meaning no, separated by |"))

    /// Whether an answer contains one of these words or phrases, as whole words.
    static func says(_ answer: String, any options: [String]) -> Bool {
        let padded = " " + normalize(answer) + " "
        return options.contains { padded.contains(" " + $0 + " ") }
    }

    /// The action whose phrase appears in the command; the longest phrase wins, so
    /// "speech left" isn't taken for "speech".
    static func match(_ command: String, in actions: [VoiceAction]) -> VoiceAction? {
        let padded = " " + normalize(command) + " "
        let whole = normalize(command)
        var best: (action: VoiceAction, length: Int)?
        for action in actions {
            // One-word phrases ("time", "help", "scan") only when they're the whole command,
            // so "Audio Split is the app I use all the time" does nothing.
            for phrase in action.phrases where (phrase.contains(" ") ? padded.contains(" " + phrase + " ") : whole == phrase)
                && phrase.count > (best?.length ?? 0) {
                best = (action, phrase.count)
            }
        }
        return best?.action
    }

    /// "find the search field" → "the search field", for Do It for Me.
    /// Words that start a timer or reminder, in English, Spanish, French and German.
    static func isReminder(_ command: String) -> Bool {
        let words = normalize(command)
        return ["timer", "remind", "reminder", "temporizador", "recuerdame", "recordatorio", "minuteur", "rappelle",
                "rappel", "erinnere", "erinnerung", "wecker"].contains { words.contains($0) }
    }

    /// What to look for with the camera, from "look for my keys", "where are my glasses" and
    /// the same in Spanish, French and German; nil for anything else.
    static func objectRequest(in command: String) -> String? {
        let words = normalize(command)
        let starts = ["look for ", "where are my ", "where is my ", "where s my ", "busca mi ", "busca mis ", "donde esta mi ",
                      "donde estan mis ", "cherche mon ", "cherche ma ", "cherche mes ", "ou est mon ", "ou est ma ",
                      "ou sont mes ", "suche mein ", "suche meine ", "suche meinen ", "wo ist mein ", "wo ist meine ", "wo sind meine "]
        guard let start = starts.first(where: { words.hasPrefix($0) }) else { return nil }
        let rest = String(words.dropFirst(start.count)).trimmingCharacters(in: .whitespaces)
        // The finder takes the whole phrase, so "look for the word exit" keeps "word".
        return rest.isEmpty ? nil : words
    }

    static func findRequest(in command: String) -> String? {
        let starts = phrases("find|go to|move to|take me to",
                             String(localized: "find|go to", comment: "Voice command words that start a Do It for Me request, separated by |"))
        let text = normalize(command)
        for start in starts.sorted(by: { $0.count > $1.count }) where text.hasPrefix(start + " ") {
            return String(text.dropFirst(start.count + 1))
        }
        return nil
    }

    // MARK: The commands

    private static var app: AppDelegate? { NSApp.delegate as? AppDelegate }
    private static var controller: Controller { Controller.shared }

    static var all: [VoiceAction] {
        var actions: [VoiceAction] = [
            // Rescue
            VoiceAction(name: String(localized: "Turn on VoiceOver"),
                        phrases: phrases("turn on voiceover|start voiceover|voiceover on",
                                         String(localized: "turn on voiceover|start voiceover", comment: "Voice command phrases, separated by |"))) {
                if NSWorkspace.shared.isVoiceOverEnabled { Announcer.say(String(localized: "VoiceOver is already on.")) }
                else { MainActor.assumeIsolated { VoiceOverRescue.restart() } }
            },
            VoiceAction(name: String(localized: "Restart VoiceOver"),
                        phrases: phrases("restart voiceover|reset voiceover|fix voiceover",
                                         String(localized: "restart voiceover", comment: "Voice command phrases, separated by |")),
                        confirm: String(localized: "Restart VoiceOver?")) {
                MainActor.assumeIsolated { VoiceOverRescue.restart() }
            },
            VoiceAction(name: String(localized: "Where am I?"),
                        phrases: phrases("where am i|where is the cursor",
                                         String(localized: "where am i", comment: "Voice command phrases, separated by |"))) {
                WhereAmI.announce()
            },
            VoiceAction(name: String(localized: "Stop talking"),
                        phrases: phrases("stop talking|silence voiceover|be quiet|quiet voiceover",
                                         String(localized: "stop talking|silence voiceover", comment: "Voice command phrases, separated by |"))) {
                if !controller.speechSilenced { controller.toggleSilence() }
            },
            VoiceAction(name: String(localized: "Speak again"),
                        phrases: phrases("speak again|voiceover back|start talking|unsilence",
                                         String(localized: "speak again|start talking", comment: "Voice command phrases, separated by |"))) {
                if controller.speechSilenced { controller.toggleSilence() } else { Announcer.say(String(localized: "VoiceOver is already speaking.")) }
            },
            VoiceAction(name: String(localized: "What can I say?"),
                        phrases: phrases("what can i say|help|voice commands|list commands",
                                         String(localized: "what can i say|help", comment: "Voice command phrases, separated by |"))) {
                Announcer.say(whatCanISay())
            },
            // Hands-free reading and the camera
            VoiceAction(name: String(localized: "Read this page"),
                        phrases: phrases("read this page|scan|scan and read|read this letter|read this document",
                                         String(localized: "read this page|scan", comment: "Voice command phrases, separated by |"))) {
                app?.showScan()
                ScanReader.shared.start()
            },
            VoiceAction(name: String(localized: "What color is this?"),
                        phrases: phrases("what color is this|what colour is this|identify color|what color",
                                         String(localized: "what color is this", comment: "Voice command phrases, separated by |"))) {
                controller.run(.colorIdentifier)
            },
            VoiceAction(name: String(localized: "Read this barcode"),
                        phrases: phrases("read this barcode|read this code|barcode|qr code|read this qr code",
                                         String(localized: "read this barcode|barcode", comment: "Voice command phrases, separated by |"))) {
                if !CodeReader.isRunning { controller.run(.codeReader) }
            },
            VoiceAction(name: String(localized: "Read this label"),
                        phrases: phrases("read this label|read this medicine|read this bottle|medicine label",
                                         String(localized: "read this label", comment: "Voice command phrases, separated by |"))) {
                if !LabelReader.isRunning { controller.run(.labelReader) }
            },
            VoiceAction(name: String(localized: "What money is this?"),
                        phrases: phrases("what money is this|identify money|what note is this|what bill is this",
                                         String(localized: "what money is this", comment: "Voice command phrases, separated by |"))) {
                controller.run(.moneyReader)
            },
            VoiceAction(name: String(localized: "Read the window"),
                        phrases: phrases("read the window|read the screen|read this window|read shared screen",
                                         String(localized: "read the window|read the screen", comment: "Voice command phrases, separated by |"))) {
                controller.run(.readWindow)
            },
            // Sound
            VoiceAction(name: String(localized: "Speech left"),
                        phrases: phrases("speech left|voiceover left|speech in my left ear",
                                         String(localized: "speech left", comment: "Voice command phrases, separated by |"))) {
                controller.setSide(.left)
            },
            VoiceAction(name: String(localized: "Speech right"),
                        phrases: phrases("speech right|voiceover right|speech in my right ear",
                                         String(localized: "speech right", comment: "Voice command phrases, separated by |"))) {
                controller.setSide(.right)
            },
            VoiceAction(name: String(localized: "Split off"),
                        phrases: phrases("split off|turn off the split|stop the split|both ears",
                                         String(localized: "split off", comment: "Voice command phrases, separated by |"))) {
                controller.setSide(nil)
            },
            VoiceAction(name: String(localized: "Quiet everything"),
                        phrases: phrases("quiet everything|quiet all|mute everything|silence everything",
                                         String(localized: "quiet everything", comment: "Voice command phrases, separated by |"))) {
                if !controller.quietAll { controller.toggleQuiet() }
            },
            VoiceAction(name: String(localized: "Sound back"),
                        phrases: phrases("sound back|unquiet|bring sound back|sound on",
                                         String(localized: "sound back", comment: "Voice command phrases, separated by |"))) {
                if controller.quietAll { controller.toggleQuiet() } else { Announcer.say(String(localized: "Sound is already on.")) }
            },
            VoiceAction(name: String(localized: "Mute my microphone"),
                        phrases: phrases("mute my microphone|mute microphone|mute the mic|mute my mic|mic off",
                                         String(localized: "mute my microphone|mute microphone", comment: "Voice command phrases, separated by |"))) {
                if !AudioSystem.isMicMuted { controller.toggleMicrophone() } else { Announcer.say(String(localized: "Your microphone is already muted.")) }
            },
            VoiceAction(name: String(localized: "Unmute"),
                        phrases: phrases("unmute|unmute my microphone|unmute microphone|mic on",
                                         String(localized: "unmute|unmute my microphone", comment: "Voice command phrases, separated by |"))) {
                if AudioSystem.isMicMuted { controller.toggleMicrophone() } else { Announcer.say(String(localized: "Your microphone is already on.")) }
            },
            VoiceAction(name: String(localized: "Next output device"),
                        phrases: phrases("next output device|next output|switch output|change output|next device",
                                         String(localized: "next output device|switch output", comment: "Voice command phrases, separated by |")),
                        confirm: String(localized: "Switch to the next output device?")) {
                controller.nextOutputDevice()
            },
            // Calls and meetings
            VoiceAction(name: String(localized: "Am I muted?"),
                        phrases: phrases("am i muted|am i on mute|mute status|is my mic on",
                                         String(localized: "am i muted|mute status", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.sayMuteStatus()
            },
            VoiceAction(name: String(localized: "Mute me in the meeting"),
                        phrases: phrases("mute me|unmute me|toggle mute|mute the meeting|unmute the meeting",
                                         String(localized: "mute me|unmute me", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.toggleMute()
            },
            VoiceAction(name: String(localized: "Camera on or off"),
                        phrases: phrases("toggle video|camera on|camera off|turn my camera on|turn my camera off|video on|video off",
                                         String(localized: "camera on|camera off", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.toggleVideo()
            },
            VoiceAction(name: String(localized: "Raise my hand"),
                        phrases: phrases("raise my hand|lower my hand|raise hand|lower hand",
                                         String(localized: "raise my hand|lower my hand", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.toggleHand()
            },
            VoiceAction(name: String(localized: "Who's talking?"),
                        phrases: phrases("who s talking|whos talking|who is talking|who is speaking|who s speaking",
                                         String(localized: "who is talking|who is speaking", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.sayWhoIsTalking()
            },
            VoiceAction(name: String(localized: "Read the chat"),
                        phrases: phrases("read the chat|read meeting chat|read the meeting chat|any new messages in the chat",
                                         String(localized: "read the chat", comment: "Voice command phrases, separated by |"))) {
                MeetingHelpers.readChat()
            },
            VoiceAction(name: String(localized: "Leave the meeting"),
                        phrases: phrases("leave the meeting|leave meeting|hang up|end the call",
                                         String(localized: "leave the meeting|hang up", comment: "Voice command phrases, separated by |")),
                        confirm: MeetingHelpers.leaveNeedsConfirmation) {
                MeetingHelpers.leave(confirmed: true)
            },
            VoiceAction(name: String(localized: "Call captions"),
                        phrases: phrases("call captions|caption the call|captions for the call|turn on call captions|turn off call captions",
                                         String(localized: "call captions|caption the call", comment: "Voice command phrases, separated by |"))) {
                MainActor.assumeIsolated { CallCaptions.shared.toggle() }
            },
            VoiceAction(name: String(localized: "What did they say?"),
                        phrases: phrases("what did they say|last caption|read the caption|read the last caption",
                                         String(localized: "what did they say|last caption", comment: "Voice command phrases, separated by |"))) {
                MainActor.assumeIsolated { CallCaptions.shared.readLast() }
            },
            VoiceAction(name: String(localized: "Hearing profile"),
                        phrases: phrases("hearing profile|my hearing profile|hearing test",
                                         String(localized: "hearing profile|hearing test", comment: "Voice command phrases, separated by |"))) {
                app?.showHearingProfile()
            },
            // Everyday tools
            VoiceAction(name: String(localized: "My timers and reminders"),
                        phrases: phrases("what timers are set|list reminders|my reminders|list timers|my timers",
                                         String(localized: "my reminders|my timers", comment: "Voice command phrases, separated by |"))) {
                Reminders.shared.speakList()
            },
            VoiceAction(name: String(localized: "Cancel the timer"),
                        phrases: phrases("cancel the timer|cancel the last reminder|cancel the reminder|stop the timer",
                                         String(localized: "cancel the timer|cancel the reminder", comment: "Voice command phrases, separated by |"))) {
                Reminders.shared.cancelLast()
            },
            VoiceAction(name: String(localized: "Previous clipboard item"),
                        phrases: phrases("previous clipboard|last clipboard item|clipboard history",
                                         String(localized: "previous clipboard|clipboard history", comment: "Voice command phrases, separated by |"))) {
                ClipboardHistory.shared.speak(2)
            },
            VoiceAction(name: String(localized: "Switch window"),
                        phrases: phrases("switch window|switch windows|find a window|list windows",
                                         String(localized: "switch window|list windows", comment: "Voice command phrases, separated by |"))) {
                app?.showWindowSwitcher()
            },
            VoiceAction(name: String(localized: "Stop looking"),
                        phrases: phrases("stop looking|stop finding|stop the object finder",
                                         String(localized: "stop looking", comment: "Voice command phrases, separated by |"))) {
                ObjectFinder.stop()
            },
            // Quick questions
            VoiceAction(name: String(localized: "What time is it?"),
                        phrases: phrases("what time is it|what s the time|whats the time|tell me the time|time",
                                         String(localized: "what time is it", comment: "Voice command phrases, separated by |"))) {
                Announcer.say(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short))
            },
            VoiceAction(name: String(localized: "How's my battery?"),
                        phrases: phrases("how s my battery|hows my battery|battery|battery level",
                                         String(localized: "battery", comment: "Voice command phrases, separated by |"))) {
                Announcer.say(SystemStatus.battery() ?? String(localized: "This Mac has no battery."))
            },
            VoiceAction(name: String(localized: "System status"),
                        phrases: phrases("system status|status",
                                         String(localized: "system status", comment: "Voice command phrases, separated by |"))) {
                controller.announceSystemStatus()
            },
            VoiceAction(name: String(localized: "What's playing?"),
                        phrases: phrases("what s playing|whats playing|what is playing",
                                         String(localized: "what's playing", comment: "Voice command phrases, separated by |"))) {
                controller.announcePlaying()
            },
            VoiceAction(name: String(localized: "What's using my microphone?"),
                        phrases: phrases("what s using my microphone|whats using my microphone|who is using the microphone|what s using the camera|camera and microphone",
                                         String(localized: "what's using my microphone", comment: "Voice command phrases, separated by |"))) {
                SensorWatch.queueSummary()
            },
            VoiceAction(name: String(localized: "What did VoiceOver say?"),
                        phrases: phrases("what did voiceover say|what did it say|say that again",
                                         String(localized: "what did voiceover say", comment: "Voice command phrases, separated by |"))) {
                DispatchQueue.global().async {
                    let last = VoiceOverText.run("return content of last phrase", logErrors: false) ?? ""
                    DispatchQueue.main.async { Announcer.say(last.isEmpty ? String(localized: "VoiceOver hasn't said anything yet.") : last) }
                }
            },
            // The app
            VoiceAction(name: String(localized: "Check for updates"),
                        phrases: phrases("check for updates|check for update|update the app|any updates|is there an update",
                                         String(localized: "check for updates|update the app", comment: "Voice command phrases, separated by |"))) {
                MainActor.assumeIsolated { Updater.shared.check(userInitiated: true) }
            },
            // Learning
            VoiceAction(name: String(localized: "Next lesson"),
                        phrases: phrases("next lesson|start a lesson|continue the lessons",
                                         String(localized: "next lesson", comment: "Voice command phrases, separated by |"))) {
                app?.showLessons()
                LessonRunner.shared.start(LessonRunner.shared.nextLesson)
            },
            VoiceAction(name: String(localized: "Daily practice"),
                        phrases: phrases("daily practice|practice",
                                         String(localized: "daily practice", comment: "Voice command phrases, separated by |"))) {
                app?.showLessons()
                LessonRunner.shared.start(Lesson.daily)
            },
            VoiceAction(name: String(localized: "Repeat that"),
                        phrases: phrases("repeat that|repeat|say it again|again",
                                         String(localized: "repeat that|repeat", comment: "Voice command phrases, separated by |"))) {
                if !LessonRunner.shared.isBetweenLessons { LessonRunner.shared.repeatCurrent() }
                else { Announcer.say(Announcer.lastText.isEmpty ? String(localized: "Nothing to repeat yet.") : Announcer.lastText) }
            },
        ]
        // Presets by name: "Audio Split, meeting preset".
        let presetWord = phrases("preset", String(localized: "preset", comment: "The word preset, as said in a voice command"))
        for preset in Preferences.shared.presets {
            let name = normalize(preset.name)
            guard !name.isEmpty else { continue }
            actions.append(VoiceAction(name: String(localized: "\(preset.name) preset"),
                                       phrases: presetWord.flatMap { ["\(name) \($0)", "\($0) \(name)"] }) {
                controller.applyPreset(preset)
            })
        }
        return actions
    }

    static func whatCanISay() -> String {
        let names = all.map(\.name)
        return String(localized: "Say Audio Split, then a command. For example: \(ListFormatter.localizedString(byJoining: names)). You can also say find, or go to, and the name of a control, and I'll take you there; that uses Do It for Me, which sends the control names to Anthropic. And Launch VoiceOver training works on its own.")
    }
}

/// "Audio Split, where am I?": the app, the window and the item in the VoiceOver cursor.
enum WhereAmI {
    static func announce() {
        let app = Controller.shared.lastUsedApp
        DispatchQueue.global(qos: .userInitiated).async {
            var parts: [String] = []
            if let app, let name = app.localizedName {
                parts.append(String(localized: "You're in \(name)."))
                if let window = AX.element(AX.application(app.processIdentifier), kAXFocusedWindowAttribute) {
                    let title = AX.string(window, kAXTitleAttribute)
                    if !title.isEmpty { parts.append(String(localized: "The window is \(title).")) }
                }
            }
            if let item = VoiceOverText.itemUnderCursor()?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty {
                parts.append(String(localized: "The VoiceOver cursor is on \(item)."))
            }
            let text = parts.isEmpty ? String(localized: "I couldn't tell where you are.") : parts.joined(separator: " ")
            DispatchQueue.main.async { Announcer.say(text) }
        }
    }
}
