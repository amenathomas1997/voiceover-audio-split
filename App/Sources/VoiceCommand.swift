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
        /// Run on a spoken no, or no answer: whatever was offered is withdrawn.
        let otherwise: (() -> Void)?
        let until: Date
        var request: SFSpeechAudioBufferRecognitionRequest?
    }
    private var awaitingAnswer: Question?
    /// An answer being said: it counts once the speaker has paused.
    private var answerTimer: Timer?
    /// Tries the microphone again after it couldn't be started.
    private var retryTimer: Timer?
    /// The microphone is opened and closed here, never on the main thread.
    private static let audio = DispatchQueue(label: "VoiceOverAudioSplit.voice-command", qos: .userInitiated)
    /// The microphone is being opened.
    private var starting = false
    /// Counts stops, so a microphone that finishes opening after a stop is put away again.
    private var stops = 0
    /// Asked to listen again while the microphone was still opening for a start since stopped.
    private var startAgain = false
    /// Waiting to hear how the start in progress went.
    private var afterStart: [() -> Void] = []

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
    func askYesNo(_ question: String, otherwise: (() -> Void)? = nil, perform: @escaping () -> Void) {
        let words = question + " " + String(localized: "Say yes or no.")
        awaitingAnswer?.otherwise?()
        awaitingAnswer = Question(perform: perform, otherwise: otherwise, until: Date().addingTimeInterval(60), request: nil)
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
                self.answerTimer?.invalidate()
                asked.otherwise?()
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
                        guard granted else {
                            return Announcer.say(String(localized: "Voice command needs the microphone. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Microphone."))
                        }
                        // At login the microphone may not be there yet: it said it waits, so it does.
                        self.start { if self.wanted, !self.isListening { self.retryLater() } }
                    }
                }
            }
        }
    }

    /// `quiet` is for another try after a failure that has already been announced. The
    /// microphone is opened off the main thread (setting up sound can block for a long time
    /// while a device is asleep, and the main thread carries the keys), so this returns
    /// before listening has begun: `done` is called, on the main thread, once it's known
    /// whether it did.
    private func start(quiet: Bool = false, then done: (() -> Void)? = nil) {
        if let done { afterStart.append(done) }
        guard !isListening else { return started() }
        // The microphone is already being opened: that answers for this start too, unless
        // it was stopped in between, in which case it's opened again afterwards.
        guard !starting else {
            startAgain = true
            return
        }
        func say(_ text: String) { if !quiet { Announcer.say(text) } }
        // On-device only: the language of the Mac if it can, otherwise English.
        let candidates = [SFSpeechRecognizer(locale: Locale.current), SFSpeechRecognizer(locale: Locale(identifier: "en-US"))]
        guard let recognizer = candidates.compactMap({ $0 }).first(where: \.supportsOnDeviceRecognition) else {
            say(String(localized: "Voice command isn't available: this Mac can't recognize speech on the device."))
            return started()
        }
        guard let microphone = Self.builtInMicrophone() else {
            if !quiet { log("Voice command: no built-in microphone; not listening, to keep Bluetooth headsets at full quality.") }
            say(String(localized: "Voice command waits for a built-in or wired microphone, so your Bluetooth headphones keep their full sound quality."))
            return started()
        }
        starting = true
        startAgain = false
        let mine = stops
        let current = currentRequest
        let began = Date()
        Self.audio.async {
            let opened = Self.openMicrophone(microphone, appendingTo: current)
            DispatchQueue.main.async {
                let took = Date().timeIntervalSince(began)
                if took > 2 { log("Voice command: the microphone took \(Int(took)) seconds to open.") }
                self.starting = false
                guard mine == self.stops else {
                    // Stopped while the microphone was opening: put it away. If listening
                    // has been asked for again since, open it afresh.
                    if case .success(let engine) = opened { Self.closeMicrophone(engine) }
                    return self.startAgain ? self.start(quiet: quiet) : self.started()
                }
                self.startAgain = false
                self.finishStart(opened, recognizer: recognizer, quiet: quiet)
                self.started()
            }
        }
    }

    /// Tells whoever asked for a start that it's over, whether or not listening began.
    private func started() {
        let waiting = afterStart
        afterStart = []
        waiting.forEach { $0() }
    }

    private enum MicrophoneFailure: Error { case device, format, start }

    /// Opens the built-in microphone, feeding whatever the current request is. On the audio queue.
    private static func openMicrophone(_ microphone: AudioDeviceID,
                                       appendingTo current: OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>)
        -> Result<AVAudioEngine, MicrophoneFailure> {
        let engine = AVAudioEngine()
        var device = microphone
        // If the built-in microphone can't be chosen, don't fall back to a Bluetooth headset's.
        // (Reaching for the input can itself throw an Objective-C exception while devices change.)
        var unit: AudioUnit?
        _ = VOACatchException({ unit = engine.inputNode.audioUnit }, nil)
        guard let unit,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            return .failure(.device)
        }
        guard installTap(on: engine, appendingTo: current) else { return .failure(.format) }
        var started = false
        // Starting can also throw an Objective-C exception; that mustn't close the app.
        let caught = VOACatchException({
            do { try engine.start(); started = true } catch { started = false }
        }, nil)
        guard caught, started else {
            _ = VOACatchException({ engine.inputNode.removeTap(onBus: 0) }, nil)
            return .failure(.start)
        }
        return .success(engine)
    }

    /// Removing a tap can throw an Objective-C exception when the microphone has just
    /// changed, which is exactly when this runs.
    private static func closeMicrophone(_ engine: AVAudioEngine) {
        audio.async {
            _ = VOACatchException({ engine.inputNode.removeTap(onBus: 0) }, nil)
            _ = VOACatchException({ engine.stop() }, nil)
        }
    }

    private func finishStart(_ opened: Result<AVAudioEngine, MicrophoneFailure>, recognizer: SFSpeechRecognizer, quiet: Bool) {
        let engine: AVAudioEngine
        switch opened {
        case .failure(.device):
            if !quiet {
                log("Voice command: couldn't choose the built-in microphone.")
                Announcer.say(String(localized: "Voice command couldn't use the built-in microphone."))
            }
            return
        case .failure(.format):
            if !quiet { log("Voice command: the microphone's format wasn't accepted.") }
            return failedToListen(quiet: quiet)
        case .failure(.start):
            if !quiet { log("Voice command: microphone couldn't start.") }
            return failedToListen(quiet: quiet)
        case .success(let opened):
            engine = opened
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
            guard keep.0 || keep.1 != nil || keep.2 != nil else { return }
            self.start {
                // A question still waiting is answered on the new request.
                if self.awaitingAnswer?.request != nil { self.awaitingAnswer?.request = self.request }
                // Always-on listening that couldn't restart (no microphone yet) tries again.
                if self.wanted, !self.isListening { self.retryLater() }
            }
        }
        log("Voice command: listening on the device.")
        listen()
        // A question asked while the microphone was still opening is answered on this
        // request, as long as the question has finished being spoken.
        if awaitingAnswer != nil, awaitingAnswer?.request == nil, Date() >= Announcer.speakingUntil {
            awaitingAnswer?.request = request
        }
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
    private func failedToListen(quiet: Bool = false) {
        engine = nil
        isListening = false
        if !quiet {
            Announcer.say(String(localized: "Voice commands couldn't start the microphone, so they're off for now. The rest of the app works as usual. Try turning voice commands on again in Settings."))
        }
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
            // Decided on everything said, once the speaker has paused. Acting on the words
            // as they arrived could take "say yes" out of the app's own "Say yes or no" when
            // that was spoken more slowly than expected, or the first half of "yes… no, wait".
            answerTimer?.invalidate()
            if final { return decide(text, for: waiting.id) }
            let pause = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
                self?.decide(text, for: waiting.id)
            }
            RunLoop.main.add(pause, forMode: .common)
            answerTimer = pause
            return
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
        // In every run loop mode, so a command heard while a dialog or menu is open still runs.
        let pause = Timer(timeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.perform(self.pendingCommand)
        }
        RunLoop.main.add(pause, forMode: .common)
        pauseTimer = pause
    }

    /// Whether a pause-complete phrase answers a question: true for yes, false for no, nil
    /// for anything else. A short, clear answer: "yes", "no", "yes please". Not both (the
    /// question's own "say yes or no"), and not a sentence.
    static func answer(in text: String) -> Bool? {
        guard VoiceCommands.normalize(text).split(separator: " ").count <= 4 else { return nil }
        let yes = VoiceCommands.says(text, any: VoiceCommands.yes), no = VoiceCommands.says(text, any: VoiceCommands.no)
        return yes == no ? nil : yes
    }

    private func decide(_ text: String, for id: UUID) {
        guard let waiting = awaitingAnswer, waiting.id == id else { return }
        guard let yes = Self.answer(in: text) else {
            // Not an answer (other talk, or the question itself heard): listen afresh for one.
            listen()
            awaitingAnswer?.request = request
            return
        }
        awaitingAnswer = nil
        if yes, VoiceGuard.isAtRisk() {
            // Someone in the call could have said it.
            waiting.otherwise?()
            Tones.play(.quieter)
            Announcer.say(String(localized: "A call is playing through the speakers, so I can't take a spoken yes: someone in the call could have said it. Nothing was done."))
        } else if yes {
            Tones.play(.louder)
            waiting.perform()
        } else {
            waiting.otherwise?()
            Announcer.say(String(localized: "Cancelled"))
        }
        listen()
        stopIfNotWanted()
    }

    private func perform(_ command: String) {
        pauseTimer?.invalidate()
        pendingCommand = ""
        // The voice command key was pressed for this one, so it comes from the person at the Mac.
        let byKey = oneShotUntil != nil
        oneShotUntil = nil
        // One phrase is heard several times as it's recognized; act once.
        guard Date().timeIntervalSince(lastHeard) > 2 else { return }
        lastHeard = Date()
        // With a call on the loudspeakers, the microphone hears the other people too.
        let callCouldSayIt = !byKey && VoiceGuard.isAtRisk()
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
            guard !callCouldSayIt else { return refuseOnSpeakers() }
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
        guard !(callCouldSayIt && action.guarded) else { return refuseOnSpeakers() }
        if let question = action.confirm { return askYesNo(question, perform: action.perform) }
        Tones.play(.status)
        action.perform()
    }

    private func refuseOnSpeakers() {
        log("Voice command: not taken while a call plays through the speakers.")
        Tones.play(.quieter)
        Announcer.say(String(localized: "A call is playing through the speakers, so I didn't do that: someone in the call could have said it. Press the Listen for a Voice Command key first, or use headphones."))
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
        answerTimer?.invalidate()
        answerTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        task?.cancel()
        task = nil
        request = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine { Self.closeMicrophone(engine) }
        engine = nil
        isListening = false
        // A microphone still being opened is put away when it arrives.
        stops += 1
        startAgain = false
    }

    /// The microphone couldn't be started (none built in yet after waking, the lid closed):
    /// try again quietly, less and less often, for as long as voice commands are wanted.
    /// Without this, always-on listening stayed off until the setting was switched off and on.
    private func retryLater(after seconds: TimeInterval = 10) {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.wanted, !self.isListening else { return }
            self.start(quiet: true) {
                guard self.wanted else { return }
                if self.isListening {
                    log("Voice command: listening again.")
                } else {
                    self.retryLater(after: min(seconds * 2, 120))
                }
            }
        }
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

