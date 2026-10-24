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

final class VoiceCommand {
    static let shared = VoiceCommand()

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var lastHeard = Date.distantPast
    private(set) var isListening = false
    private var wanted = false
    /// Push-to-talk: until this time, the next thing said is a command, no wake word needed.
    private var oneShotUntil: Date?
    /// A command being said: it's acted on once the speaker pauses.
    private var pendingCommand = ""
    private var pauseTimer: Timer?
    /// A risky command waiting for yes or no.
    private var awaitingAnswer: (action: VoiceAction, from: Date, until: Date)?

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
        if !isListening { requestThenStart(oneShot: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { [weak self] in
            guard let self, let until = self.oneShotUntil, until <= Date() else { return }
            self.oneShotUntil = nil
            if !self.wanted { self.stop() }
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
        if let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            return log("Voice command: microphone couldn't start: \(error)")
        }
        self.engine = engine
        self.recognizer = recognizer
        isListening = true
        log("Voice command: listening on the device.")
        listen()
        // A recognition task can only run for a minute or so; start a fresh one regularly.
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in self?.listen() }
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
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                let final = result?.isFinal == true
                DispatchQueue.main.async { if self.request === request { self.process(text, final: final) } }
            }
            if error != nil || result?.isFinal == true {
                // Ended (silence, a limit or an error): carry on listening.
                // (A task replaced by a newer one also ends here; leave that one be.)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self.isListening && self.request === request { self.listen() } }
            }
        }
    }

    /// Everything heard so far in this recognition task.
    private func process(_ text: String, final: Bool) {
        // A yes or no for a risky command, or for a press Do It for Me is waiting on.
        if let waiting = awaitingAnswer, waiting.until > Date() {
            // The question itself ("Say yes or no") mustn't count as the answer.
            guard Date() >= waiting.from else { return }
            let yes = VoiceCommands.says(text, any: VoiceCommands.yes), no = VoiceCommands.says(text, any: VoiceCommands.no)
            guard yes || no else { return }
            awaitingAnswer = nil
            if yes {
                Tones.play(.louder)
                waiting.action.perform()
            } else {
                Announcer.say(String(localized: "Cancelled"))
            }
            listen()
            if !wanted { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if !self.wanted { self.stop() } } }
            return
        }
        if DoItModel.shared.pendingPress != nil, VoiceCommands.says(text, any: VoiceCommands.yes) {
            DoItModel.shared.confirmPress()
            return listen()
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
            if !wanted && awaitingAnswer == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if !self.wanted { self.stop() } } }
        }
        log("Voice command: \(command)")
        if Self.isLaunchCommand(command) { return launchLessons() }
        if let request = VoiceCommands.findRequest(in: command), !request.isEmpty {
            Tones.play(.status)
            let model = DoItModel.shared
            model.target = Controller.shared.lastUsedApp
            model.request = request
            return model.run()
        }
        guard let action = VoiceCommands.match(command, in: VoiceCommands.all) else {
            Tones.play(.quieter)
            return Announcer.say(String(localized: "Sorry, I didn't catch that. Say Audio Split, what can I say."))
        }
        if let question = action.confirm {
            let words = question + " " + String(localized: "Say yes or no.")
            // Answers count once the question has been said, from a fresh start.
            let asked = Date().addingTimeInterval(1 + Double(words.split(separator: " ").count) * 0.35)
            awaitingAnswer = (action, asked, asked.addingTimeInterval(8))
            Tones.play(.status)
            Announcer.say(words)
            DispatchQueue.main.asyncAfter(deadline: .now() + asked.timeIntervalSinceNow) { [weak self] in self?.listen() }
            DispatchQueue.main.asyncAfter(deadline: .now() + asked.timeIntervalSinceNow + 8.5) { [weak self] in
                guard let self, self.awaitingAnswer?.action.name == action.name else { return }
                self.awaitingAnswer = nil
                if !self.wanted { self.stop() }
            }
            return
        }
        Tones.play(.status)
        action.perform()
    }

    private func launchLessons() {
        guard Date().timeIntervalSince(lastHeard) > 5 else { return }
        lastHeard = Date()
        Tones.play(.status)
        NSApp.activate()
        (NSApp.delegate as? AppDelegate)?.showLessons()
        listen()
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isListening = false
    }

    /// "Launch VoiceOver training", or the same in the Mac's language. VoiceOver plus a
    /// word for training or lessons is enough, so it still works if a word is misheard.
    static func isLaunchCommand(_ text: String) -> Bool {
        let words = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "-", with: " ")
        let squeezed = words.replacingOccurrences(of: " ", with: "")
        let saysVoiceOver = squeezed.contains("voiceover")
        let training = ["training", "trainer", "lesson", "lessons", "tutorial",
                        "entrenamiento", "lecciones", "formation", "lecons", "entrainement", "schulung", "lektionen", "ubung"]
        return saysVoiceOver && training.contains { words.contains($0) }
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
