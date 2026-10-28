// VoiceCommand.swift — listening for voice commands: "Audio Split" and a command (see
// VoiceCommands.swift), or "Launch VoiceOver training" on its own. Always listening once
// turned on in Settings or the setup guide; otherwise the "Listen for a voice command"
// key listens for one command, without the wake word.
// Listening is done on the Mac (on-device speech recognition): nothing is recorded,
// saved or sent. It uses the Mac's built-in microphone, because using AirPods' or
// another Bluetooth headset's microphone would drop their sound to low quality; with
// only a Bluetooth microphone, it waits until another one is available.

import AppKit
import AVFoundation
import CoreAudio
import Speech
import os

final class VoiceCommand {
    static let shared = VoiceCommand()

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    /// The audio thread appends to the current request while the main thread replaces it.
    private let currentRequest = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private var request: SFSpeechAudioBufferRecognitionRequest? {
        get { currentRequest.withLock { $0 } }
        set { currentRequest.withLock { $0 = newValue } }
    }
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var configurationObserver: Any?
    private var lastHeard = Date.distantPast
    private(set) var isListening = false
    private var wanted = false
    /// Push-to-talk: until this time, the next thing said is a command, no wake word needed.
    private var oneShotUntil: Date?
    /// A command being said: it's acted on once the speaker pauses.
    private var pendingCommand = ""
    private var pauseTimer: Timer?
    /// The app (or VoiceOver for it) was speaking: what was heard then is dropped.
    private var heardOwnSpeech = false

    /// A question waiting for yes or no. Answers count only in a recognition task started
    /// after the question was spoken, so the question itself ("Say yes or no") can't answer it.
    private struct Question {
        let id = UUID()
        let perform: () -> Void
        let until: Date
        var request: SFSpeechAudioBufferRecognitionRequest?
    }
    private var awaitingAnswer: Question?

    /// Starts or stops listening to match the setting.
    func update(enabled: Bool) {
        guard enabled != wanted else { return }
        wanted = enabled
        enabled ? requestThenStart() : stop()
    }