// MARK: - Calls on loudspeakers

/// With a call on the loudspeakers, the microphone hears the other people too, so one of
/// them could say "Audio Split, unmute me" or "camera on". While that can happen, commands
/// that reveal you or act for you aren't taken by voice alone: the voice command key (which
/// only the person at the Mac can press) still works, and so do headphones.
enum VoiceGuard {
    static func isAtRisk() -> Bool {
        Preferences.shared.voiceCommandGuard && !outputIsHeadphones() && callIsOn()
    }

    static func outputIsHeadphones() -> Bool {
        let device = defaultOutputDevice()
        var addr = address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
        var source: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &source) != noErr { source = 0 }
        return isHeadphones(name: readString(device, kAudioObjectPropertyName) ?? "",
                            transport: readValue(device, kAudioDevicePropertyTransportType, default: UInt32(0)),
                            dataSource: source)
    }

    /// Whether sound from this output stays in your ears. Anything that isn't clearly
    /// headphones counts as loudspeakers, which is the careful way to be wrong.
    static func isHeadphones(name: String, transport: UInt32, dataSource: UInt32) -> Bool {
        let name = name.lowercased()
        if ["speak", "lautsprecher", "altavo", "haut-parleur", "soundbar", "homepod"].contains(where: name.contains) { return false }
        if ["headphone", "headset", "airpods", "earbud", "earpods", "earphone", "buds",
            "kopfhörer", "auricular", "casque", "écouteur"].contains(where: name.contains) { return true }
        switch transport {
        // The Mac's own socket says what's plugged in: 'hdpn' is headphones.
        case kAudioDeviceTransportTypeBuiltIn: return dataSource == 0x6864_706E
        // Mostly headsets; a Bluetooth speaker usually says so in its name.
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return true
        default: return false
        }
    }

    private static let browsers = ["com.apple.Safari", "com.apple.WebKit", "com.google.Chrome", "org.mozilla.firefox",
                                   "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser"]

    /// Whether a call is going: a call app with sound running, or a web browser using the
    /// microphone (a meeting in a web page).
    static func callIsOn() -> Bool {
        func running(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
            readValue(object, selector, default: UInt32(0)) != 0
        }
        let calls = CallCaptions.callProcesses(prefixes: Preferences.shared.callApps.map(\.bundleID))
        if calls.contains(where: { running($0, kAudioProcessPropertyIsRunning) }) { return true }
        return audioProcesses().contains { process in
            browsers.contains(where: process.bundleID.hasPrefix) && running(process.object, kAudioProcessPropertyIsRunningInput)
        }
    }
}