    /// Push-to-talk: listen for one command, without the wake word.
    func listenOnce() {
        oneShotUntil = Date().addingTimeInterval(8)
        // A tone only: spoken words could be heard as the command.
        Tones.play(.status)
        if isListening { listen() } else { requestThenStart(oneShot: true) } // A fresh start: older talk doesn't count.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { [weak self] in
            guard let self, let until = self.oneShotUntil, until <= Date() else { return }
            self.oneShotUntil = nil
            self.stopIfNotWanted()
        }
    }

    /// Asks a question out loud and acts on a spoken yes; no, or nothing within 8 seconds, cancels.
    func askYesNo(_ question: String, perform: @escaping () -> Void) {
        let words = question + " " + String(localized: "Say yes or no.")
        awaitingAnswer = Question(perform: perform, until: Date().addingTimeInterval(60), request: nil)
        Tones.play(.status)
        Announcer.say(words)
        if !isListening { requestThenStart(oneShot: true) }
        // Once the question has been said, listen afresh for the answer.
        let spoken = Announcer.speakingUntil.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + max(spoken, 1)) { [weak self] in
            guard let self, let asked = self.awaitingAnswer else { return }
            // The question itself may have been heard: that's over now, so the fresh
            // request below must not be thrown away as the app's own speech.
            self.heardOwnSpeech = false
            self.listen()
            self.awaitingAnswer?.request = self.request
            // Eight seconds for an answer, whether or not the microphone came up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                guard self.awaitingAnswer?.id == asked.id else { return }
                self.awaitingAnswer = nil
                Announcer.say(String(localized: "No answer, so I didn't do it."))
                self.stopIfNotWanted()
            }
        }
    }

    private func stopIfNotWanted() {
        guard !wanted, awaitingAnswer == nil, (oneShotUntil.map { $0 <= Date() } ?? true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.wanted, self.awaitingAnswer == nil else { return }
            self.stop()
        }
    }

    private func requestThenStart(oneShot: Bool = false) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard self.wanted || oneShot else { return }
                guard status == .authorized else {
                    return Announcer.say(String(localized: "Voice command needs Speech Recognition. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Speech Recognition."))
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard self.wanted || oneShot else { return }
                        granted ? self.start() : Announcer.say(String(localized: "Voice command needs the microphone. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Microphone."))
                    }
                }
            }
        }
    }

    private func start() {
        guard !isListening else { return }
        // On-device only: the language of the Mac if it can, otherwise English.
        let candidates = [SFSpeechRecognizer(locale: Locale.current), SFSpeechRecognizer(locale: Locale(identifier: "en-US"))]
        guard let recognizer = candidates.compactMap({ $0 }).first(where: \.supportsOnDeviceRecognition) else {
            return Announcer.say(String(localized: "Voice command isn't available: this Mac can't recognize speech on the device."))
        }
        guard let microphone = Self.builtInMicrophone() else {
            log("Voice command: no built-in microphone; not listening, to keep Bluetooth headsets at full quality.")
            return Announcer.say(String(localized: "Voice command waits for a built-in or wired microphone, so your Bluetooth headphones keep their full sound quality."))
        }
        let engine = AVAudioEngine()
        var device = microphone
        // If the built-in microphone can't be chosen, don't fall back to a Bluetooth headset's.
        guard let unit = engine.inputNode.audioUnit,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            log("Voice command: couldn't choose the built-in microphone.")
            return Announcer.say(String(localized: "Voice command couldn't use the built-in microphone."))
        }
        guard Self.installTap(on: engine, appendingTo: currentRequest) else {
            log("Voice command: the microphone's format wasn't accepted.")
            return failedToListen()
        }
        var startError: NSError?
        var started = false
        // Starting can also throw an Objective-C exception; that mustn't close the app.
        let caught = VOACatchException({
            do { try engine.start(); started = true } catch { started = false }
        }, &startError)
        guard caught, started else {
            _ = VOACatchException({ engine.inputNode.removeTap(onBus: 0) }, nil)
            log("Voice command: microphone couldn't start.")
            return failedToListen()
        }
        self.engine = engine
        self.recognizer = recognizer
        isListening = true
        // A microphone change (closing the lid, plugging something in) stops the engine: start again.
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                       queue: .main) { [weak self] _ in
            guard let self, self.isListening else { return }
            let keep = (self.wanted, self.oneShotUntil, self.awaitingAnswer)
            self.stop()
            (self.oneShotUntil, self.awaitingAnswer) = (keep.1, keep.2)
            if keep.0 || keep.1 != nil || keep.2 != nil { self.start() }
            // A question still waiting is answered on the new request.
            if self.awaitingAnswer?.request != nil { self.awaitingAnswer?.request = self.request }
        }
        log("Voice command: listening on the device.")
        listen()
    }

    /// Listens to the input with a format it accepts. Some Macs (and newer macOS versions)
    /// reject the format the input reports right after its device is changed, by throwing an
    /// Objective-C exception that would end the app: catch it, and try the formats in turn.
    private static func installTap(on engine: AVAudioEngine,
                                   appendingTo current: OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>) -> Bool {
        let input = engine.inputNode
        let block: AVAudioNodeTapBlock = { buffer, _ in current.withLock { $0 }?.append(buffer) }
        let hardware = input.inputFormat(forBus: 0)
        var candidates: [AVAudioFormat?] = [nil] // The input's own current format.
        if hardware.sampleRate > 0, hardware.channelCount > 0 { candidates.append(hardware) }
        let output = input.outputFormat(forBus: 0)
        if output.sampleRate > 0, output.channelCount > 0 { candidates.append(output) }
        for format in candidates {
            var error: NSError?
            if VOACatchException({ input.installTap(onBus: 0, bufferSize: 2048, format: format, block: block) }, &error) {
                return true
            }
            log("Voice command: tap format rejected: \(error?.localizedDescription ?? "unknown").")
            _ = VOACatchException({ input.removeTap(onBus: 0) }, nil)
        }
        return false
    }

    /// Listening couldn't start: voice commands stay off this time, and say so once.
    private func failedToListen() {
        engine = nil
        isListening = false
        Announcer.say(String(localized: "Voice commands couldn't start the microphone, so they're off for now. The rest of the app works as usual. Try turning voice commands on again in Settings."))
    }

    /// A new recognition task, replacing the last one.
    private func listen() {
        guard isListening, let recognizer else { return }
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        self.request = request
        // A task can only run for a minute or so; replace it before then (counted from now,
        // so a command being said isn't cut in two by an older timer).
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in self?.listen() }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                let final = result?.isFinal == true
                DispatchQueue.main.async { if self.request === request { self.process(text, final: final, from: request) } }
            }
            if error != nil || result?.isFinal == true {
                // Ended (silence, a limit or an error): carry on listening.
                // (A task replaced by a newer one also ends here; leave that one be.)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self.isListening && self.request === request { self.listen() } }
            }
        }
    }

    /// Everything heard so far in this recognition task.
    private func process(_ text: String, final: Bool, from request: SFSpeechAudioBufferRecognitionRequest) {
        // While the app (or VoiceOver for it) is speaking, the microphone may hear it,
        // wake word and all. Drop that, and start afresh once it has finished.
        if Date() < Announcer.speakingUntil {
            heardOwnSpeech = true
            return
        }
        if heardOwnSpeech {
            heardOwnSpeech = false
            return listen()
        }
        if let waiting = awaitingAnswer, waiting.until > Date() {
            guard let asked = waiting.request, asked === request else { return }
            // A short, clear answer: "yes", "no", "yes please". Not both, not a sentence.
            guard VoiceCommands.normalize(text).split(separator: " ").count <= 4 else { return }
            let yes = VoiceCommands.says(text, any: VoiceCommands.yes), no = VoiceCommands.says(text, any: VoiceCommands.no)
            guard yes != no else { return }
            awaitingAnswer = nil
            if yes {
                Tones.play(.louder)
                waiting.perform()
            } else {
                Announcer.say(String(localized: "Cancelled"))
            }
            listen()
            return stopIfNotWanted()
        }
        if Self.isLaunchCommand(text) && VoiceCommands.command(after: text) == nil {
            return launchLessons()
        }
        let pushToTalk = oneShotUntil.map { $0 > Date() } ?? false
        guard let command = VoiceCommands.command(after: text) ?? (pushToTalk ? VoiceCommands.normalize(text) : nil),
              !command.isEmpty else { return }
        // Wait for a short pause, so "speech left" isn't taken as "speech".
        pendingCommand = command
        pauseTimer?.invalidate()
        if final { return perform(command) }
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.perform(self.pendingCommand)
        }
    }

    private func perform(_ command: String) {
        pauseTimer?.invalidate()
        pendingCommand = ""
        oneShotUntil = nil
        // One phrase is heard several times as it's recognized; act once.
        guard Date().timeIntervalSince(lastHeard) > 2 else { return }
        lastHeard = Date()
        defer {
            listen() // Start afresh, so the same words aren't heard again.
            stopIfNotWanted()
        }
        if Self.isLaunchCommand(command) { return launchLessons() }
        // "Set a timer for 10 minutes", "remind me at 3 to call the doctor".
        if VoiceCommands.isReminder(command), Reminders.shared.handle(command) {
            log("Voice command: reminder")
            return
        }
        // "Switch student to Maria": whose lesson progress is used.
        if let name = VoiceCommands.studentName(in: command) {
            log("Voice command: switch student")
            return Announcer.say(LessonProgress.shared.switchTo(named: name)
                ? String(localized: "Now learning: \(LessonProgress.shared.current.name).")
                : String(localized: "There's no student called \(name). Add students in the lessons window."))
        }
        // "Look for my cup", "where are my glasses", "look for the word exit": the camera finder.
        if let target = VoiceCommands.objectRequest(in: command) {
            log("Voice command: object finder")
            return ObjectFinder.start(target: target)
        }
        if let request = VoiceCommands.findRequest(in: command), !request.isEmpty {
            log("Voice command: find")
            Tones.play(.status)
            let model = DoItModel.shared
            model.target = Controller.shared.lastUsedApp
            model.request = request
            model.fromVoice = true
            return model.run()
        }
        guard let action = VoiceCommands.match(command, in: VoiceCommands.all) else {
            Tones.play(.quieter)
            return Announcer.say(String(localized: "Sorry, I didn't catch that."))
        }
        // Only which command ran is logged, never what was said.
        log("Voice command: \(action.name)")
        if let question = action.confirm { return askYesNo(question, perform: action.perform) }
        Tones.play(.status)
        action.perform()
    }

    private func launchLessons() {
        guard Date().timeIntervalSince(lastHeard) > 5 else { return }
        lastHeard = Date()
        listen()
        // Already open: don't start the welcome over.
        if LessonRunner.shared.window?.isVisible == true { return }
        Tones.play(.status)
        NSApp.activate()
        (NSApp.delegate as? AppDelegate)?.showLessons()
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pendingCommand = ""
        oneShotUntil = nil
        awaitingAnswer = nil
        task?.cancel()
        task = nil
        request = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isListening = false
    }

    /// "Launch VoiceOver training", or the same in the Mac's language: a word to start, VoiceOver,
    /// and a word for training or lessons, said as a short phrase. Mentioning "VoiceOver lessons"
    /// in a sentence, or VoiceOver reading the lessons window's name, doesn't count.
    static func isLaunchCommand(_ text: String) -> Bool {
        let words = VoiceCommands.normalize(text.replacingOccurrences(of: "-", with: " "))
            .replacingOccurrences(of: "voice over", with: "voiceover").split(separator: " ").map(String.init)
        let recent = Array(words.suffix(7))
        let starts: Set<String> = ["launch", "open", "start", "begin", "abrir", "abre", "iniciar", "inicia", "empezar", "empieza",
                                   "lancer", "lance", "ouvrir", "ouvre", "demarrer", "demarre", "starten", "starte", "offnen", "offne", "beginnen"]
        let training: Set<String> = ["training", "trainer", "lesson", "lessons", "tutorial",
                                     "entrenamiento", "lecciones", "formation", "lecons", "entrainement", "schulung", "lektionen", "ubung"]
        guard words.count <= 12, recent.contains(where: starts.contains), recent.contains("voiceover") else { return false }
        return recent.contains { word in training.contains(word) || training.contains { word.hasSuffix($0) && word.hasPrefix("voiceover") } }
    }

    /// The Mac's built-in (or a wired USB) microphone, but never a Bluetooth one.
    static func builtInMicrophone() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        let inputs = devices.filter { channelCount($0, scope: kAudioObjectPropertyScopeInput) > 0 }
        func transport(_ device: AudioDeviceID) -> UInt32 { readValue(device, kAudioDevicePropertyTransportType, default: UInt32(0)) }
        return inputs.first { transport($0) == kAudioDeviceTransportTypeBuiltIn }
            ?? inputs.first { transport($0) == kAudioDeviceTransportTypeUSB }
    }
}
